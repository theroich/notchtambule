//
//  ClipboardMonitor.swift
//  NotchTubeAudio
//

import AppKit
import Foundation

/// Polls the system pasteboard (`changeCount`) every 0.6 s and captures universal
/// clipboard entries (``ClipboardItem``) across files, images, URLs, and plain text.
///
/// The pasteboard contents present at launch are deliberately ignored: the
/// first poll only records the current change count.
@MainActor
final class ClipboardMonitor {
    private static let pollInterval: TimeInterval = 0.6

    private let settings: SettingsManager
    private let pasteboard: any PasteboardReading
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredChangeCount: Int?
    private var lastContentHash: String?
    private(set) var lastCapturedItem: ClipboardItem?

    /// Invoked on the main actor whenever a new, non-duplicate clipboard item is captured.
    var onCapture: ((ClipboardItem) -> Void)?

    var isRunning: Bool {
        timer != nil
    }

    init(
        settings: SettingsManager,
        pasteboard: any PasteboardReading = SystemPasteboardReader()
    ) {
        self.settings = settings
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        self.lastContentHash = nil
    }

    func start() {
        stop()

        // The current clipboard content must never trigger a capture at launch.
        lastChangeCount = pasteboard.changeCount

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        // .common keeps polling while menus or the notch panel are tracking events.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        Log.clipboard.info("Monitor del portapapeles iniciado")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Marks a specific `changeCount` (or the next change if `nil`) to be ignored by `poll()`.
    ///
    /// Used when the clipboard manager itself writes an item back to `NSPasteboard`
    /// so it does not trigger a new external capture or plugin prompt.
    func ignoreNextChangeCount(_ count: Int? = nil) {
        if let count {
            ignoredChangeCount = count
        } else {
            ignoredChangeCount = pasteboard.changeCount + 1
        }
    }

    /// Performs a single poll check on the pasteboard.
    ///
    /// Exposed internally so unit tests can drive polling deterministically with a `MockPasteboard`.
    func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if let ignored = ignoredChangeCount, ignored == changeCount {
            ignoredChangeCount = nil
            Log.clipboard.debug("Cambio del portapapeles ignorado (auto-copia changeCount=\(changeCount))")
            return
        }
        ignoredChangeCount = nil

        guard settings.isClipboardMonitoringEnabled else { return }

        let currentTypes = Set(pasteboard.types)

        // Never re-capture writes marked with our own internal marker.
        if currentTypes.contains(PasteboardMarkerType.internalCaptureIgnore) {
            Log.clipboard.debug("Cambio del portapapeles ignorado por marcador interno")
            return
        }

        // 1. Check confidential / transient pasteboard types if privacy filtering is enabled.
        if settings.ignoreConfidentialPasteboardTypes,
           !currentTypes.isDisjoint(with: PasteboardMarkerType.confidentialTypes) {
            Log.clipboard.debug("Contenido confidencial o transitorio ignorado")
            return
        }

        guard let payload = extractPayload() else {
            // Unrecognized content clears consecutive hash deduplication so the previous
            // item can be copied again right afterwards.
            lastContentHash = nil
            return
        }

        let item = ClipboardItem(
            changeCount: changeCount,
            payload: payload,
            sourceApp: pasteboard.frontmostSourceApp()
        )

        // Consecutive identical copies must not emit duplicate events.
        guard item.contentHash != lastContentHash else { return }
        lastContentHash = item.contentHash
        lastCapturedItem = item

        Log.clipboard.info("Elemento del portapapeles capturado: \(item.contentType.rawValue, privacy: .public)")
        onCapture?(item)
    }

    /// Reads the pasteboard immediately, bypassing the automatic monitoring toggle.
    ///
    /// - Parameter force: When `true`, ignores consecutive `contentHash` deduplication.
    func captureCurrentPasteboard(force: Bool = false) -> ClipboardItem? {
        let currentTypes = Set(pasteboard.types)
        if !force,
           settings.ignoreConfidentialPasteboardTypes,
           !currentTypes.isDisjoint(with: PasteboardMarkerType.confidentialTypes) {
            return nil
        }

        guard let payload = extractPayload() else { return nil }

        let item = ClipboardItem(
            changeCount: pasteboard.changeCount,
            payload: payload,
            sourceApp: pasteboard.frontmostSourceApp()
        )

        if !force, item.contentHash == lastContentHash {
            return nil
        }

        lastContentHash = item.contentHash
        lastCapturedItem = item
        return item
    }

    /// Extracts the highest-priority `ClipboardPayload` currently present on the pasteboard.
    ///
    /// Priority order:
    /// 1. File URLs (`isFileURL == true`)
    /// 2. Image data (`.tiff` or `.png`)
    /// 3. Text (`http://` or `https://` valid web URL -> `.url`, otherwise `.text`)
    func extractPayload() -> ClipboardPayload? {
        // 1. File URLs
        let fileURLs = pasteboard.readFileURLs().filter(\.isFileURL)
        if !fileURLs.isEmpty {
            return .files(fileURLs)
        }

        // 2. Image data (.tiff or .png)
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let imagePayload = ImagePayload(data: imageData) {
            return .image(imagePayload)
        }

        // 3. Text or Web URL
        if let raw = pasteboard.string(forType: .string) {
            if let webURL = Self.parseHTTPURL(from: raw) {
                return .url(webURL, rawText: raw)
            }
            return .text(raw)
        }

        return nil
    }

    /// Validates whether a raw pasteboard string is a single valid `http://` or `https://` URL.
    private static func parseHTTPURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: \.isWhitespace),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              let url = components.url
        else {
            return nil
        }
        return url
    }
}

//
//  ClipboardMonitor.swift
//  NotchTubeAudio
//

import AppKit
import Foundation

/// Polls `NSPasteboard.general.changeCount` every 0.6 s looking for YouTube URLs.
///
/// The pasteboard contents present at launch are deliberately ignored: the
/// first poll only records the current change count.
@MainActor
final class ClipboardMonitor {
    private static let pollInterval: TimeInterval = 0.6

    private let settings: SettingsManager
    private var timer: Timer?
    private var lastChangeCount: Int
    private var lastSeenString: String?
    private(set) var lastDetectedLink: YouTubeLink?

    /// Invoked on the main actor whenever a new, different YouTube URL appears.
    var onDetect: ((YouTubeLink) -> Void)?

    var isRunning: Bool {
        timer != nil
    }

    init(settings: SettingsManager) {
        self.settings = settings
        self.lastChangeCount = NSPasteboard.general.changeCount
        self.lastSeenString = nil
    }

    func start() {
        stop()

        // The current clipboard content must never trigger a prompt at launch.
        lastChangeCount = NSPasteboard.general.changeCount

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

    /// Reads the pasteboard immediately. Used by the "force detection" menu item.
    ///
    /// - Parameter force: ignores the "same string twice" deduplication and the
    ///   automatic monitoring toggle.
    func detectCurrentPasteboard(force: Bool) -> YouTubeLink? {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return nil }
        if !force, raw == lastSeenString { return nil }

        lastSeenString = raw
        guard let link = YouTubeURLParser.parse(raw) else { return nil }

        lastDetectedLink = link
        return link
    }

    /// The URL currently on the pasteboard, if it is a valid YouTube link.
    func currentPasteboardLink() -> YouTubeLink? {
        YouTubeURLParser.parsePasteboardString(NSPasteboard.general.string(forType: .string))
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard settings.isClipboardMonitoringEnabled else { return }

        guard let raw = pasteboard.string(forType: .string) else {
            // A non-text item (image, file…) counts as "something else was copied".
            lastSeenString = nil
            return
        }

        // Copying the same text twice without copying anything else in between
        // must not reopen the notch.
        guard raw != lastSeenString else { return }
        lastSeenString = raw

        guard let link = YouTubeURLParser.parse(raw) else { return }

        lastDetectedLink = link
        Log.clipboard.info("URL de YouTube detectada: \(link.canonicalURLString, privacy: .public)")
        onDetect?(link)
    }
}

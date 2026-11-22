//
//  ClipboardStorage.swift
//  NotchTubeAudio
//

import AppKit
import Foundation

/// On-disk persistence manager for ``ClipboardHistoryStore``.
///
/// Stores metadata in `history.json` under `Application Support/NotchTubeAudio/ClipboardHistory/`
/// and offloads `.image` binary payloads into `Images/<UUID>.png` so the JSON index stays small
/// and fast to load. Supports debounced background writes (default 500 ms) so rapid consecutive
/// copies never block `@MainActor`.
@MainActor
final class ClipboardStorage {
    /// Maximum size per image persisted on disk (15 MB) to avoid unbounded disk consumption.
    static let defaultMaxImageBytes: Int = 15 * 1024 * 1024

    let baseDirectory: URL
    let historyFileURL: URL
    let imagesDirectoryURL: URL
    let debounceInterval: TimeInterval
    let maxImageBytes: Int

    private let fileManager: FileManager
    private var debounceTask: Task<Void, Never>?
    private var pendingItems: [ClipboardItem]?

    /// Internal Codable representation used inside `history.json` so `.image` payloads
    /// do not inline megabytes of base64 binary data inside the JSON metadata index.
    private struct StoredEntry: Codable {
        enum Kind: String, Codable {
            case text
            case url
            case files
            case image
        }

        let id: UUID
        let capturedAt: Date
        let changeCount: Int
        let sourceApp: ClipboardSourceApp?
        let isPinned: Bool
        let detectedFeatureIDs: [String]
        let kind: Kind

        // Payload fields
        let text: String?
        let url: URL?
        let rawText: String?
        let fileURLs: [URL]?
        let imageWidth: Double?
        let imageHeight: Double?
        let imageSHA256: String?
        let imageFilename: String?
    }

    init(
        baseDirectory: URL? = nil,
        debounceInterval: TimeInterval = 0.5,
        maxImageBytes: Int = ClipboardStorage.defaultMaxImageBytes,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.debounceInterval = debounceInterval
        self.maxImageBytes = maxImageBytes

        let resolvedBase: URL
        if let baseDirectory {
            resolvedBase = baseDirectory
        } else {
            let appSupport = fileManager
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            resolvedBase = appSupport
                .appendingPathComponent("NotchTubeAudio", isDirectory: true)
                .appendingPathComponent("ClipboardHistory", isDirectory: true)
        }

        self.baseDirectory = resolvedBase
        self.historyFileURL = resolvedBase.appendingPathComponent("history.json", isDirectory: false)
        self.imagesDirectoryURL = resolvedBase.appendingPathComponent("Images", isDirectory: true)
    }

    // MARK: - Loading

    /// Synchronously loads persisted clipboard items from `history.json` and resolves any external
    /// image files from `Images/<UUID>.png`.
    func load() -> [ClipboardItem] {
        guard fileManager.fileExists(atPath: historyFileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: historyFileURL)
            let decoder = JSONDecoder()

            // First try the externalized image index format (`[StoredEntry]`).
            if let entries = try? decoder.decode([StoredEntry].self, from: data) {
                return entries.compactMap(reconstructItem(from:))
            }

            // Fallback compatibility if `[ClipboardItem]` was encoded directly.
            if let directItems = try? decoder.decode([ClipboardItem].self, from: data) {
                return directItems
            }

            Log.clipboard.error("Could not decode history.json")
            return []
        } catch {
            Log.clipboard.error("Error reading clipboard history from disk: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Saving (Debounced & Immediate)

    /// Schedules a debounced background write of the given items.
    func scheduleSave(_ items: [ClipboardItem]) {
        pendingItems = items
        debounceTask?.cancel()

        let delaySeconds = max(0, debounceInterval)
        if delaySeconds == 0 {
            flushPendingSave()
            return
        }

        debounceTask = Task { [weak self] in
            let nanoseconds = UInt64(delaySeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.flushPendingSave()
        }
    }

    /// Cancels any active debounce timer and writes pending items immediately.
    func flushPendingSave() {
        debounceTask?.cancel()
        debounceTask = nil
        guard let items = pendingItems else { return }
        pendingItems = nil
        saveImmediately(items)
    }

    /// Writes the given items to `history.json` and `Images/<UUID>.png` immediately.
    func saveImmediately(_ items: [ClipboardItem]) {
        debounceTask?.cancel()
        debounceTask = nil
        pendingItems = nil

        let baseDir = baseDirectory
        let imagesDir = imagesDirectoryURL
        let historyFile = historyFileURL
        let maxBytes = maxImageBytes

        Self.performWrite(
            items: items,
            baseDirectory: baseDir,
            imagesDirectory: imagesDir,
            historyFileURL: historyFile,
            maxImageBytes: maxBytes
        )
    }

    // MARK: - Cleanup

    /// Removes the cached image file for a specific item ID if one exists on disk.
    func removeImageFile(for itemID: UUID) {
        let imageURL = imageFileURL(for: itemID)
        if fileManager.fileExists(atPath: imageURL.path) {
            try? fileManager.removeItem(at: imageURL)
        }
    }

    /// Removes cached image files for multiple item IDs.
    func removeImageFiles(for itemIDs: [UUID]) {
        for id in itemIDs {
            removeImageFile(for: id)
        }
    }

    /// Deletes `history.json` and all cached images on disk.
    func deleteAllPersistedData() {
        debounceTask?.cancel()
        debounceTask = nil
        pendingItems = nil

        if fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.removeItem(at: baseDirectory)
        }
    }

    /// Returns the expected file path for an item's external image payload (`Images/<UUID>.png`).
    func imageFileURL(for itemID: UUID) -> URL {
        imagesDirectoryURL.appendingPathComponent("\(itemID.uuidString).png", isDirectory: false)
    }

    // MARK: - Private helpers

    private func reconstructItem(from entry: StoredEntry) -> ClipboardItem? {
        let payload: ClipboardPayload
        switch entry.kind {
        case .text:
            guard let text = entry.text else { return nil }
            payload = .text(text)

        case .url:
            guard let url = entry.url else { return nil }
            payload = .url(url, rawText: entry.rawText ?? url.absoluteString)

        case .files:
            guard let urls = entry.fileURLs, !urls.isEmpty else { return nil }
            payload = .files(urls)

        case .image:
            let filename = entry.imageFilename ?? "\(entry.id.uuidString).png"
            let fileURL = imagesDirectoryURL.appendingPathComponent(filename, isDirectory: false)
            guard let imageData = try? Data(contentsOf: fileURL), !imageData.isEmpty else {
                return nil
            }
            let size = CGSize(width: entry.imageWidth ?? 0, height: entry.imageHeight ?? 0)
            let imagePayload = ImagePayload(
                size: size,
                tiffOrPngData: imageData,
                sha256Hash: entry.imageSHA256
            )
            payload = .image(imagePayload)
        }

        return ClipboardItem(
            id: entry.id,
            capturedAt: entry.capturedAt,
            changeCount: entry.changeCount,
            payload: payload,
            sourceApp: entry.sourceApp,
            isPinned: entry.isPinned,
            detectedFeatureIDs: entry.detectedFeatureIDs
        )
    }

    nonisolated private static func performWrite(
        items: [ClipboardItem],
        baseDirectory: URL,
        imagesDirectory: URL,
        historyFileURL: URL,
        maxImageBytes: Int
    ) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
            try fm.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

            var entries: [StoredEntry] = []
            var activeImageFilenames: Set<String> = []

            for item in items {
                switch item.payload {
                case .text(let text):
                    entries.append(
                        StoredEntry(
                            id: item.id,
                            capturedAt: item.capturedAt,
                            changeCount: item.changeCount,
                            sourceApp: item.sourceApp,
                            isPinned: item.isPinned,
                            detectedFeatureIDs: item.detectedFeatureIDs,
                            kind: .text,
                            text: text,
                            url: nil,
                            rawText: nil,
                            fileURLs: nil,
                            imageWidth: nil,
                            imageHeight: nil,
                            imageSHA256: nil,
                            imageFilename: nil
                        )
                    )

                case .url(let url, let rawText):
                    entries.append(
                        StoredEntry(
                            id: item.id,
                            capturedAt: item.capturedAt,
                            changeCount: item.changeCount,
                            sourceApp: item.sourceApp,
                            isPinned: item.isPinned,
                            detectedFeatureIDs: item.detectedFeatureIDs,
                            kind: .url,
                            text: nil,
                            url: url,
                            rawText: rawText,
                            fileURLs: nil,
                            imageWidth: nil,
                            imageHeight: nil,
                            imageSHA256: nil,
                            imageFilename: nil
                        )
                    )

                case .files(let urls):
                    entries.append(
                        StoredEntry(
                            id: item.id,
                            capturedAt: item.capturedAt,
                            changeCount: item.changeCount,
                            sourceApp: item.sourceApp,
                            isPinned: item.isPinned,
                            detectedFeatureIDs: item.detectedFeatureIDs,
                            kind: .files,
                            text: nil,
                            url: nil,
                            rawText: nil,
                            fileURLs: urls,
                            imageWidth: nil,
                            imageHeight: nil,
                            imageSHA256: nil,
                            imageFilename: nil
                        )
                    )

                case .image(let imagePayload):
                    let binaryData = normalizedPNGData(from: imagePayload.tiffOrPngData)
                    guard binaryData.count <= maxImageBytes else {
                        Log.clipboard.warning("Image omitted from disk persistence because it exceeds limit (\(binaryData.count) bytes)")
                        continue
                    }

                    let filename = "\(item.id.uuidString).png"
                    let fileURL = imagesDirectory.appendingPathComponent(filename, isDirectory: false)
                    activeImageFilenames.insert(filename)

                    if !fm.fileExists(atPath: fileURL.path) {
                        try binaryData.write(to: fileURL, options: .atomic)
                    }

                    entries.append(
                        StoredEntry(
                            id: item.id,
                            capturedAt: item.capturedAt,
                            changeCount: item.changeCount,
                            sourceApp: item.sourceApp,
                            isPinned: item.isPinned,
                            detectedFeatureIDs: item.detectedFeatureIDs,
                            kind: .image,
                            text: nil,
                            url: nil,
                            rawText: nil,
                            fileURLs: nil,
                            imageWidth: imagePayload.width,
                            imageHeight: imagePayload.height,
                            imageSHA256: imagePayload.sha256Hash,
                            imageFilename: filename
                        )
                    )
                }
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(entries)
            try jsonData.write(to: historyFileURL, options: .atomic)

            // Prune orphaned image files no longer referenced by `entries`
            if let existingFiles = try? fm.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil) {
                for fileURL in existingFiles where !activeImageFilenames.contains(fileURL.lastPathComponent) {
                    try? fm.removeItem(at: fileURL)
                }
            }
        } catch {
            Log.clipboard.error("Error saving clipboard history to disk: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated private static func normalizedPNGData(from data: Data) -> Data {
        // Convert TIFF data to PNG when possible so `Images/<UUID>.png` is compact and uniform,
        // while keeping original PNG data untouched so its SHA-256 remains identical.
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        if data.count >= pngSignature.count,
           Array(data.prefix(pngSignature.count)) == pngSignature {
            return data
        }
        if let bitmap = NSBitmapImageRep(data: data),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return png
        }
        return data
    }
}

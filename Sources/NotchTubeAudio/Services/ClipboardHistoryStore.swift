//
//  ClipboardHistoryStore.swift
//  NotchTubeAudio
//

import AppKit
import Foundation
import Observation

/// Categories available in the clipboard history filter bar.
enum ClipboardContentFilter: String, CaseIterable, Identifiable, Sendable, Codable {
    case all
    case text
    case links
    case images
    case files
    case pinned

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .all:
            return "Todo"
        case .text:
            return "Texto"
        case .links:
            return "Enlaces"
        case .images:
            return "Imágenes"
        case .files:
            return "Archivos"
        case .pinned:
            return "Fijados"
        }
    }

    var iconSystemName: String {
        switch self {
        case .all:
            return "tray.full"
        case .text:
            return "doc.text"
        case .links:
            return "link"
        case .images:
            return "photo"
        case .files:
            return "folder"
        case .pinned:
            return "pin.fill"
        }
    }

    /// Evaluates whether a ``ClipboardItem`` belongs to this filter category.
    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            switch item.contentType {
            case .plainText, .colorHex, .codeSnippet:
                return true
            case .url, .image, .fileURLs:
                return false
            }
        case .links:
            return item.contentType == .url
        case .images:
            return item.contentType == .image
        case .files:
            return item.contentType == .fileURLs
        case .pinned:
            return item.isPinned
        }
    }
}

/// Central store that manages clipboard history items, deduplication, pinning,
/// search/category filtering, restoration to `NSPasteboard`, retention limits,
/// and disk persistence via ``ClipboardStorage``.
@MainActor
@Observable
final class ClipboardHistoryStore {
    private(set) var items: [ClipboardItem] = []
    var searchQuery: String = ""
    var selectedFilter: ClipboardContentFilter = .all

    private let settings: SettingsManager
    private let storage: ClipboardStorage
    private let pasteboard: any PasteboardReading
    @ObservationIgnored weak var clipboardMonitor: ClipboardMonitor?

    init(
        settings: SettingsManager,
        storage: ClipboardStorage = ClipboardStorage(),
        pasteboard: any PasteboardReading = SystemPasteboardReader(),
        clipboardMonitor: ClipboardMonitor? = nil
    ) {
        self.settings = settings
        self.storage = storage
        self.pasteboard = pasteboard
        self.clipboardMonitor = clipboardMonitor

        if settings.persistClipboardHistory {
            self.items = storage.load()
            enforceRetentionLimit()
        }
    }

    // MARK: - Filtered view

    /// Computed list applying `selectedFilter` and case-insensitive search across
    /// text, URL, file names/paths, and source application metadata.
    var filteredItems: [ClipboardItem] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        return items.filter { item in
            guard selectedFilter.matches(item) else { return false }
            guard !trimmedQuery.isEmpty else { return true }
            return Self.matchesSearchQuery(item, query: trimmedQuery)
        }
    }

    // MARK: - Core Store Operations

    /// Records a captured clipboard item into the history.
    ///
    /// - If an entry with the same `contentHash` already exists, it is promoted to index 0
    ///   without duplicating, updating its `capturedAt`, `changeCount`, `sourceApp`, and
    ///   merging `detectedFeatureIDs` while preserving its `isPinned` state and `id`.
    /// - If it is new, it is inserted at index 0.
    /// - Enforces `settings.maxClipboardHistoryItems` by purging the oldest unpinned items
    ///   (`!isPinned`) and cleaning up their cached image files on disk.
    func record(_ item: ClipboardItem) {
        if let existingIndex = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            let existing = items.remove(at: existingIndex)
            let mergedFeatures = Self.mergeFeatureIDs(existing: existing.detectedFeatureIDs, incoming: item.detectedFeatureIDs)
            let promoted = ClipboardItem(
                id: existing.id,
                capturedAt: item.capturedAt,
                changeCount: item.changeCount,
                payload: item.payload,
                sourceApp: item.sourceApp ?? existing.sourceApp,
                isPinned: existing.isPinned || item.isPinned,
                detectedFeatureIDs: mergedFeatures
            )
            items.insert(promoted, at: 0)
        } else {
            items.insert(item, at: 0)
        }

        enforceRetentionLimit()
        persistIfNeeded()
    }

    /// Writes the item's `ClipboardPayload` back to the system pasteboard, notifies
    /// ``ClipboardMonitor`` to ignore the internal changeCount, and promotes the item
    /// to the top of the history.
    func copyToPasteboard(_ item: ClipboardItem) {
        // Pre-arm monitor before writing, then update with the exact post-write changeCount.
        clipboardMonitor?.ignoreNextChangeCount()
        let newChangeCount = pasteboard.write(item.payload)
        clipboardMonitor?.ignoreNextChangeCount(newChangeCount)

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            let existing = items.remove(at: index)
            let promoted = ClipboardItem(
                id: existing.id,
                capturedAt: Date(),
                changeCount: newChangeCount,
                payload: existing.payload,
                sourceApp: existing.sourceApp,
                isPinned: existing.isPinned,
                detectedFeatureIDs: existing.detectedFeatureIDs
            )
            items.insert(promoted, at: 0)
        } else {
            let restored = ClipboardItem(
                id: item.id,
                capturedAt: Date(),
                changeCount: newChangeCount,
                payload: item.payload,
                sourceApp: item.sourceApp,
                isPinned: item.isPinned,
                detectedFeatureIDs: item.detectedFeatureIDs
            )
            record(restored)
            return
        }

        persistIfNeeded()
    }

    /// Toggles the `isPinned` flag on the item with the given ID and persists the change.
    func togglePin(_ itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].isPinned.toggle()
        enforceRetentionLimit()
        persistIfNeeded()
    }

    /// Removes a specific item by ID and cleans up any cached image file on disk.
    func remove(_ itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let removed = items.remove(at: index)
        if case .image = removed.payload {
            storage.removeImageFile(for: removed.id)
        }
        persistIfNeeded()
    }

    /// Removes all unpinned items while preserving every pinned entry (`isPinned == true`).
    func clearUnpinned() {
        let removedImageIDs = items
            .filter { !$0.isPinned && $0.contentType == .image }
            .map(\.id)
        items.removeAll { !$0.isPinned }
        storage.removeImageFiles(for: removedImageIDs)
        persistIfNeeded()
    }

    /// Clears the entire clipboard history (including pinned items) and deletes persisted files.
    func clearAll() {
        let removedImageIDs = items
            .filter { $0.contentType == .image }
            .map(\.id)
        items.removeAll()
        storage.removeImageFiles(for: removedImageIDs)
        persistIfNeeded()
    }

    /// Flushes any pending debounced disk write immediately (useful on application shutdown or tests).
    func flushPendingPersistence() {
        if settings.persistClipboardHistory {
            storage.saveImmediately(items)
        } else {
            storage.deleteAllPersistedData()
        }
    }

    // MARK: - Retention & Persistence Helpers

    /// Purges the oldest unpinned items (`!isPinned`) when the total item count exceeds
    /// `settings.maxClipboardHistoryItems`. Pinned items are never automatically purged.
    func enforceRetentionLimit() {
        let maxCount = max(1, settings.maxClipboardHistoryItems)
        guard items.count > maxCount else { return }

        var purgedImageIDs: [UUID] = []

        // Walk from the oldest (end of array) towards the newest (start of array),
        // removing unpinned items until count <= maxCount or only pinned items remain.
        var index = items.count - 1
        while items.count > maxCount, index >= 0 {
            if !items[index].isPinned {
                let removed = items.remove(at: index)
                if case .image = removed.payload {
                    purgedImageIDs.append(removed.id)
                }
            }
            index -= 1
        }

        if !purgedImageIDs.isEmpty {
            storage.removeImageFiles(for: purgedImageIDs)
        }
    }

    private func persistIfNeeded() {
        if settings.persistClipboardHistory {
            storage.scheduleSave(items)
        } else {
            storage.deleteAllPersistedData()
        }
    }

    private static func mergeFeatureIDs(existing: [String], incoming: [String]) -> [String] {
        guard !incoming.isEmpty else { return existing }
        var result = existing
        for id in incoming where !result.contains(id) {
            result.append(id)
        }
        return result
    }

    private static func matchesSearchQuery(_ item: ClipboardItem, query: String) -> Bool {
        if item.previewTitle.localizedCaseInsensitiveContains(query) {
            return true
        }
        if let subtitle = item.previewSubtitle,
           subtitle.localizedCaseInsensitiveContains(query) {
            return true
        }
        if let appName = item.sourceApp?.localizedName,
           appName.localizedCaseInsensitiveContains(query) {
            return true
        }
        if let bundleID = item.sourceApp?.bundleIdentifier,
           bundleID.localizedCaseInsensitiveContains(query) {
            return true
        }

        switch item.payload {
        case .text(let text):
            return text.localizedCaseInsensitiveContains(query)

        case .url(let url, let rawText):
            return url.absoluteString.localizedCaseInsensitiveContains(query)
                || rawText.localizedCaseInsensitiveContains(query)

        case .files(let urls):
            return urls.contains { url in
                url.lastPathComponent.localizedCaseInsensitiveContains(query)
                    || url.path.localizedCaseInsensitiveContains(query)
            }

        case .image:
            return "imagen".localizedCaseInsensitiveContains(query)
                || "image".localizedCaseInsensitiveContains(query)
        }
    }
}

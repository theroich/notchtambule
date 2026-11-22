//
//  ClipboardHistoryStoreTests.swift
//  NotchTubeAudioTests
//

import AppKit
import Foundation
import Testing
@testable import NotchTubeAudio

@MainActor
struct ClipboardHistoryStoreTests {
    private struct TestHarness {
        let store: ClipboardHistoryStore
        let storage: ClipboardStorage
        let monitor: ClipboardMonitor
        let pasteboard: MockPasteboard
        let settings: SettingsManager
        let defaults: UserDefaults
        let suiteName: String
        let tempDirectory: URL

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    private func makeHarness(
        maxHistoryItems: Int = 100,
        persistHistory: Bool = true,
        debounceInterval: TimeInterval = 0
    ) throws -> TestHarness {
        let suiteName = "notchtube.historystore.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsManager(defaults: defaults)
        settings.maxClipboardHistoryItems = maxHistoryItems
        settings.persistClipboardHistory = persistHistory

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTubeClipboardTests-\(UUID().uuidString)", isDirectory: true)

        let storage = ClipboardStorage(
            baseDirectory: tempDirectory,
            debounceInterval: debounceInterval
        )
        let pasteboard = MockPasteboard()
        let monitor = ClipboardMonitor(settings: settings, pasteboard: pasteboard)
        let store = ClipboardHistoryStore(
            settings: settings,
            storage: storage,
            pasteboard: pasteboard,
            clipboardMonitor: monitor
        )

        return TestHarness(
            store: store,
            storage: storage,
            monitor: monitor,
            pasteboard: pasteboard,
            settings: settings,
            defaults: defaults,
            suiteName: suiteName,
            tempDirectory: tempDirectory
        )
    }

    private func makeSamplePNGData(width: Int = 20, height: Int = 14) throws -> Data {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test func deduplicatesByContentHashPromotesToFirstPositionAndPreservesIsPinned() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = t0.addingTimeInterval(10)
        let t2 = t0.addingTimeInterval(20)

        let first = ClipboardItem(
            capturedAt: t0,
            changeCount: 1,
            payload: .text("Elemento A"),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.apple.Notes", localizedName: "Notas"),
            isPinned: true,
            detectedFeatureIDs: ["feature.one"]
        )
        let second = ClipboardItem(
            capturedAt: t1,
            changeCount: 2,
            payload: .text("Elemento B")
        )

        harness.store.record(first)
        harness.store.record(second)

        #expect(harness.store.items.count == 2)
        #expect(harness.store.items[0].payload == .text("Elemento B"))
        #expect(harness.store.items[1].payload == .text("Elemento A"))

        // Re-copying "Elemento A" with a later timestamp and unpinned flag in the raw event
        let duplicateOfFirst = ClipboardItem(
            capturedAt: t2,
            changeCount: 3,
            payload: .text("Elemento A"),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.apple.Safari", localizedName: "Safari"),
            isPinned: false,
            detectedFeatureIDs: ["feature.two"]
        )
        harness.store.record(duplicateOfFirst)

        #expect(harness.store.items.count == 2)
        let promoted = harness.store.items[0]
        #expect(promoted.id == first.id)
        #expect(promoted.payload == .text("Elemento A"))
        #expect(promoted.capturedAt == t2)
        #expect(promoted.changeCount == 3)
        #expect(promoted.isPinned == true)
        #expect(promoted.sourceApp?.localizedName == "Safari")
        #expect(promoted.detectedFeatureIDs == ["feature.one", "feature.two"])
    }

    @Test func retentionLimitPurgesOldestUnpinnedItemsAndPreservesPinnedItems() throws {
        // SettingsManager clamps to minimum 10, so test retention with maxClipboardHistoryItems = 10
        let harness = try makeHarness(maxHistoryItems: 10)
        defer { harness.cleanup() }

        var pinnedIDs: Set<UUID> = []

        // Insert 12 items; pin the earliest 3 items (indices 1, 2, 3)
        for index in 1...12 {
            let isPinned = (index <= 3)
            let item = ClipboardItem(
                capturedAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index)),
                changeCount: index,
                payload: .text("Entrada #\(index)"),
                isPinned: isPinned
            )
            if isPinned {
                pinnedIDs.insert(item.id)
            }
            harness.store.record(item)
        }

        // Max history is 10: total count must be 10
        #expect(harness.store.items.count == 10)

        // All 3 oldest pinned items (#1, #2, #3) must still exist!
        let remainingIDs = Set(harness.store.items.map(\.id))
        #expect(pinnedIDs.isSubset(of: remainingIDs))

        // Unpinned oldest items (#4 and #5) must have been purged instead
        let remainingTexts = Set(harness.store.items.compactMap { $0.payload.stringValue })
        #expect(remainingTexts.contains("Entrada #1"))
        #expect(remainingTexts.contains("Entrada #2"))
        #expect(remainingTexts.contains("Entrada #3"))
        #expect(!remainingTexts.contains("Entrada #4"))
        #expect(!remainingTexts.contains("Entrada #5"))
        #expect(remainingTexts.contains("Entrada #12"))
    }

    @Test func filteredItemsFiltersByCategoryAndSearchQueryInRealTime() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        let textItem = ClipboardItem(
            changeCount: 1,
            payload: .text("Reunión de arquitectura Swift en Madrid"),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.apple.Notes", localizedName: "Notas")
        )
        let hexColorItem = ClipboardItem(
            changeCount: 2,
            payload: .text("#FF5733"),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.bohemiancoding.sketch3", localizedName: "Sketch")
        )
        let linkItem = ClipboardItem(
            changeCount: 3,
            payload: .url(
                try #require(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")),
                rawText: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
            ),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.apple.Safari", localizedName: "Safari"),
            isPinned: true
        )
        let fileItem = ClipboardItem(
            changeCount: 4,
            payload: .files([URL(fileURLWithPath: "/Users/test/Documents/presupuesto_2026.pdf")]),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.apple.finder", localizedName: "Finder")
        )
        let pngData = try makeSamplePNGData(width: 48, height: 32)
        let imagePayload = try #require(ImagePayload(data: pngData))
        let imageItem = ClipboardItem(
            changeCount: 5,
            payload: .image(imagePayload),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.apple.Preview", localizedName: "Vista Previa"),
            isPinned: true
        )

        harness.store.record(textItem)
        harness.store.record(hexColorItem)
        harness.store.record(linkItem)
        harness.store.record(fileItem)
        harness.store.record(imageItem)

        // 1. Filter by category
        harness.store.selectedFilter = .all
        #expect(harness.store.filteredItems.count == 5)

        harness.store.selectedFilter = .text
        #expect(harness.store.filteredItems.map(\.id) == [hexColorItem.id, textItem.id])

        harness.store.selectedFilter = .links
        #expect(harness.store.filteredItems.map(\.id) == [linkItem.id])

        harness.store.selectedFilter = .files
        #expect(harness.store.filteredItems.map(\.id) == [fileItem.id])

        harness.store.selectedFilter = .images
        #expect(harness.store.filteredItems.map(\.id) == [imageItem.id])

        harness.store.selectedFilter = .pinned
        #expect(harness.store.filteredItems.map(\.id) == [imageItem.id, linkItem.id])

        // 2. Search query across text, URL, file name, and source app name (case-insensitive)
        harness.store.selectedFilter = .all

        harness.store.searchQuery = "arquitectura"
        #expect(harness.store.filteredItems.map(\.id) == [textItem.id])

        harness.store.searchQuery = "YOUTUBE"
        #expect(harness.store.filteredItems.map(\.id) == [linkItem.id])

        harness.store.searchQuery = "presupuesto_2026"
        #expect(harness.store.filteredItems.map(\.id) == [fileItem.id])

        harness.store.searchQuery = "safari"
        #expect(harness.store.filteredItems.map(\.id) == [linkItem.id])

        // 3. Combined category + search query
        harness.store.selectedFilter = .pinned
        harness.store.searchQuery = "vista previa"
        #expect(harness.store.filteredItems.map(\.id) == [imageItem.id])
    }

    @Test func copyToPasteboardRestoresContentAndPreventsMonitorInfiniteLoop() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        var monitorCaptures: [ClipboardItem] = []
        harness.monitor.onCapture = { item in
            monitorCaptures.append(item)
            harness.store.record(item)
        }

        // User copies two items externally
        harness.pasteboard.simulateCopyText("Primer texto copiado")
        harness.monitor.poll()

        harness.pasteboard.simulateCopyText("Segundo texto copiado")
        harness.monitor.poll()

        #expect(monitorCaptures.count == 2)
        #expect(harness.store.items.count == 2)
        let firstItem = harness.store.items[1]
        #expect(firstItem.payload == .text("Primer texto copiado"))

        // Restore firstItem back to the pasteboard via store
        harness.store.copyToPasteboard(firstItem)

        // Verify the pasteboard now holds firstItem's payload
        #expect(harness.pasteboard.string(forType: .string) == "Primer texto copiado")
        // Verify firstItem was promoted to index 0 in the history store
        #expect(harness.store.items.first?.id == firstItem.id)

        // Polling the monitor after copyToPasteboard must NOT trigger a new capture!
        harness.monitor.poll()
        #expect(monitorCaptures.count == 2)
        #expect(harness.store.items.count == 2)
    }

    @Test func togglePinRemoveAndClearOperationsUpdateStateAndCleanUpImageFiles() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        let pngData = try makeSamplePNGData(width: 16, height: 16)
        let imagePayload = try #require(ImagePayload(data: pngData))

        let imageItem = ClipboardItem(changeCount: 1, payload: .image(imagePayload))
        let unpinnedText = ClipboardItem(changeCount: 2, payload: .text("Temporal"))
        let pinnedText = ClipboardItem(changeCount: 3, payload: .text("Importante"))

        harness.store.record(imageItem)
        harness.store.record(unpinnedText)
        harness.store.record(pinnedText)

        // Image file should be saved on disk in Images/<UUID>.png
        let imageFileURL = harness.storage.imageFileURL(for: imageItem.id)
        #expect(FileManager.default.fileExists(atPath: imageFileURL.path))

        // Pin `pinnedText`
        harness.store.togglePin(pinnedText.id)
        #expect(harness.store.items.first(where: { $0.id == pinnedText.id })?.isPinned == true)

        // Remove `imageItem` specifically and verify its disk file is deleted
        harness.store.remove(imageItem.id)
        #expect(!harness.store.items.contains(where: { $0.id == imageItem.id }))
        #expect(!FileManager.default.fileExists(atPath: imageFileURL.path))

        // Clear unpinned items -> only `pinnedText` remains
        harness.store.clearUnpinned()
        #expect(harness.store.items.map(\.id) == [pinnedText.id])

        // Clear all items -> empty
        harness.store.clearAll()
        #expect(harness.store.items.isEmpty)
    }

    @Test func persistsAndReloadsHistoryAndExternalImagesFromTemporaryDirectory() async throws {
        let harness = try makeHarness(debounceInterval: 0.05)
        defer { harness.cleanup() }

        let pngData = try makeSamplePNGData(width: 28, height: 18)
        let imagePayload = try #require(ImagePayload(data: pngData))

        let textItem = ClipboardItem(
            changeCount: 10,
            payload: .text("Persistido en JSON"),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.apple.Terminal", localizedName: "Terminal"),
            isPinned: true,
            detectedFeatureIDs: ["json"]
        )
        let urlItem = ClipboardItem(
            changeCount: 11,
            payload: .url(
                try #require(URL(string: "https://swift.org")),
                rawText: "https://swift.org"
            )
        )
        let imageItem = ClipboardItem(
            changeCount: 12,
            payload: .image(imagePayload)
        )

        harness.store.record(textItem)
        harness.store.record(urlItem)
        harness.store.record(imageItem)

        // Wait for the debounced background write to complete
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(FileManager.default.fileExists(atPath: harness.storage.historyFileURL.path))
        #expect(FileManager.default.fileExists(atPath: harness.storage.imageFileURL(for: imageItem.id).path))

        // Instantiate a second store pointing to the same temporary directory
        let reloadedStore = ClipboardHistoryStore(
            settings: harness.settings,
            storage: harness.storage,
            pasteboard: harness.pasteboard
        )

        #expect(reloadedStore.items.count == 3)
        #expect(reloadedStore.items[0].id == imageItem.id)
        #expect(reloadedStore.items[0].contentHash == imageItem.contentHash)
        #expect(reloadedStore.items[1] == urlItem)
        #expect(reloadedStore.items[2] == textItem)
        #expect(reloadedStore.items[2].isPinned == true)
    }
}

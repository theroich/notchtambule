//
//  ClipboardMonitorTests.swift
//  NotchTubeAudioTests
//

import AppKit
import Foundation
import Testing
@testable import NotchTubeAudio

/// In-memory pasteboard double for deterministic unit testing without touching `NSPasteboard.general`.
@MainActor
final class MockPasteboard: PasteboardReading {
    var changeCount: Int = 1
    var types: [NSPasteboard.PasteboardType] = []
    var fileURLs: [URL] = []
    var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
    var stringByType: [NSPasteboard.PasteboardType: String] = [:]
    var sourceApp: ClipboardSourceApp? = ClipboardSourceApp(
        bundleIdentifier: "com.apple.Safari",
        localizedName: "Safari"
    )

    func readFileURLs() -> [URL] {
        fileURLs
    }

    func data(forType dataType: NSPasteboard.PasteboardType) -> Data? {
        dataByType[dataType]
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        stringByType[dataType]
    }

    func frontmostSourceApp() -> ClipboardSourceApp? {
        sourceApp
    }

    // MARK: - Helpers to simulate user copy operations

    func simulateCopyText(
        _ text: String,
        extraTypes: [NSPasteboard.PasteboardType] = [],
        sourceApp: ClipboardSourceApp? = nil
    ) {
        changeCount += 1
        types = [.string] + extraTypes
        fileURLs = []
        dataByType = [:]
        stringByType = [.string: text]
        if let sourceApp {
            self.sourceApp = sourceApp
        }
    }

    func simulateCopyFiles(
        _ urls: [URL],
        extraTypes: [NSPasteboard.PasteboardType] = [],
        sourceApp: ClipboardSourceApp? = nil
    ) {
        changeCount += 1
        types = [.fileURL] + extraTypes
        fileURLs = urls
        dataByType = [:]
        stringByType = [.string: urls.map(\.lastPathComponent).joined(separator: "\n")]
        if let sourceApp {
            self.sourceApp = sourceApp
        }
    }

    func simulateCopyImage(
        _ data: Data,
        type: NSPasteboard.PasteboardType = .png,
        extraTypes: [NSPasteboard.PasteboardType] = [],
        sourceApp: ClipboardSourceApp? = nil
    ) {
        changeCount += 1
        types = [type] + extraTypes
        fileURLs = []
        dataByType = [type: data]
        stringByType = [:]
        if let sourceApp {
            self.sourceApp = sourceApp
        }
    }
}

@MainActor
struct ClipboardMonitorTests {
    private func makeMonitor() throws -> (ClipboardMonitor, MockPasteboard, SettingsManager, UserDefaults, String) {
        let suiteName = "notchtube.clipboard.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsManager(defaults: defaults)
        let pasteboard = MockPasteboard()
        let monitor = ClipboardMonitor(settings: settings, pasteboard: pasteboard)
        return (monitor, pasteboard, settings, defaults, suiteName)
    }

    private func makeSamplePNGData(width: Int = 24, height: Int = 16) throws -> Data {
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

    @Test func detectsPlainTextAndCapturesSourceApp() throws {
        let (monitor, pasteboard, _, defaults, suiteName) = try makeMonitor()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var captured: [ClipboardItem] = []
        monitor.onCapture = { captured.append($0) }

        let notesApp = ClipboardSourceApp(bundleIdentifier: "com.apple.Notes", localizedName: "Notas")
        pasteboard.simulateCopyText("Hola mundo desde el portapapeles", sourceApp: notesApp)
        monitor.poll()

        #expect(captured.count == 1)
        let item = try #require(captured.first)
        #expect(item.payload == .text("Hola mundo desde el portapapeles"))
        #expect(item.contentType == .plainText)
        #expect(item.sourceApp == notesApp)
        #expect(item.changeCount == pasteboard.changeCount)
        #expect(item.previewTitle == "Hola mundo desde el portapapeles")
        #expect(item.previewSubtitle?.contains("Notas") == true)
    }

    @Test func detectsGenericWebURLs() throws {
        let (monitor, pasteboard, _, defaults, suiteName) = try makeMonitor()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var captured: [ClipboardItem] = []
        monitor.onCapture = { captured.append($0) }

        pasteboard.simulateCopyText("  https://developer.apple.com/documentation/appkit/nspasteboard  ")
        monitor.poll()

        #expect(captured.count == 1)
        let item = try #require(captured.first)
        let expectedURL = try #require(URL(string: "https://developer.apple.com/documentation/appkit/nspasteboard"))
        #expect(item.payload == .url(expectedURL, rawText: "  https://developer.apple.com/documentation/appkit/nspasteboard  "))
        #expect(item.contentType == .url)
        #expect(item.previewTitle == "developer.apple.com/documentation/appkit/nspasteboard")
        #expect(item.previewSubtitle?.contains("developer.apple.com") == true)
    }

    @Test func detectsFinderFileURLsBeforeFallbackString() throws {
        let (monitor, pasteboard, _, defaults, suiteName) = try makeMonitor()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var captured: [ClipboardItem] = []
        monitor.onCapture = { captured.append($0) }

        let fileA = URL(fileURLWithPath: "/Users/test/Desktop/informe.pdf")
        let fileB = URL(fileURLWithPath: "/Users/test/Desktop/audio.mp3")
        let finderApp = ClipboardSourceApp(bundleIdentifier: "com.apple.finder", localizedName: "Finder")

        pasteboard.simulateCopyFiles([fileA, fileB], sourceApp: finderApp)
        monitor.poll()

        #expect(captured.count == 1)
        let item = try #require(captured.first)
        #expect(item.payload == .files([fileA, fileB]))
        #expect(item.contentType == .fileURLs)
        #expect(item.sourceApp == finderApp)
        #expect(item.previewTitle == "informe.pdf y 1 más")
        #expect(item.previewSubtitle == "Finder · 2 archivos")
    }

    @Test func detectsCopiedImageWithDimensionsAndHash() throws {
        let (monitor, pasteboard, _, defaults, suiteName) = try makeMonitor()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var captured: [ClipboardItem] = []
        monitor.onCapture = { captured.append($0) }

        let pngData = try makeSamplePNGData(width: 32, height: 20)
        let previewApp = ClipboardSourceApp(bundleIdentifier: "com.apple.Preview", localizedName: "Vista Previa")

        pasteboard.simulateCopyImage(pngData, type: .png, sourceApp: previewApp)
        monitor.poll()

        #expect(captured.count == 1)
        let item = try #require(captured.first)
        #expect(item.contentType == .image)
        #expect(item.sourceApp == previewApp)
        #expect(item.previewTitle == "Imagen (32×20)")

        guard case .image(let imagePayload) = item.payload else {
            Issue.record("Se esperaba un payload .image")
            return
        }
        #expect(imagePayload.size == CGSize(width: 32, height: 20))
        #expect(imagePayload.tiffOrPngData == pngData)
        #expect(!imagePayload.sha256Hash.isEmpty)
        #expect(item.contentHash == "image:\(imagePayload.sha256Hash)")
    }

    @Test(arguments: [
        PasteboardMarkerType.concealed,
        PasteboardMarkerType.transient,
        PasteboardMarkerType.autoGenerated,
        PasteboardMarkerType.onePassword
    ])
    func ignoresConfidentialAndTransientPasteboardTypes(_ confidentialType: NSPasteboard.PasteboardType) throws {
        let (monitor, pasteboard, _, defaults, suiteName) = try makeMonitor()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var captured: [ClipboardItem] = []
        monitor.onCapture = { captured.append($0) }

        pasteboard.simulateCopyText("super-secret-password", extraTypes: [confidentialType])
        monitor.poll()

        #expect(captured.isEmpty)
    }

    @Test func ignoresInternalSelfCopyAndIgnoreNextChangeCount() throws {
        let (monitor, pasteboard, _, defaults, suiteName) = try makeMonitor()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var captured: [ClipboardItem] = []
        monitor.onCapture = { captured.append($0) }

        // 1. Ignoring by explicit changeCount
        monitor.ignoreNextChangeCount()
        pasteboard.simulateCopyText("Restaurado desde el historial")
        monitor.poll()
        #expect(captured.isEmpty)

        // 2. Ignoring by internal pasteboard marker type
        pasteboard.simulateCopyText(
            "Restaurado con marcador interno",
            extraTypes: [PasteboardMarkerType.internalCaptureIgnore]
        )
        monitor.poll()
        #expect(captured.isEmpty)

        // 3. Subsequent normal external copy works normally
        pasteboard.simulateCopyText("Copia externa real")
        monitor.poll()
        #expect(captured.count == 1)
        #expect(captured.first?.payload == .text("Copia externa real"))
    }

    @Test func deduplicatesConsecutiveIdenticalCopiesByContentHash() throws {
        let (monitor, pasteboard, _, defaults, suiteName) = try makeMonitor()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var captured: [ClipboardItem] = []
        monitor.onCapture = { captured.append($0) }

        // First copy
        pasteboard.simulateCopyText("Texto repetido")
        monitor.poll()
        #expect(captured.count == 1)

        // Second consecutive copy with same content (even though changeCount incremented)
        pasteboard.simulateCopyText("Texto repetido")
        monitor.poll()
        #expect(captured.count == 1)

        // Different content in between
        pasteboard.simulateCopyText("Otro texto distinto")
        monitor.poll()
        #expect(captured.count == 2)

        // Copying the first text again now emits a new capture
        pasteboard.simulateCopyText("Texto repetido")
        monitor.poll()
        #expect(captured.count == 3)
    }

    @Test func codableRoundTripPreservesClipboardItemAndPayloads() throws {
        let pngData = try makeSamplePNGData(width: 12, height: 12)
        let imagePayload = try #require(ImagePayload(data: pngData))
        let item = ClipboardItem(
            changeCount: 42,
            payload: .image(imagePayload),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.apple.Terminal", localizedName: "Terminal"),
            isPinned: true,
            detectedFeatureIDs: ["youtube", "ocr"]
        )

        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: encoded)
        #expect(decoded == item)
        #expect(decoded.contentHash == item.contentHash)
    }
}

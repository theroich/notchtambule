//
//  OCRFeaturePluginTests.swift
//  NotchTubeAudioTests
//
//  Created by NotchTubeAudio.
//

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import NotchTubeAudio

@MainActor
private final class FakeOCRService: OCRServicing, @unchecked Sendable {
    var resultToReturn: Result<OCRResult, Error> = .success(.empty)
    var artificialDelayNanoseconds: UInt64 = 0
    private(set) var receivedCalls: [(data: Data, options: OCROptions)] = []

    func recognizeText(in imageData: Data, options: OCROptions) async throws -> OCRResult {
        receivedCalls.append((imageData, options))
        if artificialDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: artificialDelayNanoseconds)
        }
        try Task.checkCancellation()
        return try resultToReturn.get()
    }
}

@MainActor
struct OCRFeaturePluginTests {
    private func makeIsolatedOCRSettings() throws -> (OCRSettingsStore, UserDefaults, String) {
        let suiteName = "notchtube.ocr.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = OCRSettingsStore(defaults: defaults)
        return (store, defaults, suiteName)
    }

    private func makeImageItem(
        data: Data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        isPinned: Bool = false
    ) -> ClipboardItem {
        let payload = ImagePayload(
            size: CGSize(width: 200, height: 100),
            tiffOrPngData: data
        )
        return ClipboardItem(
            changeCount: 1,
            payload: .image(payload),
            isPinned: isPinned
        )
    }

    /// Renders crisp black text on a white background in memory as PNG data for Vision integration tests.
    private func renderTextImagePNG(lines: [String], size: CGSize = CGSize(width: 720, height: 240)) throws -> Data {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        )

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 12
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let combined = lines.joined(separator: "\n")
        let textRect = CGRect(x: 36, y: 24, width: size.width - 72, height: size.height - 48)
        NSString(string: combined).draw(in: textRect, withAttributes: attributes)

        NSGraphicsContext.restoreGraphicsState()

        let cgImage = try #require(context.makeImage())
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    // MARK: - 1. Plugin Identity & Detection

    @Test func ocrPluginDetectsOnlyImagePayloads() throws {
        let (store, defaults, suiteName) = try makeIsolatedOCRSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fakeService = FakeOCRService()
        let plugin = OCRFeaturePlugin(settingsStore: store, ocrService: fakeService)

        #expect(plugin.id == "com.notchclip.plugin.ocr")
        #expect(plugin.priority == .normal)
        #expect(plugin.defaultTriggerBehavior == .historyActionOnly)
        #expect(plugin.hasActivityPanel == false)

        let imageItem = makeImageItem()
        let textItem = ClipboardItem(changeCount: 2, payload: .text("Texto normal"))
        let url = try #require(URL(string: "https://example.com/image.png"))
        let urlItem = ClipboardItem(changeCount: 3, payload: .url(url, rawText: url.absoluteString))
        let fileItem = ClipboardItem(changeCount: 4, payload: .files([URL(fileURLWithPath: "/tmp/foto.png")]))

        #expect(plugin.canHandle(imageItem) == true)
        #expect(plugin.canHandle(textItem) == false)
        #expect(plugin.canHandle(urlItem) == false)
        #expect(plugin.canHandle(fileItem) == false)
        #expect(fakeService.receivedCalls.isEmpty)
    }

    // MARK: - 2. Quick Actions

    @Test func quickActionOpensPromptWithoutExecutingOCRAndWorksForPinnedImages() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let (store, defaults, suiteName) = try makeIsolatedOCRSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fakeService = FakeOCRService()
        let plugin = OCRFeaturePlugin(settingsStore: store, ocrService: fakeService)
        let pinnedImage = makeImageItem(isPinned: true)
        let context = FeatureActionContext.noop

        let actions = plugin.quickActions(for: pinnedImage, context: context)
        #expect(actions.count == 1)

        let extractAction = try #require(actions.first)
        #expect(extractAction.title == "Extraer texto")
        #expect(extractAction.iconSystemName == "text.viewfinder")

        extractAction.handler()

        #expect(context.lastPresentedPrompt?.pluginID == "com.notchclip.plugin.ocr")
        #expect(context.lastPresentedPrompt?.item.id == pinnedImage.id)
        #expect(context.writtenPayloads.isEmpty)
        #expect(fakeService.receivedCalls.isEmpty)
    }

    // MARK: - 3. Prompt ViewModel States & Actions

    @Test func promptViewModelShowsRecognizedTextAndCopiesAllOrSelection() async throws {
        let fakeService = FakeOCRService()
        let expectedResult = OCRResult(
            fullText: "Error 404\nNot Found",
            blocks: [
                OCRTextBlock(text: "Error 404", confidence: 0.98),
                OCRTextBlock(text: "Not Found", confidence: 0.96)
            ],
            averageConfidence: 0.97,
            detectedLanguages: ["es-ES", "en-US"]
        )
        fakeService.resultToReturn = .success(expectedResult)

        let context = FeatureActionContext.noop
        var completeCount = 0
        var dismissCount = 0

        let viewModel = OCRPromptViewModel(
            imagePayload: makeImageItem().payload.imagePayloadForTest!,
            options: OCROptions(),
            ocrService: fakeService,
            context: context,
            onComplete: { completeCount += 1 },
            onDismiss: { dismissCount += 1 }
        )

        #expect(viewModel.state == .loading)
        await viewModel.start()
        #expect(viewModel.state == .loaded(expectedResult))

        L10n.withLanguage(.spanish) {
            // Copy selection
            viewModel.selectedText = "Error 404"
            #expect(viewModel.hasSelection == true)
            viewModel.copySelection()
            #expect(context.writtenPayloads.last == .text("Error 404"))
            #expect(completeCount == 1)

            // Copy all
            viewModel.copyAll()
            #expect(context.writtenPayloads.last == .text("Error 404\nNot Found"))
            #expect(completeCount == 2)
            #expect(context.lastNotification?.message == "Texto copiado al portapapeles")
        }

        // Dismiss
        viewModel.dismiss()
        #expect(dismissCount == 1)
    }

    @Test func promptViewModelShowsEmptyStateWhenNoTextDetected() async {
        let fakeService = FakeOCRService()
        fakeService.resultToReturn = .success(.empty)

        let viewModel = OCRPromptViewModel(
            imagePayload: makeImageItem().payload.imagePayloadForTest!,
            options: OCROptions(),
            ocrService: fakeService,
            context: .noop,
            onComplete: {},
            onDismiss: {}
        )

        await viewModel.start()
        #expect(viewModel.state == .empty)
    }

    @Test func promptViewModelShowsErrorStateWhenServiceThrows() async {
        let fakeService = FakeOCRService()
        fakeService.resultToReturn = .failure(OCRError.invalidImageData)

        let viewModel = OCRPromptViewModel(
            imagePayload: makeImageItem().payload.imagePayloadForTest!,
            options: OCROptions(),
            ocrService: fakeService,
            context: .noop,
            onComplete: {},
            onDismiss: {}
        )

        await viewModel.start()
        if case .failed(let message) = viewModel.state {
            #expect(!message.isEmpty)
        } else {
            Issue.record("Expected failed state, got \(viewModel.state)")
        }
    }

    @Test func promptViewModelCancelsInFlightRecognitionOnDismiss() async {
        let fakeService = FakeOCRService()
        fakeService.artificialDelayNanoseconds = 500_000_000
        fakeService.resultToReturn = .success(OCRResult(fullText: "Should not appear"))

        var dismissCount = 0
        let viewModel = OCRPromptViewModel(
            imagePayload: makeImageItem().payload.imagePayloadForTest!,
            options: OCROptions(),
            ocrService: fakeService,
            context: .noop,
            onComplete: {},
            onDismiss: { dismissCount += 1 }
        )

        let runTask = Task {
            await viewModel.start()
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        viewModel.dismiss()
        await runTask.value

        #expect(dismissCount == 1)
        #expect(viewModel.state == .loading)
    }

    // MARK: - 4. Settings Store Persistence

    @Test func ocrSettingsStorePersistsPreferencesInOwnKeys() throws {
        let (store, defaults, suiteName) = try makeIsolatedOCRSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(store.languages == ["es-ES", "en-US"])
        #expect(store.recognitionLevel == .accurate)
        #expect(store.usesLanguageCorrection == true)
        #expect(store.preserveLineBreaks == true)

        store.recognitionLevel = .fast
        store.usesLanguageCorrection = false
        store.preserveLineBreaks = false
        store.setLanguage("fr-FR", enabled: true)
        store.setLanguage("es-ES", enabled: false)

        let reloaded = OCRSettingsStore(defaults: defaults)
        #expect(reloaded.recognitionLevel == .fast)
        #expect(reloaded.usesLanguageCorrection == false)
        #expect(reloaded.preserveLineBreaks == false)
        #expect(reloaded.languages == ["en-US", "fr-FR"])

        // Cannot disable the very last language
        reloaded.setLanguage("en-US", enabled: false)
        reloaded.setLanguage("fr-FR", enabled: false)
        #expect(reloaded.languages == ["fr-FR"])
    }

    // MARK: - 5. Reading Order & Vision Integration

    @Test func visionReadingOrderSortsTopToBottomAndLeftToRight() {
        // Vision coordinates: y=0 bottom, y=1 top
        let topLeft = OCRTextBlock(text: "A1", confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.08))
        let topRight = OCRTextBlock(text: "A2", confidence: 1, boundingBox: CGRect(x: 0.6, y: 0.81, width: 0.2, height: 0.08))
        let bottomLeft = OCRTextBlock(text: "B1", confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.08))
        let bottomRight = OCRTextBlock(text: "B2", confidence: 1, boundingBox: CGRect(x: 0.6, y: 0.19, width: 0.2, height: 0.08))

        let sorted = VisionOCRService.sortBlocksInReadingOrder([bottomRight, topRight, bottomLeft, topLeft])
        #expect(sorted.map(\.text) == ["A1", "A2", "B1", "B2"])
    }

    @Test func visionOCRServiceRejectsEmptyAndCorruptImageData() async {
        let service = VisionOCRService()

        await #expect(throws: OCRError.emptyImageData) {
            try await service.recognizeText(in: Data(), options: OCROptions())
        }

        await #expect(throws: OCRError.invalidImageData) {
            try await service.recognizeText(in: Data("not-an-image".utf8), options: OCROptions())
        }
    }

    @Test func visionOCRServiceRecognizesRenderedHighContrastTextAndRespectsLineBreakOption() async throws {
        let pngData = try renderTextImagePNG(lines: ["HELLO VISION", "NOTCH OCR 2026"])
        let service = VisionOCRService()

        let multiline = try await service.recognizeText(
            in: pngData,
            options: OCROptions(
                languages: ["en-US", "es-ES"],
                recognitionLevel: .accurate,
                usesLanguageCorrection: true,
                preserveLineBreaks: true
            )
        )
        let normalizedMultiline = multiline.fullText.uppercased()
        #expect(normalizedMultiline.contains("HELLO"))
        #expect(normalizedMultiline.contains("VISION"))
        #expect(normalizedMultiline.contains("2026"))

        let singleLine = try await service.recognizeText(
            in: pngData,
            options: OCROptions(
                languages: ["en-US"],
                recognitionLevel: .fast,
                usesLanguageCorrection: false,
                preserveLineBreaks: false
            )
        )
        #expect(!singleLine.fullText.contains("\n"))
        #expect(singleLine.fullText.uppercased().contains("HELLO"))
    }

    // MARK: - 6. Layout & Localization Rendering

    @Test func ocrPromptAndSettingsViewsRenderInSpanishEnglishAndPseudolocalization() throws {
        let (store, defaults, suiteName) = try makeIsolatedOCRSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let plugin = OCRFeaturePlugin(settingsStore: store, ocrService: FakeOCRService())
        let imageItem = makeImageItem()

        for (language, pseudo) in [(AppLanguage.spanish, false), (.english, false), (.english, true)] {
            L10n.withLanguage(language, pseudolocalized: pseudo) {
                let promptView = plugin.makePromptView(
                    for: imageItem,
                    context: .noop,
                    onComplete: {},
                    onDismiss: {}
                )
                #expect(promptView != nil)

                if let promptView {
                    let hosting = NSHostingView(
                        rootView: promptView.frame(width: NotchMetrics.contentWidth)
                    )
                    hosting.layoutSubtreeIfNeeded()
                    #expect(hosting.fittingSize.width == NotchMetrics.contentWidth)
                    #expect(hosting.fittingSize.height > 0)
                }

                if let settingsView = plugin.makeSettingsView() {
                    let settingsHosting = NSHostingView(
                        rootView: Form { settingsView }
                            .formStyle(.grouped)
                            .frame(width: 560)
                    )
                    settingsHosting.layoutSubtreeIfNeeded()
                    #expect(settingsHosting.fittingSize.height > 0)
                }
            }
        }
    }
}

private extension ClipboardPayload {
    var imagePayloadForTest: ImagePayload? {
        if case .image(let payload) = self {
            return payload
        }
        return nil
    }
}

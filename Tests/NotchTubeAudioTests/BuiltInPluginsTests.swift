//
//  BuiltInPluginsTests.swift
//  NotchTubeAudioTests
//

import Foundation
import Testing
@testable import NotchTubeAudio

@MainActor
struct BuiltInPluginsTests {
    private func makeIsolatedSettings() throws -> (SettingsManager, UserDefaults, String) {
        let suiteName = "notchtube.builtin.plugins.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsManager(defaults: defaults)
        return (settings, defaults, suiteName)
    }

    private func makeURLItem(_ urlString: String) throws -> ClipboardItem {
        let url = try #require(URL(string: urlString))
        return ClipboardItem(
            changeCount: 1,
            payload: .url(url, rawText: urlString)
        )
    }

    private func makeTextItem(_ text: String) -> ClipboardItem {
        ClipboardItem(
            changeCount: 1,
            payload: .text(text)
        )
    }

    // MARK: - 1. URLCleanerFeaturePlugin

    @Test func urlCleanerDetectsTrackingParametersAndIgnoresCleanURLs() throws {
        let plugin = URLCleanerFeaturePlugin()

        #expect(plugin.id == "com.notchclip.plugin.url-cleaner")
        #expect(plugin.priority == .normal)
        #expect(plugin.defaultTriggerBehavior == .historyActionOnly)

        let trackedYouTube = try makeURLItem("https://www.youtube.com/watch?v=dQw4w9WgXcQ&utm_source=newsletter&utm_medium=email&si=abc123XYZ")
        let trackedArticle = try makeURLItem("https://example.com/post?id=42&fbclid=IwAR12345&gclid=Cj0KCQ&_hsenc=p2ANqtz&mkt_tok=tok123")
        let trackedInTextPayload = makeTextItem("https://example.org/landing?igshid=998877&mc_eid=deadbeef")
        let cleanURL = try makeURLItem("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=45s")
        let plainText = makeTextItem("Esto no es una URL aunque mencione utm_source=test")

        #expect(plugin.canHandle(trackedYouTube) == true)
        #expect(plugin.canHandle(trackedArticle) == true)
        #expect(plugin.canHandle(trackedInTextPayload) == true)
        #expect(plugin.canHandle(cleanURL) == false)
        #expect(plugin.canHandle(plainText) == false)
    }

    @Test func urlCleanerQuickActionStripsTrackingAndPreservesLegitimateQueryParams() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let plugin = URLCleanerFeaturePlugin()
        let item = try makeURLItem("https://www.youtube.com/watch?v=dQw4w9WgXcQ&utm_source=twitter&utm_campaign=launch&fbclid=fb123&gclid=gc456&si=share99&t=120s#section")
        let context = FeatureActionContext.noop

        let actions = plugin.quickActions(for: item, context: context)
        #expect(actions.count == 1)

        let cleanAction = try #require(actions.first)
        #expect(cleanAction.title == "Limpiar URL (quitar tracking)")
        #expect(cleanAction.iconSystemName == "sparkles")

        cleanAction.handler()

        let expectedURL = try #require(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=120s#section"))
        #expect(context.writtenPayloads == [.url(expectedURL, rawText: expectedURL.absoluteString)])
        #expect(context.lastNotification?.icon == "sparkles")
        #expect(context.lastNotification?.message.contains("URL limpia copiada") == true)
    }

    @Test func urlCleanerRemovesEntireQueryStringWhenAllParametersAreTracking() throws {
        let plugin = URLCleanerFeaturePlugin()
        let item = try makeURLItem("https://example.com/blog/articulo?utm_source=rss&utm_medium=feed&mc_eid=12345")
        let context = FeatureActionContext.noop

        let action = try #require(plugin.quickActions(for: item, context: context).first)
        action.handler()

        let expectedURL = try #require(URL(string: "https://example.com/blog/articulo"))
        #expect(context.writtenPayloads == [.url(expectedURL, rawText: "https://example.com/blog/articulo")])
    }

    // MARK: - 2. JSONFormatterFeaturePlugin

    @Test func jsonFormatterDetectsValidJSONObjectsAndArraysAndRejectsInvalidText() throws {
        let plugin = JSONFormatterFeaturePlugin()

        #expect(plugin.id == "com.notchclip.plugin.json-formatter")
        #expect(plugin.priority == .normal)
        #expect(plugin.defaultTriggerBehavior == .historyActionOnly)

        let validObject = makeTextItem(#"{"z":1,"a":{"nested":true}}"#)
        let validArray = makeTextItem(#"  [1, "dos", {"tres": 3}]  "#)
        let invalidJSON = makeTextItem(#"{"unclosed": [1, 2}"#)
        let normalText = makeTextItem("Hola mundo, esto es texto normal")
        let primitiveJSON = makeTextItem("12345")
        let urlItem = try makeURLItem("https://example.com/data.json")

        #expect(plugin.canHandle(validObject) == true)
        #expect(plugin.canHandle(validArray) == true)
        #expect(plugin.canHandle(invalidJSON) == false)
        #expect(plugin.canHandle(normalText) == false)
        #expect(plugin.canHandle(primitiveJSON) == false)
        #expect(plugin.canHandle(urlItem) == false)
    }

    @Test func jsonFormatterPrettifiesWithTwoSpaceIndentationAndSortedKeysAndMinifies() throws {
        let plugin = JSONFormatterFeaturePlugin()
        let rawJSON = #"{"zeta":2,"alfa":{"b":true,"a":"https://example.com/path"}}"#
        let item = makeTextItem(rawJSON)
        let context = FeatureActionContext.noop

        let actions = plugin.quickActions(for: item, context: context)
        #expect(actions.count == 2)
        #expect(actions.map(\.title) == ["Prettify JSON", "Minify JSON"])
        #expect(actions.map(\.iconSystemName) == ["curlybraces", "arrow.down.right.and.arrow.up.left"])

        // 1. Prettify JSON
        actions[0].handler()
        let expectedPretty = """
        {
          "alfa" : {
            "a" : "https://example.com/path",
            "b" : true
          },
          "zeta" : 2
        }
        """
        #expect(context.writtenPayloads.last == .text(expectedPretty))
        #expect(context.lastNotification?.icon == "curlybraces")

        // 2. Minify JSON from pretty-printed input
        let prettyItem = makeTextItem(expectedPretty)
        let minifyActions = plugin.quickActions(for: prettyItem, context: context)
        minifyActions[1].handler()

        let expectedMinified = #"{"alfa":{"a":"https://example.com/path","b":true},"zeta":2}"#
        #expect(context.writtenPayloads.last == .text(expectedMinified))
        #expect(context.lastNotification?.icon == "arrow.down.right.and.arrow.up.left")
    }

    // MARK: - 3. ColorConverterFeaturePlugin

    @Test func colorConverterDetectsHexAndRGBFormatsAndRejectsInvalidColors() {
        let plugin = ColorConverterFeaturePlugin()

        #expect(plugin.id == "com.notchclip.plugin.color-converter")
        #expect(plugin.priority == .low)
        #expect(plugin.defaultTriggerBehavior == .historyActionOnly)

        #expect(plugin.canHandle(makeTextItem("#FF5733")) == true)
        #expect(plugin.canHandle(makeTextItem("  #0f8  ")) == true)
        #expect(plugin.canHandle(makeTextItem("#11223380")) == true)
        #expect(plugin.canHandle(makeTextItem("rgb(255, 87, 51)")) == true)
        #expect(plugin.canHandle(makeTextItem("RGB(0,128,255)")) == true)

        #expect(plugin.canHandle(makeTextItem("#12345")) == false)
        #expect(plugin.canHandle(makeTextItem("#GGGGGG")) == false)
        #expect(plugin.canHandle(makeTextItem("rgb(300, 0, 0)")) == false)
        #expect(plugin.canHandle(makeTextItem("color: #FF5733")) == false)
    }

    @Test func colorConverterConvertsAccuratelyBetweenHexRGBAndSwiftUIColor() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let plugin = ColorConverterFeaturePlugin()
        let context = FeatureActionContext.noop

        // Caso 1: #RRGGBB -> RGB, HEX, SwiftUI Color
        let hexItem = makeTextItem("#ff5733")
        let hexActions = plugin.quickActions(for: hexItem, context: context)
        #expect(hexActions.map(\.title) == [
            "Copiar como RGB",
            "Copiar como HEX",
            "Copiar como SwiftUI Color"
        ])

        hexActions[0].handler()
        #expect(context.writtenPayloads.last == .text("rgb(255, 87, 51)"))

        hexActions[1].handler()
        #expect(context.writtenPayloads.last == .text("#FF5733"))

        hexActions[2].handler()
        #expect(context.writtenPayloads.last == .text("Color(red: 1.000, green: 0.341, blue: 0.200)"))

        // Caso 2: #RGB corto (#0F8 -> R:0x00=0, G:0xFF=255, B:0x88=136)
        let shortHexItem = makeTextItem("#0f8")
        let shortActions = plugin.quickActions(for: shortHexItem, context: context)
        shortActions[0].handler()
        #expect(context.writtenPayloads.last == .text("rgb(0, 255, 136)"))
        shortActions[1].handler()
        #expect(context.writtenPayloads.last == .text("#00FF88"))

        // Caso 3: rgb(r, g, b) -> HEX
        let rgbItem = makeTextItem("rgb(18, 52, 86)")
        let rgbActions = plugin.quickActions(for: rgbItem, context: context)
        rgbActions[1].handler()
        #expect(context.writtenPayloads.last == .text("#123456"))

        // Caso 4: #RRGGBBAA con canal alfa (#FF000080 -> alpha 128)
        let alphaHexItem = makeTextItem("#FF000080")
        let alphaActions = plugin.quickActions(for: alphaHexItem, context: context)
        alphaActions[0].handler()
        #expect(context.writtenPayloads.last == .text("rgba(255, 0, 0, 0.50)"))
        alphaActions[1].handler()
        #expect(context.writtenPayloads.last == .text("#FF000080"))
        alphaActions[2].handler()
        #expect(context.writtenPayloads.last == .text("Color(red: 1.000, green: 0.000, blue: 0.000, opacity: 0.502)"))
    }

    // MARK: - 4. Coexistencia de los 4 Plugins en FeatureRegistry

    @Test func allFourBuiltInPluginsCoexistInFeatureRegistryAndRespectPriorityAndEnablement() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let (settings, defaults, suiteName) = try makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let youtubePlugin = YouTubeAudioFeaturePlugin(settings: settings)
        let urlCleanerPlugin = URLCleanerFeaturePlugin()
        let jsonFormatterPlugin = JSONFormatterFeaturePlugin()
        let colorConverterPlugin = ColorConverterFeaturePlugin()

        let registry = FeatureRegistry(
            settings: settings,
            plugins: [
                youtubePlugin,
                urlCleanerPlugin,
                jsonFormatterPlugin,
                colorConverterPlugin
            ]
        )

        #expect(registry.plugins.map(\.id) == [
            "com.notchclip.plugin.youtube-audio",
            "com.notchclip.plugin.url-cleaner",
            "com.notchclip.plugin.json-formatter",
            "com.notchclip.plugin.color-converter"
        ])

        // Una URL de YouTube con parámetros de tracking coincide tanto con YouTubeAudio (.high) como con URLCleaner (.normal)
        let trackedYouTubeItem = try makeURLItem("https://www.youtube.com/watch?v=dQw4w9WgXcQ&utm_source=share&si=track123")
        let matchedForYouTube = registry.matchingPlugins(for: trackedYouTubeItem)
        #expect(matchedForYouTube.map(\.id) == [
            youtubePlugin.id,
            urlCleanerPlugin.id
        ])

        let context = FeatureActionContext.noop
        let combinedQuickActions = registry.quickActions(for: trackedYouTubeItem, context: context)
        #expect(combinedQuickActions.map(\.title) == [
            "Descargar MP3",
            "Descargar WAV",
            "Descargar vídeo",
            "Limpiar URL (quitar tracking)"
        ])

        // Al desactivar URLCleaner desde Ajustes/Registry, solo queda YouTubeAudio
        registry.setPluginEnabled(urlCleanerPlugin.id, false)
        #expect(registry.isPluginEnabled(urlCleanerPlugin.id) == false)
        #expect(registry.matchingPlugins(for: trackedYouTubeItem).map(\.id) == [youtubePlugin.id])

        // Si se reactiva URLCleaner y se configura con .automaticPrompt mientras YouTube está desactivado, URLCleaner ofrece prompt
        registry.setPluginEnabled(youtubePlugin.id, false)
        registry.setPluginEnabled(urlCleanerPlugin.id, true)
        registry.setTriggerBehavior(.automaticPrompt, for: urlCleanerPlugin.id)
        #expect(registry.primaryPromptPlugin(for: trackedYouTubeItem)?.id == urlCleanerPlugin.id)
    }

    // MARK: - 5. YouTube Audio & Video Formats and Prompt Behavior

    @Test func downloadFormatExposesExpectedKindsExtensionsAndBadges() {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        #expect(DownloadFormat.allCases == [.mp3, .wav, .mp4_720p, .mp4_1080p])
        #expect(DownloadFormat.audioFormats == [.mp3, .wav])
        #expect(DownloadFormat.videoFormats == [.mp4_720p, .mp4_1080p])

        #expect(DownloadFormat.mp3.kind == .audio)
        #expect(DownloadFormat.mp3.fileExtension == "mp3")
        #expect(DownloadFormat.mp3.shortBadge == "MP3")
        #expect(DownloadFormat.mp3.maxVideoHeight == nil)

        #expect(DownloadFormat.wav.kind == .audio)
        #expect(DownloadFormat.wav.fileExtension == "wav")
        #expect(DownloadFormat.wav.shortBadge == "WAV")
        #expect(DownloadFormat.wav.maxVideoHeight == nil)

        #expect(DownloadFormat.mp4_720p.kind == .video)
        #expect(DownloadFormat.mp4_720p.fileExtension == "mp4")
        #expect(DownloadFormat.mp4_720p.shortBadge == "720p")
        #expect(DownloadFormat.mp4_720p.displayName == "MP4 720p")
        #expect(DownloadFormat.mp4_720p.maxVideoHeight == 720)

        #expect(DownloadFormat.mp4_1080p.kind == .video)
        #expect(DownloadFormat.mp4_1080p.fileExtension == "mp4")
        #expect(DownloadFormat.mp4_1080p.shortBadge == "1080p")
        #expect(DownloadFormat.mp4_1080p.displayName == "MP4 1080p")
        #expect(DownloadFormat.mp4_1080p.maxVideoHeight == 1080)
    }

    @Test func notchPromptViewShowsDynamicPrimaryButtonTitleForAudioAndVideo() throws {
        let ytURL = try #require(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let video = DetectedVideo(
            videoID: "dQw4w9WgXcQ",
            canonicalURL: ytURL,
            title: "Demo Video",
            authorName: "Channel",
            thumbnailURL: nil,
            isLoading: false
        )

        L10n.withLanguage(.spanish) {
            let audioPrompt = NotchPromptView(
                video: video,
                format: .mp3,
                binariesAvailable: true,
                onSelectFormat: { _ in },
                onSave: {},
                onCancel: {}
            )
            let videoPrompt = NotchPromptView(
                video: video,
                format: .mp4_1080p,
                binariesAvailable: true,
                onSelectFormat: { _ in },
                onSave: {},
                onCancel: {}
            )
            #expect(audioPrompt.primaryActionTitle == "Guardar audio")
            #expect(videoPrompt.primaryActionTitle == "Guardar vídeo")
        }

        L10n.withLanguage(.english) {
            let audioPrompt = NotchPromptView(
                video: video,
                format: .wav,
                binariesAvailable: true,
                onSelectFormat: { _ in },
                onSave: {},
                onCancel: {}
            )
            let videoPrompt = NotchPromptView(
                video: video,
                format: .mp4_720p,
                binariesAvailable: true,
                onSelectFormat: { _ in },
                onSave: {},
                onCancel: {}
            )
            #expect(audioPrompt.primaryActionTitle == "Save audio")
            #expect(videoPrompt.primaryActionTitle == "Save video")
        }
    }

    @Test func videoQuickActionOpensPromptWithVideoPreselectedEvenInHistoryActionOnlyMode() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let (settings, defaults, suiteName) = try makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.defaultFormat = .mp3
        settings.persistClipboardHistory = false

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTubeVideoQuickAction-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = ClipboardStorage(baseDirectory: tempDir, debounceInterval: 0)
        let historyStore = ClipboardHistoryStore(
            settings: settings,
            storage: storage,
            pasteboard: MockPasteboard()
        )
        let youtubePlugin = YouTubeAudioFeaturePlugin(settings: settings)
        let registry = FeatureRegistry(settings: settings, plugins: [youtubePlugin])
        registry.setTriggerBehavior(.historyActionOnly, for: youtubePlugin.id)

        let appState = AppState(
            settings: settings,
            historyStore: historyStore,
            featureRegistry: registry
        )

        let ytItem = try makeURLItem("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        appState.handleCapturedItem(ytItem)

        // In .historyActionOnly mode, automatic prompt does NOT open on copy.
        #expect(appState.notchMode == .idle)

        let storedItem = try #require(historyStore.items.first)
        let actions = youtubePlugin.quickActions(for: storedItem, context: appState.actionContext)
        let videoAction = try #require(actions.first(where: { $0.title == "Descargar vídeo" }))

        // Trigger "Descargar vídeo" quick action -> opens prompt with video preselected.
        videoAction.handler()
        #expect(appState.notchMode == .promptingFeature(pluginID: youtubePlugin.id, item: storedItem))
        #expect(youtubePlugin.promptFormat.isVideo == true)
        #expect(youtubePlugin.promptFormat == .mp4_1080p)

        // Calling makePromptView again (as NotchRootView does on render) must NOT reset to MP3.
        let renderedPrompt = youtubePlugin.makePromptView(
            for: storedItem,
            context: appState.actionContext,
            onComplete: {},
            onDismiss: {}
        )
        #expect(renderedPrompt != nil)
        #expect(youtubePlugin.promptFormat == .mp4_1080p)

        // Switching format while prompt is open is preserved across re-renders.
        youtubePlugin.promptFormat = .mp4_720p
        _ = youtubePlugin.makePromptView(
            for: storedItem,
            context: appState.actionContext,
            onComplete: {},
            onDismiss: {}
        )
        #expect(youtubePlugin.promptFormat == .mp4_720p)
    }
}

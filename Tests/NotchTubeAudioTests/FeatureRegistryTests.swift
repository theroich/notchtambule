//
//  FeatureRegistryTests.swift
//  NotchTubeAudioTests
//

import Foundation
import SwiftUI
import Testing
@testable import NotchTubeAudio

@MainActor
private final class MockFeaturePlugin: ClipboardFeaturePlugin {
    let id: String
    let displayName: String
    let summary: String
    let iconSystemName: String
    let priority: FeaturePriority
    let defaultTriggerBehavior: FeatureTriggerBehavior
    let hasActivityPanel: Bool
    var activeTasksCount: Int

    var canHandlePredicate: (ClipboardItem) -> Bool
    var supportsPrompt: Bool
    var quickActionTitles: [String]
    var supportsSettingsView: Bool

    private(set) var startCallCount: Int = 0
    private(set) var shutdownCallCount: Int = 0
    private(set) var makePromptCallCount: Int = 0
    private(set) var executedQuickActions: [String] = []

    init(
        id: String,
        displayName: String = "Mock Plugin",
        summary: String = "Mock summary",
        iconSystemName: String = "puzzlepiece.extension",
        priority: FeaturePriority = .normal,
        defaultTriggerBehavior: FeatureTriggerBehavior = .historyActionOnly,
        hasActivityPanel: Bool = false,
        activeTasksCount: Int = 0,
        supportsPrompt: Bool = false,
        quickActionTitles: [String] = ["Acción Mock"],
        supportsSettingsView: Bool = false,
        canHandlePredicate: @escaping (ClipboardItem) -> Bool = { _ in true }
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.iconSystemName = iconSystemName
        self.priority = priority
        self.defaultTriggerBehavior = defaultTriggerBehavior
        self.hasActivityPanel = hasActivityPanel
        self.activeTasksCount = activeTasksCount
        self.supportsPrompt = supportsPrompt
        self.quickActionTitles = quickActionTitles
        self.supportsSettingsView = supportsSettingsView
        self.canHandlePredicate = canHandlePredicate
    }

    func start() {
        startCallCount += 1
    }

    func shutdown() {
        shutdownCallCount += 1
    }

    func canHandle(_ item: ClipboardItem) -> Bool {
        canHandlePredicate(item)
    }

    func quickActions(for item: ClipboardItem, context: FeatureActionContext) -> [FeatureQuickAction] {
        guard canHandle(item) else { return [] }
        return quickActionTitles.enumerated().map { index, title in
            FeatureQuickAction(
                id: "\(id).action.\(index)",
                pluginID: id,
                title: title,
                iconSystemName: iconSystemName
            ) { [weak self] in
                self?.executedQuickActions.append(title)
            }
        }
    }

    func makePromptView(
        for item: ClipboardItem,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView? {
        guard supportsPrompt else { return nil }
        makePromptCallCount += 1
        return AnyView(EmptyView())
    }

    func makeActivityPanelView(context: FeatureActionContext) -> AnyView? {
        guard hasActivityPanel else { return nil }
        return AnyView(EmptyView())
    }

    func makeSettingsView() -> AnyView? {
        guard supportsSettingsView else { return nil }
        return AnyView(EmptyView())
    }
}

@MainActor
struct FeatureRegistryTests {
    private func makeIsolatedSettings() throws -> (SettingsManager, UserDefaults, String) {
        let suiteName = "notchtube.features.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsManager(defaults: defaults)
        return (settings, defaults, suiteName)
    }

    private func makeURLItem(_ urlString: String = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&utm_source=test") throws -> ClipboardItem {
        let url = try #require(URL(string: urlString))
        return ClipboardItem(
            changeCount: 1,
            payload: .url(url, rawText: urlString)
        )
    }

    private func makeTextItem(_ text: String = "{\"hello\":\"world\"}") -> ClipboardItem {
        ClipboardItem(
            changeCount: 2,
            payload: .text(text)
        )
    }

    @Test func registersMockPluginAndInvokesStartWhenEnabled() throws {
        let (settings, defaults, suiteName) = try makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = FeatureRegistry(settings: settings)
        let plugin = MockFeaturePlugin(
            id: "com.notchclip.plugin.mock",
            displayName: "Plugin de Prueba"
        )

        registry.register(plugin)

        #expect(registry.plugins.count == 1)
        #expect(registry.plugin(withID: plugin.id)?.displayName == "Plugin de Prueba")
        #expect(registry.isPluginEnabled(plugin.id) == true)
        #expect(plugin.startCallCount == 1)
        #expect(plugin.shutdownCallCount == 0)
    }

    @Test func doesNotStartPluginUponRegistrationIfPersistedAsDisabled() throws {
        let (settings, defaults, suiteName) = try makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let pluginID = "com.notchclip.plugin.pre-disabled"
        settings.setPluginEnabled(pluginID, false)

        let registry = FeatureRegistry(settings: settings)
        let plugin = MockFeaturePlugin(id: pluginID)
        registry.register(plugin)

        #expect(registry.isPluginEnabled(pluginID) == false)
        #expect(plugin.startCallCount == 0)
        #expect(registry.matchingPlugins(for: makeTextItem()).isEmpty)
    }

    @Test func matchingPluginsReturnsCompatiblePluginsOrderedByDescendingPriority() throws {
        let (settings, defaults, suiteName) = try makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = FeatureRegistry(settings: settings)

        let lowPlugin = MockFeaturePlugin(
            id: "com.notchclip.plugin.low",
            priority: .low,
            canHandlePredicate: { $0.contentType == .url }
        )
        let normalPluginA = MockFeaturePlugin(
            id: "com.notchclip.plugin.normal-a",
            priority: .normal,
            canHandlePredicate: { $0.contentType == .url }
        )
        let highPlugin = MockFeaturePlugin(
            id: "com.notchclip.plugin.high",
            priority: .high,
            canHandlePredicate: { $0.contentType == .url }
        )
        let normalPluginB = MockFeaturePlugin(
            id: "com.notchclip.plugin.normal-b",
            priority: .normal,
            canHandlePredicate: { $0.contentType == .url }
        )
        let nonMatchingPlugin = MockFeaturePlugin(
            id: "com.notchclip.plugin.text-only",
            priority: .high,
            canHandlePredicate: { $0.contentType == .plainText }
        )

        registry.register(lowPlugin)
        registry.register(normalPluginA)
        registry.register(highPlugin)
        registry.register(normalPluginB)
        registry.register(nonMatchingPlugin)

        let urlItem = try makeURLItem()
        let matches = registry.matchingPlugins(for: urlItem)

        #expect(matches.map(\.id) == [
            "com.notchclip.plugin.high",
            "com.notchclip.plugin.normal-a",
            "com.notchclip.plugin.normal-b",
            "com.notchclip.plugin.low"
        ])
    }

    @Test func disablingPluginExcludesItFromMatchingAndInvokesShutdown() throws {
        let (settings, defaults, suiteName) = try makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = FeatureRegistry(settings: settings)
        let youtubePlugin = MockFeaturePlugin(
            id: "com.notchclip.plugin.youtube-audio",
            priority: .high,
            defaultTriggerBehavior: .automaticPrompt,
            supportsPrompt: true
        )
        let cleanerPlugin = MockFeaturePlugin(
            id: "com.notchclip.plugin.url-cleaner",
            priority: .normal,
            defaultTriggerBehavior: .historyActionOnly
        )

        registry.register(youtubePlugin)
        registry.register(cleanerPlugin)

        let item = try makeURLItem()
        #expect(registry.matchingPlugins(for: item).map(\.id) == [youtubePlugin.id, cleanerPlugin.id])
        #expect(youtubePlugin.startCallCount == 1)
        #expect(youtubePlugin.shutdownCallCount == 0)

        // Disable YouTube plugin
        registry.setPluginEnabled(youtubePlugin.id, false)

        #expect(registry.isPluginEnabled(youtubePlugin.id) == false)
        #expect(settings.isPluginEnabled(youtubePlugin.id) == false)
        #expect(youtubePlugin.shutdownCallCount == 1)
        #expect(registry.matchingPlugins(for: item).map(\.id) == [cleanerPlugin.id])
        #expect(registry.primaryPromptPlugin(for: item) == nil)

        // Re-enable YouTube plugin
        registry.setPluginEnabled(youtubePlugin.id, true)
        #expect(registry.isPluginEnabled(youtubePlugin.id) == true)
        #expect(youtubePlugin.startCallCount == 2)
        #expect(registry.matchingPlugins(for: item).map(\.id) == [youtubePlugin.id, cleanerPlugin.id])
        #expect(registry.primaryPromptPlugin(for: item)?.id == youtubePlugin.id)
    }

    @Test func changingTriggerBehaviorToHistoryActionOnlyPreventsAutomaticPromptWhileKeepingQuickActions() throws {
        let (settings, defaults, suiteName) = try makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = FeatureRegistry(settings: settings)
        let youtubePlugin = MockFeaturePlugin(
            id: "com.notchclip.plugin.youtube-audio",
            priority: .high,
            defaultTriggerBehavior: .automaticPrompt,
            supportsPrompt: true,
            quickActionTitles: ["Descargar MP3", "Descargar WAV"]
        )
        let cleanerPlugin = MockFeaturePlugin(
            id: "com.notchclip.plugin.url-cleaner",
            priority: .normal,
            defaultTriggerBehavior: .historyActionOnly,
            supportsPrompt: true,
            quickActionTitles: ["Limpiar URL"]
        )

        registry.register(youtubePlugin)
        registry.register(cleanerPlugin)

        let item = try makeURLItem()
        let context = FeatureActionContext.noop

        // Initially YouTube has .automaticPrompt
        #expect(registry.triggerBehavior(for: youtubePlugin.id) == .automaticPrompt)
        #expect(registry.primaryPromptPlugin(for: item)?.id == youtubePlugin.id)

        // Switch YouTube to .historyActionOnly
        registry.setTriggerBehavior(.historyActionOnly, for: youtubePlugin.id)
        #expect(registry.triggerBehavior(for: youtubePlugin.id) == .historyActionOnly)
        #expect(registry.primaryPromptPlugin(for: item) == nil)

        // Quick actions remain available in history
        let actions = registry.quickActions(for: item, context: context)
        #expect(actions.map(\.title) == ["Descargar MP3", "Descargar WAV", "Limpiar URL"])
        #expect(actions.map(\.pluginID) == [youtubePlugin.id, youtubePlugin.id, cleanerPlugin.id])

        // Executing a quick action invokes its handler
        actions.first?.handler()
        #expect(youtubePlugin.executedQuickActions == ["Descargar MP3"])

        // If the secondary plugin is switched to .automaticPrompt, it becomes the primaryPromptPlugin
        registry.setTriggerBehavior(.automaticPrompt, for: cleanerPlugin.id)
        #expect(registry.primaryPromptPlugin(for: item)?.id == cleanerPlugin.id)
    }

    @Test func primaryPromptPluginSkipsPluginsWhoseMakePromptViewReturnsNil() throws {
        let (settings, defaults, suiteName) = try makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = FeatureRegistry(settings: settings)
        let highWithoutPromptView = MockFeaturePlugin(
            id: "com.notchclip.plugin.high-no-view",
            priority: .high,
            defaultTriggerBehavior: .automaticPrompt,
            supportsPrompt: false
        )
        let normalWithPromptView = MockFeaturePlugin(
            id: "com.notchclip.plugin.normal-with-view",
            priority: .normal,
            defaultTriggerBehavior: .automaticPrompt,
            supportsPrompt: true
        )

        registry.register(highWithoutPromptView)
        registry.register(normalWithPromptView)

        let item = makeTextItem()
        let selected = registry.primaryPromptPlugin(for: item)
        #expect(selected?.id == normalWithPromptView.id)
    }

    @Test func featureActionContextForwardsAllSystemPrimitivesToClosures() throws {
        let item = makeTextItem("hola")

        var capturedWrite: ClipboardPayload?
        var capturedPrompt: (String, ClipboardItem)?
        var capturedActivityPluginID: String?
        var hideCount = 0
        var capturedNotification: (String, String)?

        let context = FeatureActionContext(
            onWriteToClipboard: { payload in
                capturedWrite = payload
            },
            onPresentPluginPrompt: { pluginID, clipboardItem in
                capturedPrompt = (pluginID, clipboardItem)
            },
            onSwitchToPluginActivity: { pluginID in
                capturedActivityPluginID = pluginID
            },
            onHideNotch: {
                hideCount += 1
            },
            onNotifyUser: { message, icon in
                capturedNotification = (message, icon)
            }
        )

        context.writeToClipboard(.text("limpio"))
        context.presentPluginPrompt(pluginID: "com.notchclip.plugin.youtube-audio", for: item)
        context.switchToPluginActivity(pluginID: "com.notchclip.plugin.youtube-audio")
        context.hideNotch()
        context.notifyUser(message: "URL limpia copiada", icon: "sparkles")

        #expect(capturedWrite == .text("limpio"))
        #expect(context.writtenPayloads == [.text("limpio")])
        #expect(capturedPrompt?.0 == "com.notchclip.plugin.youtube-audio")
        #expect(capturedPrompt?.1 == item)
        #expect(context.lastPresentedPrompt?.pluginID == "com.notchclip.plugin.youtube-audio")
        #expect(capturedActivityPluginID == "com.notchclip.plugin.youtube-audio")
        #expect(context.lastSwitchedActivityPluginID == "com.notchclip.plugin.youtube-audio")
        #expect(hideCount == 1)
        #expect(context.hideNotchCallCount == 1)
        #expect(capturedNotification?.0 == "URL limpia copiada")
        #expect(capturedNotification?.1 == "sparkles")
        #expect(context.lastNotification == FeatureUserNotification(message: "URL limpia copiada", icon: "sparkles"))
    }

    @Test func tracksActivityPanelPluginsAndActiveTaskCounts() throws {
        let (settings, defaults, suiteName) = try makeIsolatedSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let registry = FeatureRegistry(settings: settings)
        let youtube = MockFeaturePlugin(
            id: "com.notchclip.plugin.youtube-audio",
            hasActivityPanel: true,
            activeTasksCount: 2
        )
        let json = MockFeaturePlugin(
            id: "com.notchclip.plugin.json-formatter",
            hasActivityPanel: false,
            activeTasksCount: 0
        )

        registry.register(youtube)
        registry.register(json)

        #expect(registry.activityPanelPlugins.map(\.id) == [youtube.id])
        #expect(registry.totalActiveTasksCount == 2)

        registry.setPluginEnabled(youtube.id, false)
        #expect(registry.activityPanelPlugins.isEmpty)
        #expect(registry.totalActiveTasksCount == 0)
    }
}

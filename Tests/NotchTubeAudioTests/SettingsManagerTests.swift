//
//  SettingsManagerTests.swift
//  NotchTubeAudioTests
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NotchTubeAudio

@MainActor
private final class SettingsTestPlugin: ClipboardFeaturePlugin {
    let id: String
    let displayName: String
    let summary: String
    let iconSystemName: String
    let priority: FeaturePriority
    let defaultTriggerBehavior: FeatureTriggerBehavior
    let supportsPrompt: Bool
    var hasCustomSettingsView: Bool

    private(set) var startCount = 0
    private(set) var shutdownCount = 0
    private(set) var makeSettingsViewCallCount = 0
    private(set) var makePromptViewCallCount = 0
    private(set) var executedQuickActionCount = 0

    init(
        id: String,
        displayName: String = "Módulo de Prueba",
        summary: String = "Descripción del módulo de prueba",
        iconSystemName: String = "puzzlepiece.extension",
        priority: FeaturePriority = .normal,
        defaultTriggerBehavior: FeatureTriggerBehavior = .historyActionOnly,
        supportsPrompt: Bool = true,
        hasCustomSettingsView: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.iconSystemName = iconSystemName
        self.priority = priority
        self.defaultTriggerBehavior = defaultTriggerBehavior
        self.supportsPrompt = supportsPrompt
        self.hasCustomSettingsView = hasCustomSettingsView
    }

    func start() {
        startCount += 1
    }

    func shutdown() {
        shutdownCount += 1
    }

    func canHandle(_ item: ClipboardItem) -> Bool {
        true
    }

    func quickActions(for item: ClipboardItem, context: FeatureActionContext) -> [FeatureQuickAction] {
        [
            FeatureQuickAction(
                id: "\(id).quick.\(item.id.uuidString)",
                pluginID: id,
                title: "Acción rápida \(displayName)",
                iconSystemName: iconSystemName
            ) { [weak self] in
                self?.executedQuickActionCount += 1
            }
        ]
    }

    func makePromptView(
        for item: ClipboardItem,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView? {
        guard supportsPrompt else { return nil }
        makePromptViewCallCount += 1
        return AnyView(Text("Prompt de \(displayName)"))
    }

    func makeSettingsView() -> AnyView? {
        guard hasCustomSettingsView else { return nil }
        makeSettingsViewCallCount += 1
        return AnyView(
            Section("Preferencias de \(displayName)") {
                Text("Ajuste personalizado de \(displayName)")
            }
        )
    }
}

@MainActor
struct SettingsManagerTests {
    @Test func clampsPromptDurationAndPersistsChanges() throws {
        let suiteName = "notchtube.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        #expect(settings.defaultFormat == .mp3)
        #expect(settings.promptAutoDismissSeconds == 8)

        settings.promptAutoDismissSeconds = 1
        #expect(settings.promptAutoDismissSeconds == SettingsManager.minimumPromptDuration)

        settings.promptAutoDismissSeconds = 99
        #expect(settings.promptAutoDismissSeconds == SettingsManager.maximumPromptDuration)

        settings.promptAutoDismissSeconds = 12
        settings.defaultFormat = .wav
        settings.isClipboardMonitoringEnabled = false

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.promptAutoDismissSeconds == 12)
        #expect(reloaded.defaultFormat == .wav)
        #expect(reloaded.isClipboardMonitoringEnabled == false)
    }

    @Test func clampsClipboardHistoryRetentionAndPersistsHistorySettings() throws {
        let suiteName = "notchtube.settings.history.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        #expect(settings.maxClipboardHistoryItems == 100)
        #expect(settings.persistClipboardHistory == true)
        #expect(settings.ignoreConfidentialPasteboardTypes == true)

        settings.maxClipboardHistoryItems = 3
        #expect(settings.maxClipboardHistoryItems == SettingsManager.minimumClipboardHistoryItems)

        settings.maxClipboardHistoryItems = 999
        #expect(settings.maxClipboardHistoryItems == SettingsManager.maximumClipboardHistoryItems)

        settings.maxClipboardHistoryItems = 75
        settings.persistClipboardHistory = false
        settings.ignoreConfidentialPasteboardTypes = false

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.maxClipboardHistoryItems == 75)
        #expect(reloaded.persistClipboardHistory == false)
        #expect(reloaded.ignoreConfidentialPasteboardTypes == false)
    }

    @Test func validatesBinaryPaths() {
        #expect(BinaryLocator.isExecutable("/usr/bin/true"))
        #expect(!BinaryLocator.isExecutable("/usr/bin"))
        #expect(!BinaryLocator.isExecutable("/definitely/not/here"))
        #expect(!BinaryLocator.isExecutable(""))
    }

    @Test func persistsPluginEnabledStatesAndTriggerBehaviors() throws {
        let suiteName = "notchtube.settings.plugins.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        let youtubeID = "com.notchclip.plugin.youtube-audio"
        let cleanerID = "com.notchclip.plugin.url-cleaner"

        #expect(settings.isPluginEnabled(youtubeID) == true)
        #expect(settings.triggerBehavior(for: youtubeID, defaultBehavior: .automaticPrompt) == .automaticPrompt)
        #expect(settings.triggerBehavior(for: cleanerID, defaultBehavior: .historyActionOnly) == .historyActionOnly)

        settings.setPluginEnabled(youtubeID, false)
        settings.setPluginEnabled(cleanerID, true)
        settings.setTriggerBehavior(.historyActionOnly, for: youtubeID)
        settings.setTriggerBehavior(.automaticPrompt, for: cleanerID)

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.isPluginEnabled(youtubeID) == false)
        #expect(reloaded.isPluginEnabled(cleanerID) == true)
        #expect(reloaded.triggerBehavior(for: youtubeID, defaultBehavior: .automaticPrompt) == .historyActionOnly)
        #expect(reloaded.triggerBehavior(for: cleanerID, defaultBehavior: .historyActionOnly) == .automaticPrompt)
    }

    @Test func modularSettingsAndPluginsTabRenderRegisteredPluginsAndYouTubeSettingsView() throws {
        let suiteName = "notchtube.settings.modular.ui.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        settings.persistClipboardHistory = false

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTubeSettingsUITests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = ClipboardStorage(baseDirectory: tempDir, debounceInterval: 0)
        let pasteboard = MockPasteboard()
        let historyStore = ClipboardHistoryStore(
            settings: settings,
            storage: storage,
            pasteboard: pasteboard
        )

        let youtubePlugin = YouTubeAudioFeaturePlugin(settings: settings)
        let customPlugin = SettingsTestPlugin(
            id: "com.notchclip.plugin.custom-formatter",
            displayName: "Formateador JSON",
            summary: "Embellece y valida bloques JSON copiados.",
            iconSystemName: "curlybraces",
            defaultTriggerBehavior: .historyActionOnly,
            supportsPrompt: true,
            hasCustomSettingsView: true
        )

        let featureRegistry = FeatureRegistry(
            settings: settings,
            plugins: [youtubePlugin, customPlugin]
        )

        #expect(SettingsView.historyLimitPresets == [25, 50, 100, 250, 500])
        #expect(featureRegistry.pluginSupportsPrompt(youtubePlugin) == true)
        #expect(featureRegistry.pluginSupportsPrompt(customPlugin) == true)
        #expect(youtubePlugin.makeSettingsView() != nil)

        // Render PluginsSettingsTabView to verify dynamic iteration and makeSettingsView() injection
        let pluginsTab = PluginsSettingsTabView(featureRegistry: featureRegistry)
        let pluginsHosting = NSHostingView(rootView: pluginsTab)
        pluginsHosting.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        pluginsHosting.layoutSubtreeIfNeeded()

        #expect(customPlugin.makeSettingsViewCallCount >= 1)

        // Toggle plugin enablement and trigger behavior through FeatureRegistry
        featureRegistry.setPluginEnabled(customPlugin.id, false)
        #expect(featureRegistry.isPluginEnabled(customPlugin.id) == false)
        #expect(customPlugin.shutdownCount == 1)

        featureRegistry.setTriggerBehavior(.automaticPrompt, for: customPlugin.id)
        #expect(featureRegistry.triggerBehavior(for: customPlugin.id) == .automaticPrompt)

        // Render main SettingsView with TabView
        let settingsView = SettingsView(
            settings: settings,
            featureRegistry: featureRegistry,
            historyStore: historyStore
        )
        let settingsHosting = NSHostingView(rootView: settingsView)
        settingsHosting.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        settingsHosting.layoutSubtreeIfNeeded()
        #expect(settingsHosting.fittingSize.width == 600)
    }

    @Test func menuBarContentExposesRecentClipboardItemsAndControls() throws {
        let suiteName = "notchtube.menubar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        settings.persistClipboardHistory = false

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTubeMenuBarTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = ClipboardStorage(baseDirectory: tempDir, debounceInterval: 0)
        let pasteboard = MockPasteboard()
        let historyStore = ClipboardHistoryStore(
            settings: settings,
            storage: storage,
            pasteboard: pasteboard
        )
        let plugin = SettingsTestPlugin(
            id: "com.notchclip.plugin.test",
            supportsPrompt: true
        )
        let featureRegistry = FeatureRegistry(settings: settings, plugins: [plugin])
        let appState = AppState(
            settings: settings,
            historyStore: historyStore,
            featureRegistry: featureRegistry
        )

        // Record 7 items; MenuBarContent.recentItems must return the latest 5
        for index in 1...7 {
            var item = ClipboardItem(
                changeCount: index,
                payload: .text("Elemento copiado \(index)")
            )
            if index == 7 {
                item.isPinned = true
            }
            historyStore.record(item)
        }

        var toggleNotchCalled = 0
        var runActionCalled = 0
        let menuBar = MenuBarContent(
            appState: appState,
            historyStore: historyStore,
            featureRegistry: featureRegistry,
            onToggleNotch: { toggleNotchCalled += 1 },
            onRunCurrentClipboardAction: { runActionCalled += 1 }
        )

        #expect(menuBar.recentItems.count == 5)
        #expect(menuBar.recentItems.first?.previewTitle == "Elemento copiado 7")
        #expect(menuBar.recentItems.last?.previewTitle == "Elemento copiado 3")
        #expect(menuBar.toggleNotchMenuTitle == "Mostrar portapapeles en el notch")

        appState.showPanelFromMenu()
        #expect(menuBar.toggleNotchMenuTitle == "Ocultar portapapeles en el notch")

        let pinnedItem = try #require(menuBar.recentItems.first)
        #expect(MenuBarContent.menuItemTitle(for: pinnedItem).hasPrefix("📌 "))
        #expect(MenuBarContent.menuItemIcon(for: pinnedItem) == "doc.text")

        // Clearing unpinned items via historyStore leaves only the pinned item
        historyStore.clearUnpinned()
        #expect(historyStore.items.count == 1)
        #expect(historyStore.items.first?.isPinned == true)

        menuBar.onToggleNotch()
        menuBar.onRunCurrentClipboardAction()
        #expect(toggleNotchCalled == 1)
        #expect(runActionCalled == 1)
    }
}

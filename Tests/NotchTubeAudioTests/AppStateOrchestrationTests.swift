//
//  AppStateOrchestrationTests.swift
//  NotchTubeAudioTests
//

import Foundation
import SwiftUI
import Testing
@testable import NotchTubeAudio

@MainActor
private final class MockNotchPresenter: NotchPresenting {
    private(set) var presentPromptCount = 0
    private(set) var presentPanelCalls: [TimeInterval?] = []
    private(set) var hideCount = 0

    func presentPrompt() {
        presentPromptCount += 1
    }

    func presentPanel(autoHideAfter seconds: TimeInterval?) {
        presentPanelCalls.append(seconds)
    }

    func hide() {
        hideCount += 1
    }
}

@MainActor
private final class OrchestrationTestPlugin: ClipboardFeaturePlugin {
    let id: String
    let displayName: String
    let summary: String
    let iconSystemName: String
    let priority: FeaturePriority
    let defaultTriggerBehavior: FeatureTriggerBehavior
    let hasActivityPanel: Bool
    var activeTasksCount: Int
    var supportsPromptView: Bool
    var canHandlePredicate: (ClipboardItem) -> Bool

    private(set) var startCount = 0
    private(set) var shutdownCount = 0

    init(
        id: String,
        displayName: String = "Test Plugin",
        summary: String = "Summary",
        iconSystemName: String = "bolt.fill",
        priority: FeaturePriority = .normal,
        defaultTriggerBehavior: FeatureTriggerBehavior = .historyActionOnly,
        hasActivityPanel: Bool = false,
        activeTasksCount: Int = 0,
        supportsPromptView: Bool = true,
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
        self.supportsPromptView = supportsPromptView
        self.canHandlePredicate = canHandlePredicate
    }

    func start() {
        startCount += 1
    }

    func shutdown() {
        shutdownCount += 1
    }

    func canHandle(_ item: ClipboardItem) -> Bool {
        canHandlePredicate(item)
    }

    func makePromptView(
        for item: ClipboardItem,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView? {
        guard supportsPromptView else { return nil }
        return AnyView(EmptyView())
    }

    func makeActivityPanelView(context: FeatureActionContext) -> AnyView? {
        guard hasActivityPanel else { return nil }
        return AnyView(EmptyView())
    }
}

@MainActor
struct AppStateOrchestrationTests {
    private struct Harness {
        let appState: AppState
        let presenter: MockNotchPresenter
        let historyStore: ClipboardHistoryStore
        let featureRegistry: FeatureRegistry
        let pasteboard: MockPasteboard
        let settings: SettingsManager
        let defaults: UserDefaults
        let suiteName: String
        let tempDir: URL

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeHarness(plugins: [any ClipboardFeaturePlugin] = []) throws -> Harness {
        let suiteName = "notchtube.appstate.orchestration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsManager(defaults: defaults)
        settings.persistClipboardHistory = false

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTubeAppStateTests-\(UUID().uuidString)", isDirectory: true)
        let storage = ClipboardStorage(baseDirectory: tempDir, debounceInterval: 0)
        let pasteboard = MockPasteboard()
        let historyStore = ClipboardHistoryStore(
            settings: settings,
            storage: storage,
            pasteboard: pasteboard
        )
        let featureRegistry = FeatureRegistry(settings: settings, plugins: plugins)
        let appState = AppState(
            settings: settings,
            historyStore: historyStore,
            featureRegistry: featureRegistry
        )
        let presenter = MockNotchPresenter()
        appState.presenter = presenter

        return Harness(
            appState: appState,
            presenter: presenter,
            historyStore: historyStore,
            featureRegistry: featureRegistry,
            pasteboard: pasteboard,
            settings: settings,
            defaults: defaults,
            suiteName: suiteName,
            tempDir: tempDir
        )
    }

    @Test func storesEveryCapturedItemInHistoryWithDetectedFeatureIDs() throws {
        let urlPlugin = OrchestrationTestPlugin(
            id: "com.notchclip.plugin.url-cleaner",
            priority: .normal,
            defaultTriggerBehavior: .historyActionOnly,
            canHandlePredicate: { $0.contentType == .url }
        )
        let mediaPlugin = OrchestrationTestPlugin(
            id: "com.notchclip.plugin.media-detector",
            priority: .high,
            defaultTriggerBehavior: .historyActionOnly,
            canHandlePredicate: { $0.contentType == .url }
        )

        let harness = try makeHarness(plugins: [urlPlugin, mediaPlugin])
        defer { harness.cleanup() }

        let url = try #require(URL(string: "https://example.com/video?utm_source=test"))
        let item = ClipboardItem(
            changeCount: 1,
            payload: .url(url, rawText: url.absoluteString)
        )

        harness.appState.handleCapturedItem(item)

        #expect(harness.historyStore.items.count == 1)
        let stored = try #require(harness.historyStore.items.first)
        #expect(stored.detectedFeatureIDs == [
            "com.notchclip.plugin.media-detector",
            "com.notchclip.plugin.url-cleaner"
        ])
        // Since both plugins use .historyActionOnly, notch remains .idle
        #expect(harness.appState.notchMode == .idle)
        #expect(harness.presenter.presentPromptCount == 0)
    }

    @Test func expandsNotchWithPromptWhenMatchingPluginUsesAutomaticPrompt() throws {
        let promptPlugin = OrchestrationTestPlugin(
            id: "com.notchclip.plugin.auto-prompt",
            priority: .high,
            defaultTriggerBehavior: .automaticPrompt,
            hasActivityPanel: true,
            supportsPromptView: true,
            canHandlePredicate: { $0.contentType == .url }
        )
        let secondaryPlugin = OrchestrationTestPlugin(
            id: "com.notchclip.plugin.secondary",
            priority: .low,
            defaultTriggerBehavior: .historyActionOnly,
            canHandlePredicate: { $0.contentType == .url }
        )

        let harness = try makeHarness(plugins: [secondaryPlugin, promptPlugin])
        defer { harness.cleanup() }

        let url = try #require(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let item = ClipboardItem(
            changeCount: 5,
            payload: .url(url, rawText: url.absoluteString)
        )

        harness.appState.handleCapturedItem(item)

        // Recorded in history first with both detectedFeatureIDs
        #expect(harness.historyStore.items.count == 1)
        let recorded = try #require(harness.historyStore.items.first)
        #expect(recorded.detectedFeatureIDs == [promptPlugin.id, secondaryPlugin.id])

        // Transitioned to .promptingFeature for the primary prompt plugin
        #expect(harness.appState.notchMode == .promptingFeature(pluginID: promptPlugin.id, item: recorded))
        #expect(harness.presenter.presentPromptCount == 1)
    }

    @Test func silentCaptureWhenNoPluginRequestsAutomaticPromptIsAvailableOnHover() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        let item = ClipboardItem(
            changeCount: 2,
            payload: .text("Nota de texto silenciosa")
        )

        harness.appState.handleCapturedItem(item)

        #expect(harness.appState.notchMode == .idle)
        #expect(harness.presenter.presentPromptCount == 0)
        #expect(harness.historyStore.items.count == 1)
        #expect(harness.historyStore.items.first?.payload == .text("Nota de texto silenciosa"))

        // Hovering over the notch opens .showingPanel(tab: .clipboardHistory)
        harness.appState.showPanelFromHover()

        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))
        #expect(harness.appState.activeTab == .clipboardHistory)
        #expect(harness.presenter.presentPanelCalls == [nil])
    }

    @Test func hoverAndMenuOpenPanelInActiveTabAndCollapseOnHide() throws {
        let activityPlugin = OrchestrationTestPlugin(
            id: "com.notchclip.plugin.downloads",
            hasActivityPanel: true,
            activeTasksCount: 3
        )
        let harness = try makeHarness(plugins: [activityPlugin])
        defer { harness.cleanup() }

        // 1. Default hover opens .clipboardHistory
        harness.appState.showPanelFromHover()
        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))
        #expect(harness.presenter.presentPanelCalls.count == 1)

        // 2. User switches tab to pluginActivity
        let pluginTab = NotchPanelTab.pluginActivity(pluginID: activityPlugin.id)
        harness.appState.selectTab(pluginTab)
        #expect(harness.appState.activeTab == pluginTab)
        #expect(harness.appState.notchMode == .showingPanel(tab: pluginTab))

        // 3. Pointer leaves retention zone -> hides to .idle
        harness.appState.hideFromHover()
        #expect(harness.appState.notchMode == .idle)
        #expect(harness.presenter.hideCount == 1)

        // 4. Subsequent hover remembers the last active tab (.pluginActivity)
        harness.appState.showPanelFromHover()
        #expect(harness.appState.notchMode == .showingPanel(tab: pluginTab))

        // 5. If the plugin is disabled while activeTab points to it, next hover falls back to .clipboardHistory
        harness.appState.hideFromTimeout()
        #expect(harness.appState.notchMode == .idle)

        harness.featureRegistry.setPluginEnabled(activityPlugin.id, false)
        harness.appState.showPanelFromHover()
        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))
        #expect(harness.appState.activeTab == .clipboardHistory)

        // 6. Calling selectTab(.pluginActivity) while plugin is disabled falls back to .clipboardHistory
        harness.appState.selectTab(pluginTab)
        #expect(harness.appState.activeTab == .clipboardHistory)
        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))

        // 7. Re-enabling the plugin allows selectTab(.pluginActivity) to resolve to .pluginActivity
        harness.featureRegistry.setPluginEnabled(activityPlugin.id, true)
        harness.appState.selectTab(pluginTab)
        #expect(harness.appState.activeTab == pluginTab)
        #expect(harness.appState.notchMode == .showingPanel(tab: pluginTab))
    }

    @Test func promptLifecycleDismissCompleteAndReturnToHistoryTransitions() throws {
        let activityPlugin = OrchestrationTestPlugin(
            id: "com.notchclip.plugin.with-activity",
            priority: .high,
            defaultTriggerBehavior: .automaticPrompt,
            hasActivityPanel: true,
            supportsPromptView: true
        )
        let simplePromptPlugin = OrchestrationTestPlugin(
            id: "com.notchclip.plugin.no-activity",
            priority: .normal,
            defaultTriggerBehavior: .automaticPrompt,
            hasActivityPanel: false,
            supportsPromptView: true
        )

        let harness = try makeHarness(plugins: [activityPlugin, simplePromptPlugin])
        defer { harness.cleanup() }

        let item = ClipboardItem(changeCount: 1, payload: .text("Elemento con prompt"))
        harness.appState.handleCapturedItem(item)
        #expect(harness.appState.notchMode.isPrompting)

        // Hover while prompting does not override the prompt
        harness.appState.showPanelFromHover()
        #expect(harness.appState.notchMode.isPrompting)

        // Dismiss prompt -> returns to .idle
        harness.appState.dismissPrompt()
        #expect(harness.appState.notchMode == .idle)
        #expect(harness.presenter.hideCount == 1)

        // Re-open prompt and complete for plugin with activity panel -> transitions to .showingPanel(.pluginActivity)
        harness.appState.presentPluginPrompt(pluginID: activityPlugin.id, for: item)
        #expect(harness.appState.notchMode == .promptingFeature(pluginID: activityPlugin.id, item: item))

        harness.appState.completePrompt(for: activityPlugin.id)
        #expect(harness.appState.notchMode == .showingPanel(tab: .pluginActivity(pluginID: activityPlugin.id)))
        #expect(harness.presenter.presentPanelCalls.last == 4)

        // Present prompt and return to history from the top bar button
        harness.appState.presentPluginPrompt(pluginID: simplePromptPlugin.id, for: item)
        #expect(harness.appState.notchMode == .promptingFeature(pluginID: simplePromptPlugin.id, item: item))

        harness.appState.returnToHistoryFromPrompt()
        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))
        #expect(harness.appState.activeTab == .clipboardHistory)

        // Present prompt for a plugin without activity panel and complete -> hides to .idle
        harness.appState.presentPluginPrompt(pluginID: simplePromptPlugin.id, for: item)
        harness.appState.completePrompt(for: simplePromptPlugin.id)
        #expect(harness.appState.notchMode == .idle)
    }

    @Test func featureActionContextIntegratesWithAppStateHistoryStoreAndPresenter() throws {
        let plugin = OrchestrationTestPlugin(
            id: "com.notchclip.plugin.transformer",
            hasActivityPanel: true,
            supportsPromptView: true
        )
        let harness = try makeHarness(plugins: [plugin])
        defer { harness.cleanup() }

        let context = harness.appState.actionContext
        let item = ClipboardItem(changeCount: 1, payload: .text(" original "))

        // 1. writeToClipboard writes to pasteboard and records in historyStore
        context.writeToClipboard(.text("transformado"))
        #expect(harness.pasteboard.string(forType: .string) == "transformado")
        #expect(harness.historyStore.items.first?.payload == .text("transformado"))

        // 2. presentPluginPrompt transitions to .promptingFeature
        context.presentPluginPrompt(pluginID: plugin.id, for: item)
        #expect(harness.appState.notchMode == .promptingFeature(pluginID: plugin.id, item: item))
        #expect(harness.presenter.presentPromptCount == 1)

        // 3. switchToPluginActivity transitions to .showingPanel(tab: .pluginActivity)
        context.switchToPluginActivity(pluginID: plugin.id)
        #expect(harness.appState.notchMode == .showingPanel(tab: .pluginActivity(pluginID: plugin.id)))
        #expect(harness.presenter.presentPanelCalls.last == 4)

        // 4. notifyUser records the notification
        context.notifyUser(message: "Copiado limpio", icon: "checkmark.circle.fill")
        #expect(harness.appState.activeNotification == FeatureUserNotification(message: "Copiado limpio", icon: "checkmark.circle.fill"))

        // 5. hideNotch collapses the notch
        context.hideNotch()
        #expect(harness.appState.notchMode == .idle)
        #expect(harness.presenter.hideCount == 1)
    }
}

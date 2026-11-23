//
//  AppState.swift
//  NotchTubeAudio
//

import Foundation
import Observation

/// The notch is driven by `AppState`; the controller implements the actual
/// presentation so the state object stays free of AppKit and SwiftUI details.
@MainActor
protocol NotchPresenting: AnyObject {
    /// Expand the notch showing a plugin prompt.
    func presentPrompt()
    /// Expand the notch showing the panel (clipboard history or plugin activity).
    /// - Parameter autoHideAfter: hides automatically when the pointer is not
    ///   inside the notch. `nil` keeps it open until the pointer leaves.
    func presentPanel(autoHideAfter seconds: TimeInterval?)
    /// Collapse the notch.
    func hide()
    /// Immediately dismisses the notch panel and relinquishes key-window focus
    /// before synthesizing `⌘V` into the previously active application.
    func hideImmediatelyForAutoPaste() async
}

extension NotchPresenting {
    /// Backward-compatible alias for `presentPanel(autoHideAfter:)`.
    func presentDownloads(autoHideAfter seconds: TimeInterval?) {
        presentPanel(autoHideAfter: seconds)
    }

    func hideImmediatelyForAutoPaste() async {
        hide()
    }
}

/// Global application orchestrator: coordinates the clipboard history store,
/// registered feature plugins, and the notch presentation state machine.
@MainActor
@Observable
final class AppState {
    let settings: SettingsManager
    let historyStore: ClipboardHistoryStore
    let featureRegistry: FeatureRegistry
    let autoPasteService: AutoPasteService

    private(set) var notchMode: NotchMode = .idle
    var activeTab: NotchPanelTab = .clipboardHistory
    private(set) var activeNotification: FeatureUserNotification?
    private(set) var lastPasteResult: PasteResult?

    @ObservationIgnored weak var presenter: (any NotchPresenting)?

    /// Context shared with feature plugins so they can write back to the clipboard,
    /// request prompts, switch to their activity panel, or hide the notch.
    @ObservationIgnored lazy var actionContext: FeatureActionContext = {
        FeatureActionContext(
            onWriteToClipboard: { [weak self] payload in
                self?.writePayloadToClipboard(payload)
            },
            onPresentPluginPrompt: { [weak self] pluginID, item in
                self?.presentPluginPrompt(pluginID: pluginID, for: item)
            },
            onSwitchToPluginActivity: { [weak self] pluginID in
                self?.switchToPluginActivity(pluginID: pluginID, autoHideAfter: 4)
            },
            onHideNotch: { [weak self] in
                self?.hideNotch()
            },
            onNotifyUser: { [weak self] message, icon in
                self?.notifyUser(message: message, icon: icon)
            }
        )
    }()

    init(
        settings: SettingsManager,
        historyStore: ClipboardHistoryStore,
        featureRegistry: FeatureRegistry,
        autoPasteService: AutoPasteService = AutoPasteService()
    ) {
        self.settings = settings
        self.historyStore = historyStore
        self.featureRegistry = featureRegistry
        self.autoPasteService = autoPasteService
    }

    // MARK: - Clipboard flow

    /// Main entry point when ``ClipboardMonitor`` captures a new clipboard item.
    ///
    /// 1. Evaluates matching enabled plugins in `featureRegistry`.
    /// 2. Annotates `item.detectedFeatureIDs`.
    /// 3. Records the item in `historyStore`.
    /// 4. If a primary plugin is configured with `.automaticPrompt`, transitions to
    ///    `.promptingFeature(pluginID:item:)` and expands the notch prompt.
    ///    Otherwise, stores the item silently in the history.
    func handleCapturedItem(_ item: ClipboardItem) {
        let matchedPlugins = featureRegistry.matchingPlugins(for: item)
        var annotatedItem = item
        annotatedItem.detectedFeatureIDs = matchedPlugins.map(\.id)

        historyStore.record(annotatedItem)

        let storedItem = historyStore.items.first(where: { $0.contentHash == annotatedItem.contentHash }) ?? annotatedItem

        if let promptPlugin = featureRegistry.primaryPromptPlugin(for: storedItem, context: actionContext) {
            autoPasteService.rememberFrontmostApp()
            notchMode = .promptingFeature(pluginID: promptPlugin.id, item: storedItem)
            presenter?.presentPrompt()
        }
    }

    /// Alias for `handleCapturedItem(_:)` used by existing callers.
    func handleClipboardItem(_ item: ClipboardItem) {
        handleCapturedItem(item)
    }

    // MARK: - Prompt & Plugin Actions

    /// Presents the full prompt for a specific plugin and clipboard item.
    func presentPluginPrompt(pluginID: String, for item: ClipboardItem) {
        guard let plugin = featureRegistry.plugin(withID: pluginID),
              featureRegistry.isPluginEnabled(pluginID),
              plugin.makePromptView(for: item, context: actionContext, onComplete: {}, onDismiss: {}) != nil else {
            return
        }
        autoPasteService.rememberFrontmostApp()
        notchMode = .promptingFeature(pluginID: pluginID, item: item)
        presenter?.presentPrompt()
    }

    /// Completes the active prompt: if the plugin has an activity panel, transitions to it;
    /// otherwise collapses the notch unless the plugin already transitioned `notchMode`.
    func completePrompt(for pluginID: String) {
        if case .showingPanel = notchMode {
            return
        }

        if let plugin = featureRegistry.plugin(withID: pluginID),
           featureRegistry.isPluginEnabled(pluginID),
           plugin.hasActivityPanel {
            switchToPluginActivity(pluginID: pluginID, autoHideAfter: 4)
        } else if case .promptingFeature(let currentPluginID, _) = notchMode, currentPluginID == pluginID {
            notchMode = .idle
            presenter?.hide()
        }
    }

    /// Dismisses a currently displayed plugin prompt and collapses the notch.
    func dismissPrompt() {
        guard notchMode.isPrompting else { return }
        notchMode = .idle
        presenter?.hide()
    }

    /// Called by the auto-dismiss timer when a prompt times out.
    func dismissPromptFromTimeout() {
        dismissPrompt()
    }

    /// Returns from an active plugin prompt directly to the clipboard history tab in the notch.
    func returnToHistoryFromPrompt() {
        selectTab(.clipboardHistory)
    }

    // MARK: - Panel & Tab Navigation

    /// Selects a tab and presents the notch panel.
    func selectTab(_ tab: NotchPanelTab, autoHideAfter seconds: TimeInterval? = nil) {
        if notchMode == .idle {
            autoPasteService.rememberFrontmostApp()
        }
        let resolvedTab = validatedTab(tab)
        activeTab = resolvedTab
        notchMode = .showingPanel(tab: resolvedTab)
        presenter?.presentPanel(autoHideAfter: seconds)
    }

    /// Transitions to a plugin's activity panel tab in the notch.
    func switchToPluginActivity(pluginID: String, autoHideAfter seconds: TimeInterval? = 4) {
        if notchMode == .idle {
            autoPasteService.rememberFrontmostApp()
        }
        let tab: NotchPanelTab = .pluginActivity(pluginID: pluginID)
        activeTab = tab
        notchMode = .showingPanel(tab: tab)
        presenter?.presentPanel(autoHideAfter: seconds)
    }

    /// Triggered when the pointer enters the notch hover zone.
    func showPanelFromHover() {
        guard !notchMode.isPrompting else { return }
        guard !notchMode.isShowingPanel else { return }

        autoPasteService.rememberFrontmostApp()
        let tab = validatedTab(activeTab)
        activeTab = tab
        notchMode = .showingPanel(tab: tab)
        presenter?.presentPanel(autoHideAfter: nil)
    }

    /// Backward-compatible alias for `showPanelFromHover()`.
    func showDownloadsFromHover() {
        showPanelFromHover()
    }

    /// Opened explicitly from the menu bar.
    func showPanelFromMenu(tab: NotchPanelTab? = nil, autoHideAfter seconds: TimeInterval? = 6) {
        guard !notchMode.isPrompting else { return }

        if notchMode == .idle {
            autoPasteService.rememberFrontmostApp()
        }
        let resolvedTab = validatedTab(tab ?? activeTab)
        activeTab = resolvedTab
        notchMode = .showingPanel(tab: resolvedTab)
        presenter?.presentPanel(autoHideAfter: seconds)
    }

    /// Backward-compatible alias for `showPanelFromMenu()`.
    func showDownloadsFromMenu() {
        showPanelFromMenu()
    }

    func hideFromHover() {
        guard notchMode.isShowingPanel else { return }
        notchMode = .idle
        presenter?.hide()
    }

    func hideFromTimeout() {
        guard notchMode.isShowingPanel else { return }
        notchMode = .idle
        presenter?.hide()
    }

    func hideNotch() {
        guard notchMode != .idle else { return }
        notchMode = .idle
        presenter?.hide()
    }

    // MARK: - Auto-Paste

    /// Writes `item` to the system pasteboard (`ignoreNextChangeCount` armed so no duplicate
    /// entry is recorded) and, when `settings.autoPasteOnSelect` is enabled and `forceCopyOnly`
    /// is `false`, hides the notch, restores focus to the remembered frontmost application,
    /// and synthesizes `⌘V`.
    ///
    /// - Parameters:
    ///   - item: The clipboard history entry selected by the user.
    ///   - forceCopyOnly: Pass `true` (e.g. when `⌥ Option` is held) to force copy-only behavior.
    /// - Returns: `.pasted` when `⌘V` was sent, or `.copiedOnly(reason:)` when degraded to copy-only.
    @discardableResult
    func autoPaste(item: ClipboardItem, forceCopyOnly: Bool = false) async -> PasteResult {
        historyStore.copyToPasteboard(item)

        if forceCopyOnly {
            let result: PasteResult = .copiedOnly(reason: .forcedCopyModifier)
            lastPasteResult = result
            return result
        }

        guard settings.autoPasteOnSelect else {
            let result: PasteResult = .copiedOnly(reason: .disabledInSettings)
            lastPasteResult = result
            return result
        }

        guard autoPasteService.canAutoPaste() else {
            let reason = AutoPasteSkipReason.accessibilityPermissionMissing
            if let message = reason.userFacingMessage {
                notifyUser(message: message, icon: "hand.raised.fill")
            }
            let result: PasteResult = .copiedOnly(reason: reason)
            lastPasteResult = result
            return result
        }

        // Collapse the notch immediately and relinquish key-window focus before
        // activating the target application and posting ⌘V. DynamicNotch.hide()
        // animates for ~400ms before closing its NSPanel; ordering the panel out
        // synchronously prevents the synthesized ⌘V from being swallowed by the notch.
        await hideNotchForAutoPaste()

        let result = await autoPasteService.paste()
        lastPasteResult = result

        if result.didPaste {
            activeNotification = nil
        } else if case .copiedOnly(let reason) = result,
                  let message = reason.userFacingMessage {
            notifyUser(message: message, icon: "info.circle.fill")
        }

        return result
    }

    private func hideNotchForAutoPaste() async {
        guard notchMode != .idle else { return }
        notchMode = .idle
        await presenter?.hideImmediatelyForAutoPaste()
    }

    // MARK: - Context helpers

    private func writePayloadToClipboard(_ payload: ClipboardPayload) {
        var newItem = ClipboardItem(
            changeCount: 0,
            payload: payload
        )
        let matchedPlugins = featureRegistry.matchingPlugins(for: newItem)
        newItem.detectedFeatureIDs = matchedPlugins.map(\.id)
        historyStore.copyToPasteboard(newItem)
    }

    private func notifyUser(message: String, icon: String) {
        activeNotification = FeatureUserNotification(message: message, icon: icon)
    }

    /// Ensures the requested tab is still valid (e.g. if a plugin was disabled, falls back to `.clipboardHistory`).
    private func validatedTab(_ tab: NotchPanelTab) -> NotchPanelTab {
        switch tab {
        case .clipboardHistory:
            return .clipboardHistory
        case .pluginActivity(let pluginID):
            if let plugin = featureRegistry.plugin(withID: pluginID),
               featureRegistry.isPluginEnabled(pluginID),
               plugin.hasActivityPanel {
                return tab
            }
            return .clipboardHistory
        }
    }

    // MARK: - Lifecycle

    func shutdown() {
        featureRegistry.shutdownAll()
        historyStore.flushPendingPersistence()
        activeNotification = nil
        notchMode = .idle
        presenter?.hide()
    }
}

//
//  AppEnvironment.swift
//  NotchTubeAudio
//

import AppKit
import Foundation

/// Composition root. Everything is created once on the main actor and wired
/// together here.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let settings: SettingsManager
    let downloadManager: DownloadManager
    let youtubePlugin: YouTubeAudioFeaturePlugin
    let urlCleanerPlugin: URLCleanerFeaturePlugin
    let jsonFormatterPlugin: JSONFormatterFeaturePlugin
    let colorConverterPlugin: ColorConverterFeaturePlugin
    let ocrPlugin: OCRFeaturePlugin
    let fileActionsPlugin: FileActionsFeaturePlugin
    let historyStore: ClipboardHistoryStore
    let featureRegistry: FeatureRegistry
    let autoPasteService: AutoPasteService
    let appState: AppState
    let clipboardMonitor: ClipboardMonitor
    let globalHotKeyService: GlobalHotKeyService
    let notchController: NotchController

    private var isStarted = false

    private init() {
        let settings = SettingsManager()
        let downloads = DownloadManager(settings: settings)
        let youtubePlugin = YouTubeAudioFeaturePlugin(
            settings: settings,
            downloadManager: downloads
        )
        let urlCleanerPlugin = URLCleanerFeaturePlugin()
        let jsonFormatterPlugin = JSONFormatterFeaturePlugin()
        let colorConverterPlugin = ColorConverterFeaturePlugin()
        let ocrPlugin = OCRFeaturePlugin()
        let fileActionsPlugin = FileActionsFeaturePlugin()
        let clipboard = ClipboardMonitor(settings: settings)
        let historyStore = ClipboardHistoryStore(
            settings: settings,
            clipboardMonitor: clipboard
        )
        let featureRegistry = FeatureRegistry(
            settings: settings,
            plugins: [
                youtubePlugin,
                urlCleanerPlugin,
                jsonFormatterPlugin,
                colorConverterPlugin,
                ocrPlugin,
                fileActionsPlugin
            ]
        )
        let autoPasteService = AutoPasteService()
        let appState = AppState(
            settings: settings,
            historyStore: historyStore,
            featureRegistry: featureRegistry,
            autoPasteService: autoPasteService
        )
        let notch = NotchController(appState: appState, settings: settings)
        let globalHotKeyService = GlobalHotKeyService()

        self.settings = settings
        self.downloadManager = downloads
        self.youtubePlugin = youtubePlugin
        self.urlCleanerPlugin = urlCleanerPlugin
        self.jsonFormatterPlugin = jsonFormatterPlugin
        self.colorConverterPlugin = colorConverterPlugin
        self.ocrPlugin = ocrPlugin
        self.fileActionsPlugin = fileActionsPlugin
        self.historyStore = historyStore
        self.featureRegistry = featureRegistry
        self.autoPasteService = autoPasteService
        self.appState = appState
        self.clipboardMonitor = clipboard
        self.globalHotKeyService = globalHotKeyService
        self.notchController = notch

        appState.presenter = notch
        clipboard.onCapture = { [weak appState] item in
            appState?.handleCapturedItem(item)
        }
        globalHotKeyService.onHotKey = { [weak appState] in
            appState?.openClipboardFromHotKey()
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        NSApp.setActivationPolicy(.accessory)
        autoPasteService.startObservingFrontmostApplications()
        do {
            try globalHotKeyService.start()
        } catch {
            Log.app.warning(
                "Global hotkey \(self.globalHotKeyService.hotKey.displayString, privacy: .public) unavailable: \(String(describing: error), privacy: .public)"
            )
        }
        featureRegistry.startAllEnabled()
        notchController.start()
        clipboardMonitor.start()

        Log.app.info("NotchTubeAudio started")
        if !settings.areBinariesAvailable {
            Log.app.warning("yt-dlp or ffmpeg are not available at the configured paths")
        }
    }

    func shutdown() {
        guard isStarted else { return }
        isStarted = false

        clipboardMonitor.stop()
        globalHotKeyService.stop()
        notchController.stop()
        autoPasteService.stopObservingFrontmostApplications()
        appState.shutdown()
        downloadManager.terminateAllProcesses()

        Log.app.info("NotchTubeAudio stopped")
    }

    // MARK: - Actions shared with the menu bar

    func openDownloadFolder() {
        FileActions.openFolder(settings.downloadDirectory)
    }

    /// Forces capture of the current pasteboard item and routes it through `AppState`,
    /// even if automatic monitoring is disabled.
    func detectClipboardNow() {
        runActionOnCurrentClipboard()
    }

    /// Evaluates the current clipboard (or the most recent history entry) against
    /// `FeatureRegistry` and triggers the highest-priority compatible plugin's prompt
    /// or quick action in the notch.
    func runActionOnCurrentClipboard() {
        let candidateItem: ClipboardItem
        if let captured = clipboardMonitor.captureCurrentPasteboard(force: true) {
            let matchedPlugins = featureRegistry.matchingPlugins(for: captured)
            var annotated = captured
            annotated.detectedFeatureIDs = matchedPlugins.map(\.id)
            historyStore.record(annotated)
            candidateItem = historyStore.items.first(where: { $0.contentHash == annotated.contentHash }) ?? annotated
        } else if let latest = historyStore.items.first {
            candidateItem = latest
        } else {
            NSSound.beep()
            return
        }

        let matching = featureRegistry.matchingPlugins(for: candidateItem)
        for plugin in matching {
            if plugin.makePromptView(
                for: candidateItem,
                context: appState.actionContext,
                onComplete: {},
                onDismiss: {}
            ) != nil {
                appState.presentPluginPrompt(pluginID: plugin.id, for: candidateItem)
                return
            }
        }

        if let firstQuickAction = featureRegistry.quickActions(for: candidateItem, context: appState.actionContext).first {
            firstQuickAction.handler()
            return
        }

        appState.showPanelFromMenu(tab: .clipboardHistory)
    }

    /// Símbolo SF Symbol para `MenuBarExtra`, cambiando dinámicamente cuando hay tareas
    /// activas en algún módulo habilitado.
    var menuBarIconSystemName: String {
        if featureRegistry.totalActiveTasksCount > 0 {
            return "arrow.down.circle.fill"
        }
        return "doc.on.clipboard.fill"
    }

    var hasClipboardLink: Bool {
        guard let payload = clipboardMonitor.extractPayload(),
              let raw = payload.stringValue else {
            return false
        }
        return YouTubeURLParser.parse(raw) != nil
    }

    var isNotchShowing: Bool {
        appState.notchMode != .idle
    }
}

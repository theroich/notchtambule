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
    let historyStore: ClipboardHistoryStore
    let featureRegistry: FeatureRegistry
    let appState: AppState
    let clipboardMonitor: ClipboardMonitor
    let notchController: NotchController

    private var isStarted = false

    private init() {
        let settings = SettingsManager()
        let downloads = DownloadManager(settings: settings)
        let clipboard = ClipboardMonitor(settings: settings)
        let historyStore = ClipboardHistoryStore(
            settings: settings,
            clipboardMonitor: clipboard
        )
        let featureRegistry = FeatureRegistry(settings: settings)
        let appState = AppState(
            settings: settings,
            historyStore: historyStore,
            featureRegistry: featureRegistry
        )
        let notch = NotchController(appState: appState, settings: settings)

        self.settings = settings
        self.downloadManager = downloads
        self.historyStore = historyStore
        self.featureRegistry = featureRegistry
        self.appState = appState
        self.clipboardMonitor = clipboard
        self.notchController = notch

        appState.presenter = notch
        clipboard.onCapture = { [weak appState] item in
            appState?.handleCapturedItem(item)
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        NSApp.setActivationPolicy(.accessory)
        featureRegistry.startAllEnabled()
        notchController.start()
        clipboardMonitor.start()

        Log.app.info("NotchTubeAudio iniciado")
        if !settings.areBinariesAvailable {
            Log.app.warning("yt-dlp o ffmpeg no están disponibles en las rutas configuradas")
        }
    }

    func shutdown() {
        guard isStarted else { return }
        isStarted = false

        clipboardMonitor.stop()
        notchController.stop()
        appState.shutdown()
        downloadManager.terminateAllProcesses()

        Log.app.info("NotchTubeAudio finalizado")
    }

    // MARK: - Actions shared with the menu bar

    func openDownloadFolder() {
        FileActions.openFolder(settings.downloadDirectory)
    }

    /// Forces capture of the current pasteboard item and routes it through `AppState`,
    /// even if automatic monitoring is disabled.
    func detectClipboardNow() {
        guard let item = clipboardMonitor.captureCurrentPasteboard(force: true) else {
            NSSound.beep()
            return
        }
        appState.handleCapturedItem(item)
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

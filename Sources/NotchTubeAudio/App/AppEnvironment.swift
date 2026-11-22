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
    let appState: AppState
    let clipboardMonitor: ClipboardMonitor
    let notchController: NotchController

    private var isStarted = false

    private init() {
        let settings = SettingsManager()
        let downloads = DownloadManager(settings: settings)
        let metadata = YouTubeMetadataService()
        let appState = AppState(
            settings: settings,
            downloadManager: downloads,
            metadataService: metadata
        )
        let clipboard = ClipboardMonitor(settings: settings)
        let notch = NotchController(appState: appState, settings: settings)

        self.settings = settings
        self.downloadManager = downloads
        self.appState = appState
        self.clipboardMonitor = clipboard
        self.notchController = notch

        appState.presenter = notch
        clipboard.onCapture = { [weak appState] item in
            appState?.handleClipboardItem(item)
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        NSApp.setActivationPolicy(.accessory)
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

    /// Forces a notification for whatever YouTube link is on the pasteboard,
    /// even if automatic monitoring is disabled.
    func detectClipboardNow() {
        guard let item = clipboardMonitor.captureCurrentPasteboard(force: true),
              let link = AppState.extractYouTubeLink(from: item) else {
            NSSound.beep()
            return
        }
        appState.handleClipboardLink(link)
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

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
    /// Expand the notch showing the detected link prompt.
    func presentPrompt()
    /// Expand the notch showing the download queue.
    /// - Parameter autoHideAfter: hides automatically when the pointer is not
    ///   inside the notch. `nil` keeps it open until the pointer leaves.
    func presentDownloads(autoHideAfter seconds: TimeInterval?)
    /// Collapse the notch.
    func hide()
}

/// Global application state: the current notch mode, the detected video and the
/// metadata request lifecycle.
@MainActor
@Observable
final class AppState {
    private(set) var notchMode: NotchMode = .idle
    private(set) var detectedVideo: DetectedVideo?
    private(set) var lastDetectedURLString: String?

    /// Format preselected in the prompt. Reset on every new detection.
    var promptFormat: AudioFormat

    let settings: SettingsManager
    let downloadManager: DownloadManager

    @ObservationIgnored weak var presenter: (any NotchPresenting)?
    @ObservationIgnored private let metadataService: YouTubeMetadataService
    @ObservationIgnored private var metadataTask: Task<Void, Never>?

    init(
        settings: SettingsManager,
        downloadManager: DownloadManager,
        metadataService: YouTubeMetadataService
    ) {
        self.settings = settings
        self.downloadManager = downloadManager
        self.metadataService = metadataService
        self.promptFormat = settings.defaultFormat
    }

    // MARK: - Clipboard flow

    /// Entry point used by ``ClipboardMonitor`` for universal clipboard items.
    ///
    /// Bridges `.url` and `.text` payloads containing a YouTube URL to the existing
    /// prompt workflow until the plugin router (Issues #3–#5) takes over.
    func handleClipboardItem(_ item: ClipboardItem) {
        if let link = Self.extractYouTubeLink(from: item) {
            handleClipboardLink(link)
        }
    }

    /// Entry point for a validated YouTube link.
    func handleClipboardLink(_ link: YouTubeLink) {
        lastDetectedURLString = link.canonicalURLString
        presentPrompt(for: link)
    }

    static func extractYouTubeLink(from item: ClipboardItem) -> YouTubeLink? {
        switch item.payload {
        case .url(let url, let rawText):
            return YouTubeURLParser.parse(rawText) ?? YouTubeURLParser.parse(url.absoluteString)
        case .text(let text):
            return YouTubeURLParser.parse(text)
        case .files, .image:
            return nil
        }
    }

    func presentPrompt(for link: YouTubeLink) {
        metadataTask?.cancel()

        let placeholder = DetectedVideo(link: link)
        detectedVideo = placeholder
        promptFormat = settings.defaultFormat
        notchMode = .promptingURL
        presenter?.presentPrompt()

        metadataTask = Task { [weak self] in
            guard let self else { return }

            let metadata = await self.metadataService.metadata(for: link)
            guard !Task.isCancelled else { return }

            // The user may have closed the prompt, saved it or copied another
            // link while the request was in flight.
            guard
                let current = self.detectedVideo,
                current.videoID == link.videoID,
                self.notchMode == .promptingURL
            else { return }

            if let metadata {
                self.detectedVideo = current.applying(metadata)
            } else {
                // Fallback: keep the clean URL as the title.
                self.detectedVideo = current.finishedLoading()
            }
        }
    }

    // MARK: - Prompt actions

    func savePrompt(format: AudioFormat) {
        guard notchMode == .promptingURL, let video = detectedVideo else { return }

        metadataTask?.cancel()
        promptFormat = format
        detectedVideo = nil
        downloadManager.enqueue(video: video, format: format)

        notchMode = .showingDownloads
        // Show the progress briefly, then let the hover logic take over.
        presenter?.presentDownloads(autoHideAfter: 4)
    }

    func dismissPrompt() {
        guard notchMode == .promptingURL else { return }
        metadataTask?.cancel()
        detectedVideo = nil
        notchMode = .idle
        presenter?.hide()
    }

    /// Called by the auto-dismiss timer.
    func dismissPromptFromTimeout() {
        dismissPrompt()
    }

    // MARK: - Downloads view

    /// Triggered when the pointer enters the notch hover zone.
    func showDownloadsFromHover() {
        guard notchMode != .promptingURL else { return }
        guard notchMode != .showingDownloads else { return }

        notchMode = .showingDownloads
        presenter?.presentDownloads(autoHideAfter: nil)
    }

    /// Opened explicitly from the menu bar.
    func showDownloadsFromMenu() {
        guard notchMode != .promptingURL else { return }
        notchMode = .showingDownloads
        presenter?.presentDownloads(autoHideAfter: 6)
    }

    func hideFromHover() {
        guard notchMode == .showingDownloads else { return }
        notchMode = .idle
        presenter?.hide()
    }

    func hideFromTimeout() {
        guard notchMode == .showingDownloads else { return }
        notchMode = .idle
        presenter?.hide()
    }

    // MARK: - Lifecycle

    func shutdown() {
        metadataTask?.cancel()
        metadataTask = nil
        detectedVideo = nil
        notchMode = .idle
        presenter?.hide()
    }
}

//
//  YouTubeAudioFeaturePlugin.swift
//  NotchTubeAudio
//

import Foundation
import Observation
import SwiftUI

/// Autonomous feature module that encapsulates YouTube URL detection,
/// oEmbed metadata resolution, the notch download prompt, quick actions in
/// clipboard history rows, and the background yt-dlp/ffmpeg download queue.
@MainActor
@Observable
final class YouTubeAudioFeaturePlugin: ClipboardFeaturePlugin {
    static let pluginID = "com.notchclip.plugin.youtube-audio"

    let id: String = YouTubeAudioFeaturePlugin.pluginID
    let displayName: String = "YouTube Audio"
    let summary: String = "Detecta enlaces de YouTube y permite descargar su audio en MP3 o WAV usando yt-dlp y ffmpeg."
    let iconSystemName: String = "waveform.badge.mic"
    let priority: FeaturePriority = .high
    let defaultTriggerBehavior: FeatureTriggerBehavior = .automaticPrompt

    let settings: SettingsManager
    let downloadManager: DownloadManager
    @ObservationIgnored private let metadataService: any YouTubeMetadataFetching

    // MARK: - Internal Prompt State

    private(set) var detectedVideo: DetectedVideo?
    var promptFormat: AudioFormat

    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private var activePromptItemID: UUID?

    init(
        settings: SettingsManager,
        downloadManager: DownloadManager? = nil,
        metadataService: any YouTubeMetadataFetching = YouTubeMetadataService()
    ) {
        self.settings = settings
        self.downloadManager = downloadManager ?? DownloadManager(settings: settings)
        self.metadataService = metadataService
        self.promptFormat = settings.defaultFormat
    }

    // MARK: - Lifecycle

    func start() {
        downloadManager.resumeAcceptingDownloads()
    }

    func shutdown() {
        cancelMetadataTask()
        detectedVideo = nil
        activePromptItemID = nil
        downloadManager.terminateAllProcesses()
    }

    // MARK: - Detection

    func canHandle(_ item: ClipboardItem) -> Bool {
        extractLink(from: item) != nil
    }

    func extractLink(from item: ClipboardItem) -> YouTubeLink? {
        switch item.payload {
        case .url(_, let rawText), .text(let rawText):
            return YouTubeURLParser.parse(rawText)
        default:
            return nil
        }
    }

    // MARK: - Quick Actions

    func quickActions(for item: ClipboardItem, context: FeatureActionContext) -> [FeatureQuickAction] {
        guard let link = extractLink(from: item) else { return [] }

        return [
            FeatureQuickAction(
                id: "\(id).download-mp3.\(item.id.uuidString)",
                pluginID: id,
                title: "Descargar MP3",
                iconSystemName: "arrow.down.circle"
            ) { [weak self] in
                self?.enqueueQuickDownload(for: link, format: .mp3, context: context)
            },
            FeatureQuickAction(
                id: "\(id).download-wav.\(item.id.uuidString)",
                pluginID: id,
                title: "Descargar WAV",
                iconSystemName: "waveform"
            ) { [weak self] in
                self?.enqueueQuickDownload(for: link, format: .wav, context: context)
            }
        ]
    }

    // MARK: - Prompt View

    func makePromptView(
        for item: ClipboardItem,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView? {
        guard let link = extractLink(from: item) else {
            return nil
        }

        preparePromptStateIfNeeded(for: item.id, link: link)

        let fallbackVideo = detectedVideo ?? DetectedVideo(link: link)
        return AnyView(
            YouTubePluginPromptHostView(
                plugin: self,
                fallbackVideo: fallbackVideo,
                context: context,
                onComplete: onComplete,
                onDismiss: onDismiss
            )
        )
    }

    /// Enqueues the currently detected video with `promptFormat`, switches the notch
    /// to the downloads activity panel, cleans up the metadata task, and completes the prompt.
    func confirmPromptDownload(
        context: FeatureActionContext,
        onComplete: () -> Void = {}
    ) {
        guard let currentVideo = detectedVideo else { return }
        let videoToEnqueue = currentVideo.isLoading ? currentVideo.finishedLoading() : currentVideo
        let selectedFormat = promptFormat

        cancelMetadataTask()
        detectedVideo = nil
        activePromptItemID = nil

        downloadManager.enqueue(video: videoToEnqueue, format: selectedFormat)
        context.switchToPluginActivity(pluginID: id)
        onComplete()
    }

    /// Cancels any in-flight oEmbed metadata request, clears prompt state, and dismisses the prompt.
    func cancelPrompt(onDismiss: () -> Void = {}) {
        cancelMetadataTask()
        detectedVideo = nil
        activePromptItemID = nil
        onDismiss()
    }

    // MARK: - Activity Panel

    var hasActivityPanel: Bool { true }

    var activeTasksCount: Int {
        downloadManager.activeCount
    }

    func makeActivityPanelView(context: FeatureActionContext) -> AnyView? {
        AnyView(DownloadQueueView(downloadManager: downloadManager))
    }

    // MARK: - Settings View

    func makeSettingsView() -> AnyView? {
        AnyView(YouTubeAudioSettingsView(settings: settings))
    }

    // MARK: - Helpers

    private func preparePromptStateIfNeeded(for itemID: UUID, link: YouTubeLink) {
        if activePromptItemID == itemID,
           let existing = detectedVideo,
           existing.videoID == link.videoID {
            return
        }

        cancelMetadataTask()
        activePromptItemID = itemID
        promptFormat = settings.defaultFormat
        detectedVideo = DetectedVideo(link: link)

        let service = metadataService
        metadataTask = Task { @MainActor [weak self] in
            let metadata = await service.metadata(for: link)
            guard !Task.isCancelled else { return }
            guard let self,
                  self.activePromptItemID == itemID,
                  let current = self.detectedVideo,
                  current.videoID == link.videoID else {
                return
            }

            if let metadata {
                self.detectedVideo = current.applying(metadata)
            } else {
                self.detectedVideo = current.finishedLoading()
            }
        }
    }

    private func enqueueQuickDownload(
        for link: YouTubeLink,
        format: AudioFormat,
        context: FeatureActionContext
    ) {
        let initialVideo: DetectedVideo
        if let existing = detectedVideo, existing.videoID == link.videoID {
            initialVideo = existing.isLoading ? existing.finishedLoading() : existing
        } else {
            initialVideo = DetectedVideo(link: link).finishedLoading()
        }

        downloadManager.enqueue(video: initialVideo, format: format)
        context.switchToPluginActivity(pluginID: id)

        if initialVideo.title == link.displayURL,
           let enqueuedItem = downloadManager.items.first(where: { $0.videoID == link.videoID && $0.format == format }) {
            let service = metadataService
            Task { @MainActor in
                if let metadata = await service.metadata(for: link) {
                    if enqueuedItem.title == link.displayURL {
                        enqueuedItem.title = metadata.title
                    }
                    if enqueuedItem.authorName == nil {
                        enqueuedItem.authorName = metadata.authorName
                    }
                }
            }
        }
    }

    private func cancelMetadataTask() {
        metadataTask?.cancel()
        metadataTask = nil
    }
}

// MARK: - Prompt Host View

@MainActor
private struct YouTubePluginPromptHostView: View {
    let plugin: YouTubeAudioFeaturePlugin
    let fallbackVideo: DetectedVideo
    let context: FeatureActionContext
    let onComplete: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NotchPromptView(
            video: plugin.detectedVideo ?? fallbackVideo,
            format: plugin.promptFormat,
            binariesAvailable: plugin.settings.areBinariesAvailable,
            onSelectFormat: { format in
                plugin.promptFormat = format
            },
            onSave: {
                plugin.confirmPromptDownload(context: context, onComplete: onComplete)
            },
            onCancel: {
                plugin.cancelPrompt(onDismiss: onDismiss)
            }
        )
    }
}

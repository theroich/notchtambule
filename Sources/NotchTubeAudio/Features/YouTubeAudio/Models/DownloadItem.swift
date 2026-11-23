//
//  DownloadItem.swift
//  NotchTubeAudio
//

import Foundation
import Observation

/// One audio or video download. Observation driven so SwiftUI rows update themselves as
/// yt-dlp reports progress.
@MainActor
@Observable
final class DownloadItem: Identifiable {
    let id = UUID()
    let url: URL
    let canonicalURLString: String
    let videoID: String
    let format: DownloadFormat
    let thumbnailURL: URL?

    var title: String
    var authorName: String?
    var progress: Double
    var status: DownloadStatus
    var outputFileURL: URL?
    var errorMessage: String?

    let createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?

    init(
        url: URL,
        canonicalURLString: String,
        videoID: String,
        title: String,
        authorName: String?,
        thumbnailURL: URL?,
        format: DownloadFormat
    ) {
        self.url = url
        self.canonicalURLString = canonicalURLString
        self.videoID = videoID
        self.title = title
        self.authorName = authorName
        self.thumbnailURL = thumbnailURL
        self.format = format
        self.progress = 0
        self.status = .queued
        self.createdAt = Date()
    }

    convenience init(video: DetectedVideo, format: DownloadFormat) {
        self.init(
            url: video.canonicalURL,
            canonicalURLString: video.canonicalURL.absoluteString,
            videoID: video.videoID,
            title: video.title,
            authorName: video.authorName,
            thumbnailURL: video.thumbnailURL,
            format: format
        )
    }

    /// Human readable state line shown in the notch.
    var statusText: String {
        switch status {
        case .queued:
            return L10n.string("downloads.status.queued")
        case .downloading:
            return L10n.format("downloads.status.downloading_percent", Int64((progress * 100).rounded()))
        case .converting:
            return L10n.string("downloads.status.converting")
        case .merging:
            return L10n.string("downloads.status.merging")
        case .completed:
            return L10n.string("downloads.status.completed")
        case .failed:
            return L10n.string("downloads.status.failed")
        case .cancelled:
            return L10n.string("downloads.status.cancelled")
        }
    }

    var canCancel: Bool {
        status.isActive
    }

    var canReveal: Bool {
        status == .completed && outputFileURL != nil
    }

    var canRetry: Bool {
        status == .failed || status == .cancelled
    }

    /// Reset for a retry without losing identity in the list.
    func prepareForRetry() {
        progress = 0
        status = .queued
        outputFileURL = nil
        errorMessage = nil
        startedAt = nil
        finishedAt = nil
    }
}

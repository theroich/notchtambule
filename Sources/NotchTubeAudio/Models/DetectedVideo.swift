//
//  DetectedVideo.swift
//  NotchTubeAudio
//

import Foundation

/// Metadata displayed in the "new URL detected" prompt.
struct DetectedVideo: Identifiable, Equatable, Sendable {
    let videoID: String
    let canonicalURL: URL
    let title: String
    let authorName: String?
    let thumbnailURL: URL?
    /// `true` while the oEmbed request is in flight.
    let isLoading: Bool

    var id: String { videoID }

    var displayURL: String {
        "youtube.com/watch?v=\(videoID)"
    }

    init(
        videoID: String,
        canonicalURL: URL,
        title: String,
        authorName: String?,
        thumbnailURL: URL?,
        isLoading: Bool
    ) {
        self.videoID = videoID
        self.canonicalURL = canonicalURL
        self.title = title
        self.authorName = authorName
        self.thumbnailURL = thumbnailURL
        self.isLoading = isLoading
    }

    /// Instant placeholder shown before oEmbed finishes.
    init(link: YouTubeLink) {
        self.init(
            videoID: link.videoID,
            canonicalURL: link.canonicalURL,
            title: link.displayURL,
            authorName: nil,
            thumbnailURL: link.fallbackThumbnailURL,
            isLoading: true
        )
    }

    func finishedLoading() -> DetectedVideo {
        DetectedVideo(
            videoID: videoID,
            canonicalURL: canonicalURL,
            title: title,
            authorName: authorName,
            thumbnailURL: thumbnailURL,
            isLoading: false
        )
    }

    func applying(_ metadata: YouTubeMetadata) -> DetectedVideo {
        DetectedVideo(
            videoID: videoID,
            canonicalURL: canonicalURL,
            title: metadata.title,
            authorName: metadata.authorName,
            thumbnailURL: metadata.thumbnailURL ?? thumbnailURL,
            isLoading: false
        )
    }
}

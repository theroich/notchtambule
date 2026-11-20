//
//  YouTubeLink.swift
//  NotchTubeAudio
//

import Foundation

/// A validated YouTube video URL.
struct YouTubeLink: Equatable, Hashable, Sendable {
    /// The 11 character YouTube video identifier.
    let videoID: String
    /// The URL the user copied.
    let originalURL: URL

    /// Canonical URL used for oEmbed requests and yt-dlp.
    var canonicalURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: videoID)]
        return components.url ?? originalURL
    }

    var canonicalURLString: String {
        canonicalURL.absoluteString
    }

    /// Short, human readable representation used as fallback title.
    var displayURL: String {
        "youtube.com/watch?v=\(videoID)"
    }

    /// Thumbnail that does not depend on the oEmbed request succeeding.
    var fallbackThumbnailURL: URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }

    /// oEmbed endpoint for this video.
    var oEmbedURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/oembed"
        components.queryItems = [
            URLQueryItem(name: "url", value: canonicalURLString),
            URLQueryItem(name: "format", value: "json")
        ]
        return components.url
    }
}

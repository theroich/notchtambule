//
//  YouTubeMetadataService.swift
//  NotchTubeAudio
//

import Foundation
import os

/// Metadata resolved through YouTube's public oEmbed endpoint.
///
/// oEmbed is dramatically faster than running yt-dlp for a title (usually well
/// under 150 ms), which is what makes the notch prompt feel instant.
struct YouTubeMetadata: Equatable, Sendable {
    let title: String
    let authorName: String?
    let thumbnailURL: URL?
}

/// Contract for resolving video metadata (oEmbed in production, deterministic stubs in tests).
protocol YouTubeMetadataFetching: Sendable {
    func metadata(for link: YouTubeLink) async -> YouTubeMetadata?
}

/// Stateless, `Sendable` network client for oEmbed.
final class YouTubeMetadataService: YouTubeMetadataFetching, Sendable {
    private struct OEmbedResponse: Decodable {
        let title: String
        let authorName: String?
        let thumbnailURL: String?

        enum CodingKeys: String, CodingKey {
            case title
            case authorName = "author_name"
            case thumbnailURL = "thumbnail_url"
        }
    }

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    /// Fetches metadata for `link`. Returns `nil` on any failure so the caller
    /// can keep showing the clean URL fallback.
    func metadata(for link: YouTubeLink) async -> YouTubeMetadata? {
        guard let url = link.oEmbedURL else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else {
                Log.metadata.debug("oEmbed returned a non-2xx response")
                return nil
            }

            let payload = try JSONDecoder().decode(OEmbedResponse.self, from: data)
            let thumbnail = payload.thumbnailURL.flatMap(URL.init(string:)) ?? link.fallbackThumbnailURL

            return YouTubeMetadata(
                title: payload.title,
                authorName: payload.authorName?.isEmpty == true ? nil : payload.authorName,
                thumbnailURL: thumbnail
            )
        } catch is CancellationError {
            return nil
        } catch {
            Log.metadata.debug("oEmbed failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

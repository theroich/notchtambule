//
//  YouTubeURLParser.swift
//  NotchTubeAudio
//

import Foundation

/// Strict validation of YouTube URLs copied to the pasteboard.
///
/// Accepted shapes (scheme optional, host case-insensitive):
/// - `youtube.com/watch?v=VIDEO_ID`
/// - `youtu.be/VIDEO_ID`
/// - `youtube.com/shorts/VIDEO_ID`
/// - `music.youtube.com/watch?v=VIDEO_ID`
/// - `youtube.com/live/VIDEO_ID` and `/embed/VIDEO_ID`
///
/// Anything containing extra prose, several URLs or a non YouTube host is rejected.
enum YouTubeURLParser {
    /// `#/.../#` avoids escaping slashes; the leading scoped option makes the
    /// match case-insensitive.
    ///
    /// `Regex` is immutable and safe to share; the compiler simply does not
    /// mark the type `Sendable` yet.
    nonisolated(unsafe) private static let pattern = #/(?i)^(?:https?://)?(?:www\.|m\.|music\.)?(?:youtube\.com/(?:watch\?(?:[^#\s]*&)?v=|shorts/|live/|embed/)|youtu\.be/)([A-Za-z0-9_-]{11})(?:[?&#/][^\s]*)?$/#

    /// Parses a pasteboard string into a validated link.
    static func parse(_ rawText: String) -> YouTubeLink? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2048 else { return nil }

        guard let match = text.wholeMatch(of: Self.pattern) else { return nil }
        let videoID = String(match.1)

        let urlText = text.lowercased().hasPrefix("http") ? text : "https://\(text)"
        guard let url = URL(string: urlText) else { return nil }

        return YouTubeLink(videoID: videoID, originalURL: url)
    }

    /// Convenience used by menus and the manual refresh action.
    static func parsePasteboardString(_ string: String?) -> YouTubeLink? {
        guard let string else { return nil }
        return parse(string)
    }
}

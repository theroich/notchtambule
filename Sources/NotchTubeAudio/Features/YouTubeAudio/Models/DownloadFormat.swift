//
//  DownloadFormat.swift
//  NotchTubeAudio
//

import Foundation

/// Audio or video container/quality produced by the YouTube download pipeline.
enum DownloadFormat: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case mp3
    case wav
    case mp4_720p
    case mp4_1080p

    /// High-level media category used to group formats in the notch prompt and Settings.
    enum Kind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
        case audio
        case video

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .audio:
                return L10n.string("youtube.prompt.format.audio")
            case .video:
                return L10n.string("youtube.prompt.format.video")
            }
        }

        var iconSystemName: String {
            switch self {
            case .audio:
                return "waveform"
            case .video:
                return "film"
            }
        }

        var formats: [DownloadFormat] {
            switch self {
            case .audio:
                return DownloadFormat.audioFormats
            case .video:
                return DownloadFormat.videoFormats
            }
        }

        var defaultFormat: DownloadFormat {
            switch self {
            case .audio:
                return .mp3
            case .video:
                return .mp4_1080p
            }
        }
    }

    var id: String { rawValue }

    var kind: Kind {
        switch self {
        case .mp3, .wav:
            return .audio
        case .mp4_720p, .mp4_1080p:
            return .video
        }
    }

    var isAudio: Bool {
        kind == .audio
    }

    var isVideo: Bool {
        kind == .video
    }

    /// Maximum vertical resolution for video formats; `nil` for audio-only formats.
    var maxVideoHeight: Int? {
        switch self {
        case .mp3, .wav:
            return nil
        case .mp4_720p:
            return 720
        case .mp4_1080p:
            return 1080
        }
    }

    /// Descriptive label shown in Settings and accessibility descriptions.
    var displayName: String {
        switch self {
        case .mp3:
            return "MP3"
        case .wav:
            return "WAV"
        case .mp4_720p:
            return L10n.string("format.video.720p")
        case .mp4_1080p:
            return L10n.string("format.video.1080p")
        }
    }

    /// Compact label shown inside notch pills and queue badges (`MP3`, `WAV`, `720p`, `1080p`).
    var shortBadge: String {
        switch self {
        case .mp3:
            return "MP3"
        case .wav:
            return "WAV"
        case .mp4_720p:
            return L10n.string("youtube.prompt.video.720p")
        case .mp4_1080p:
            return L10n.string("youtube.prompt.video.1080p")
        }
    }

    /// File extension written by yt-dlp/ffmpeg (`mp3`, `wav`, `mp4`).
    var fileExtension: String {
        switch self {
        case .mp3:
            return "mp3"
        case .wav:
            return "wav"
        case .mp4_720p, .mp4_1080p:
            return "mp4"
        }
    }

    static var audioFormats: [DownloadFormat] {
        [.mp3, .wav]
    }

    static var videoFormats: [DownloadFormat] {
        [.mp4_720p, .mp4_1080p]
    }

    static var allowedFileExtensions: Set<String> {
        Set(allCases.map(\.fileExtension))
    }

    /// Decodes a persisted `UserDefaults` value (including legacy `"mp3"` / `"wav"` values),
    /// falling back to `.mp3` for unknown or missing values.
    static func fromStoredValue(_ rawValue: String?) -> DownloadFormat {
        guard let rawValue else { return .mp3 }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return DownloadFormat(rawValue: normalized) ?? .mp3
    }
}

//
//  AudioFormat.swift
//  NotchTubeAudio
//

import Foundation

/// Audio container produced by the download pipeline.
enum AudioFormat: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case mp3
    case wav

    var id: String { rawValue }

    /// Label shown in the notch and in Settings.
    var displayName: String {
        rawValue.uppercased()
    }

    /// Extension written by yt-dlp/ffmpeg.
    var fileExtension: String {
        rawValue
    }
}

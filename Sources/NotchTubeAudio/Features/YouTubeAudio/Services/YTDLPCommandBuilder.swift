//
//  YTDLPCommandBuilder.swift
//  NotchTubeAudio
//

import Foundation

/// Pure argument builder for invoking `yt-dlp` for audio or MP4 video downloads.
enum YTDLPCommandBuilder {
    /// Builds the `-o` output template for the given format and destination folder.
    ///
    /// Audio files keep `%(title)s.%(ext)s`, while video files include the resolved
    /// vertical height (`%(title)s [%(height)sp].%(ext)s`) to prevent 720p/1080p collisions.
    static func outputTemplate(for format: DownloadFormat, destination: URL) -> String {
        let filenameTemplate: String
        switch format.kind {
        case .audio:
            filenameTemplate = "%(title)s.%(ext)s"
        case .video:
            filenameTemplate = "%(title)s [%(height)sp].%(ext)s"
        }
        return destination.appendingPathComponent(filenameTemplate).path
    }

    /// Builds the `yt-dlp -f` format selector preferring H.264/AAC MP4-compatible
    /// streams for QuickTime and Finder compatibility, with graceful fallback to the
    /// best available streams up to `maxHeight`.
    static func videoFormatSelector(maxHeight: Int) -> String {
        "bv*[height<=\(maxHeight)][vcodec^=avc1]+ba[acodec^=mp4a]/b[height<=\(maxHeight)][ext=mp4]/bv*[height<=\(maxHeight)]+ba/b[height<=\(maxHeight)]"
    }

    /// Produces the full argument array passed to `yt-dlp`.
    static func arguments(
        url: URL,
        format: DownloadFormat,
        ffmpegPath: String,
        destination: URL,
        useFallbackClient: Bool
    ) -> [String] {
        let template = outputTemplate(for: format, destination: destination)

        var arguments = [
            "--newline",
            "--no-playlist",
            // --print implies --quiet; restore the normal log stream so
            // [ExtractAudio] / [Merger] phases can be detected, then force progress.
            "--print", "after_move:filepath",
            "--no-quiet",
            "--progress",
            "--no-colors"
        ]

        switch format.kind {
        case .audio:
            arguments += [
                "-x",
                "--audio-format", format.fileExtension,
                "--audio-quality", "0"
            ]
        case .video:
            let maxHeight = format.maxVideoHeight ?? 1080
            arguments += [
                "-f", videoFormatSelector(maxHeight: maxHeight),
                "--merge-output-format", "mp4"
            ]
        }

        arguments += [
            "--ffmpeg-location", ffmpegPath,
            "--progress-template", "download:%(progress._percent_str)s",
            "-o", template
        ]

        if useFallbackClient {
            // YouTube frequently blocks the default client with HTTP 403 on
            // certain videos. The embedded web client does not require a GVS
            // PO token and is a reliable fallback for both audio and video.
            arguments += ["--extractor-args", "youtube:player_client=web_embedded"]
        }

        arguments.append(url.absoluteString)
        return arguments
    }
}

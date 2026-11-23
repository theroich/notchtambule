//
//  ProcessOutputParser.swift
//  NotchTubeAudio
//

import Foundation

/// Pure parsing helpers for the yt-dlp output stream.
enum ProcessOutputParser {
    /// Removes ANSI escape sequences and trims whitespace/newlines.
    static func normalize(_ line: String) -> String {
        var output = ""
        var isEscaping = false

        for character in line {
            if isEscaping {
                // ANSI SGR/erase sequences terminate with a letter (`m`, `K`, …).
                if character.isLetter {
                    isEscaping = false
                }
                continue
            }
            if character == "\u{1B}" {
                isEscaping = true
                continue
            }
            if character == "\r" {
                continue
            }
            output.append(character)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts the numeric percentage from a progress line.
    ///
    /// Handles `download:  45.3%`, `[download]  45.3% of 3.2MiB` and
    /// `postprocess: 100%`.
    static func percent(from line: String) -> Double? {
        guard let percentIndex = line.firstIndex(of: "%") else { return nil }

        var index = percentIndex
        var collected: [Character] = []

        while index > line.startIndex {
            let previous = line.index(before: index)
            let character = line[previous]
            if character.isNumber || character == "." {
                collected.append(character)
                index = previous
            } else {
                break
            }
        }

        guard !collected.isEmpty else { return nil }
        let numberString = String(collected.reversed())
        guard let value = Double(numberString), value.isFinite else { return nil }
        return min(max(value, 0), 100)
    }

    /// `true` when yt-dlp started the ffmpeg audio extraction or video merge/remux phase.
    static func indicatesConversion(_ line: String) -> Bool {
        line.contains("[ExtractAudio]")
            || line.contains("[ffmpeg]")
            || line.contains("Extracting audio")
            || line.contains("[Merger]")
            || line.contains("[VideoRemuxer]")
            || line.contains("[VideoConvertor]")
            || line.contains("Merging formats")
            || line.contains("Fixing container")
    }

    /// Extracts progress from any of yt-dlp's progress shapes.
    ///
    /// Note: `--progress-template "download:%(progress._percent_str)s"` uses
    /// `download:` as the template *type*, so the actual output is a bare
    /// `  45.3%`. The `download:` prefix and the default `[download]` bar are
    /// handled as well for robustness.
    static func progressPercent(from line: String) -> Double? {
        if line.hasPrefix("download:") || line.hasPrefix("[download]") {
            return percent(from: line)
        }

        // Bare template output, e.g. "45.3%".
        guard line.hasSuffix("%") else { return nil }
        let numeric = line
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(numeric), value.isFinite else { return nil }
        return min(max(value, 0), 100)
    }

    /// Resolves the final output file from a yt-dlp line.
    ///
    /// `--print after_move:filepath` emits a bare path, while `--no-quiet` emits
    /// `[ExtractAudio] Destination: /path/file.mp3` or
    /// `[Merger] Merging formats into "/path/file [1080p].mp4"`.
    /// Intermediate `[download] Destination: ...` lines are ignored.
    static func outputFileURL(
        from line: String,
        destination: URL,
        expectedFormat: DownloadFormat? = nil
    ) -> URL? {
        guard let url = extractCandidateFileURL(from: line, destination: destination) else {
            return nil
        }

        let pathExtension = url.pathExtension.lowercased()
        if let expectedFormat {
            guard pathExtension == expectedFormat.fileExtension else { return nil }
        } else {
            guard DownloadFormat.allowedFileExtensions.contains(pathExtension) else { return nil }
        }

        return url
    }

    /// Detects when `yt-dlp` reports a final file path whose container does not match
    /// `expectedFormat.fileExtension` (e.g. `.mkv` or `.webm` when `.mp4` was expected).
    static func unexpectedOutputFileURL(
        from line: String,
        destination: URL,
        expectedFormat: DownloadFormat
    ) -> URL? {
        guard let url = extractCandidateFileURL(from: line, destination: destination) else {
            return nil
        }

        let pathExtension = url.pathExtension.lowercased()
        guard !pathExtension.isEmpty, pathExtension != expectedFormat.fileExtension else {
            return nil
        }

        let knownMediaExtensions: Set<String> = [
            "mkv", "webm", "mov", "avi", "flv", "m4v", "ts",
            "m4a", "opus", "ogg", "flac", "aac", "mp3", "wav", "mp4"
        ]
        guard knownMediaExtensions.contains(pathExtension) else { return nil }
        return url
    }

    private static func extractCandidateFileURL(from line: String, destination: URL) -> URL? {
        // Ignore raw pre-merge/pre-extraction download destination lines.
        if line.hasPrefix("[download]") {
            return nil
        }

        var candidate = line

        if let mergeRange = line.range(of: "Merging formats into ") {
            candidate = String(line[mergeRange.upperBound...])
        } else if let destinationRange = line.range(of: "Destination: ") {
            candidate = String(line[destinationRange.upperBound...])
        } else if line.hasPrefix("[") {
            return nil
        }

        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("\"") && candidate.hasSuffix("\"") && candidate.count > 1 {
            candidate = String(candidate.dropFirst().dropLast())
        }

        guard !candidate.isEmpty else { return nil }
        let pathExtension = (candidate as NSString).pathExtension.lowercased()
        guard !pathExtension.isEmpty else { return nil }

        let expanded = (candidate as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        } else {
            return destination.appendingPathComponent(expanded)
        }
    }

    /// Picks the best human readable line for an error message.
    static func meaningfulError(from lines: [String]) -> String? {
        for line in lines.reversed() {
            let normalized = normalize(line)
            guard !normalized.isEmpty else { continue }
            if normalized.hasPrefix("ERROR:") {
                return String(normalized.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        for line in lines.reversed() {
            let normalized = normalize(line)
            if !normalized.isEmpty {
                return normalized
            }
        }
        return nil
    }
}

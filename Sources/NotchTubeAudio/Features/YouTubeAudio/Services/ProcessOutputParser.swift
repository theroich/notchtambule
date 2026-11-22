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

    /// `true` when yt-dlp started the ffmpeg extraction phase.
    static func indicatesConversion(_ line: String) -> Bool {
        line.contains("[ExtractAudio]")
            || line.contains("[ffmpeg]")
            || line.contains("Extracting audio")
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

    /// Resolves the final audio file from a yt-dlp line.
    ///
    /// `--print after_move:filepath` emits a bare path, while `--no-quiet` emits
    /// `[ExtractAudio] Destination: /path/file.mp3`.
    static func outputFileURL(from line: String, destination: URL) -> URL? {
        var candidate = line

        if let destinationRange = line.range(of: "Destination: ") {
            candidate = String(line[destinationRange.upperBound...])
        } else if line.hasPrefix("[") {
            return nil
        }

        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("\"") && candidate.hasSuffix("\"") && candidate.count > 1 {
            candidate = String(candidate.dropFirst().dropLast())
        }

        let pathExtension = (candidate as NSString).pathExtension.lowercased()
        guard let format = AudioFormat(rawValue: pathExtension) else { return nil }

        let expanded = (candidate as NSString).expandingTildeInPath
        let url: URL
        if expanded.hasPrefix("/") {
            url = URL(fileURLWithPath: expanded)
        } else {
            url = destination.appendingPathComponent(expanded)
        }

        guard url.pathExtension.lowercased() == format.fileExtension else { return nil }
        return url
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

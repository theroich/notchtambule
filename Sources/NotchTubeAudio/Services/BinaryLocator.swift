//
//  BinaryLocator.swift
//  NotchTubeAudio
//

import Foundation

/// Helps the app find `yt-dlp` / `ffmpeg` and validate user supplied paths.
enum BinaryLocator {
    static let commonDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin"
    ]

    static func isExecutable(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        guard !expanded.isEmpty else { return false }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) else {
            return false
        }
        guard !isDirectory.boolValue else { return false }
        return FileManager.default.isExecutableFile(atPath: expanded)
    }

    /// Returns the first executable named `name` found in the preferred path,
    /// Homebrew locations and `PATH`.
    static func locate(_ name: String, preferredPath: String? = nil) -> String? {
        var candidates: [String] = []

        if let preferredPath, !preferredPath.isEmpty {
            candidates.append((preferredPath as NSString).expandingTildeInPath)
        }

        for directory in commonDirectories {
            candidates.append("\(directory)/\(name)")
        }

        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for directory in pathDirectories {
            candidates.append("\(directory)/\(name)")
        }

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            if isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }
}

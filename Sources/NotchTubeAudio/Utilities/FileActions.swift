//
//  FileActions.swift
//  NotchTubeAudio
//

import AppKit

/// Finder related actions shared by the notch UI and the menu bar.
@MainActor
enum FileActions {
    /// Filters the provided URLs to existing local file URLs, preserving order.
    static func existingURLs(from urls: [URL]) -> [URL] {
        urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Reveals a finished file in Finder.
    static func reveal(_ url: URL) {
        reveal([url])
    }

    /// Reveals one or more existing files in Finder.
    static func reveal(_ urls: [URL]) {
        let existing = existingURLs(from: urls)
        guard !existing.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }

    /// Opens existing file URLs with their default applications and returns any URLs that failed to open.
    @discardableResult
    static func open(_ urls: [URL]) -> [URL] {
        var failed: [URL] = []
        for url in urls where url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else {
                failed.append(url)
                continue
            }
            if !NSWorkspace.shared.open(url) {
                failed.append(url)
            }
        }
        return failed
    }

    /// Formats file URLs as POSIX paths separated by newlines, preserving order and without a trailing newline.
    static func formatPOSIXPaths(_ urls: [URL]) -> String {
        urls.map(\.path).joined(separator: "\n")
    }

    /// Opens a folder, creating it when needed.
    @discardableResult
    static func openFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                Log.app.error("Could not create folder: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        return NSWorkspace.shared.open(url)
    }

    /// Ensures the destination exists and is a directory.
    static func ensureDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            return
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

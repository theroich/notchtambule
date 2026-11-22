//
//  FileActions.swift
//  NotchTubeAudio
//

import AppKit

/// Finder related actions shared by the notch UI and the menu bar.
@MainActor
enum FileActions {
    /// Reveals a finished file in Finder.
    static func reveal(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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

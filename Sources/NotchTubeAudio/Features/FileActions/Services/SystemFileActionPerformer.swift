//
//  SystemFileActionPerformer.swift
//  NotchTubeAudio
//

import AppKit
import Foundation

/// Default `FileActionPerforming` implementation backed by `NSWorkspace` and `FileManager`.
@MainActor
final class SystemFileActionPerformer: FileActionPerforming {
    init() {}

    func reveal(_ urls: [URL]) {
        FileActions.reveal(urls)
    }

    func open(_ urls: [URL]) -> [URL] {
        FileActions.open(urls)
    }

    func openInTerminal(directory: URL, application: FileActionsTerminalApp) throws {
        guard application != .none,
              let bundleID = application.bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw FileActionError.terminalUnavailable(application.displayName)
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw FileActionError.noExistingFiles
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([directory], withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error {
                Log.app.error("Failed to open terminal \(application.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func existingURLs(from urls: [URL]) -> [URL] {
        FileActions.existingURLs(from: urls)
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

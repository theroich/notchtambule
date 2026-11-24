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

        // Resolve the localized terminal name here, on the main actor. Reading it inside the
        // completion handler would drag `L10n` (and therefore main-actor isolation) into it.
        let terminalName = application.displayName

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // `NSWorkspace` invokes this completion handler on a concurrent queue
        // (`com.apple.launchservices.open-queue`). Marking the closure `@Sendable` keeps it
        // out of the surrounding `@MainActor` isolation: an isolated closure trips the runtime
        // executor assertion (`dispatch_assert_queue` -> SIGTRAP) as soon as LaunchServices
        // finishes opening the terminal, which crashed the app.
        NSWorkspace.shared.open([directory], withApplicationAt: appURL, configuration: configuration) { @Sendable _, error in
            guard let error else { return }
            Log.app.error("Failed to open terminal \(terminalName, privacy: .public): \(error.localizedDescription, privacy: .public)")
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

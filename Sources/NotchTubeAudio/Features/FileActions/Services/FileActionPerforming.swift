//
//  FileActionPerforming.swift
//  NotchTubeAudio
//
//  Created for Issue #20.
//

import Foundation

/// Supported terminal applications for the optional "Open in Terminal" action.
enum FileActionsTerminalApp: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case terminal
    case iterm
    case ghostty
    case warp
    case kitty
    case alacritty

    var id: String { rawValue }

    var bundleIdentifier: String? {
        switch self {
        case .none:
            return nil
        case .terminal:
            return "com.apple.Terminal"
        case .iterm:
            return "com.googlecode.iterm2"
        case .ghostty:
            return "com.mitchellh.ghostty"
        case .warp:
            return "dev.warp.Warp-Stable"
        case .kitty:
            return "net.kovidgoyal.kitty"
        case .alacritty:
            return "org.alacritty"
        }
    }

    var displayName: String {
        switch self {
        case .none:
            return L10n.string("plugin.file_actions.terminal.none")
        case .terminal:
            return "Terminal"
        case .iterm:
            return "iTerm2"
        case .ghostty:
            return "Ghostty"
        case .warp:
            return "Warp"
        case .kitty:
            return "Kitty"
        case .alacritty:
            return "Alacritty"
        }
    }
}

/// Errors produced when executing file quick actions.
enum FileActionError: LocalizedError, Equatable, Sendable {
    case noExistingFiles
    case terminalUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noExistingFiles:
            return L10n.string("plugin.file_actions.notify.no_existing_files")
        case .terminalUnavailable(let appName):
            return L10n.format("plugin.file_actions.notify.terminal_unavailable", appName)
        }
    }
}

/// Injectable abstraction over Finder / Workspace / FileManager operations for unit testing.
@MainActor
protocol FileActionPerforming: AnyObject {
    func reveal(_ urls: [URL])
    func open(_ urls: [URL]) -> [URL]
    func openInTerminal(directory: URL, application: FileActionsTerminalApp) throws
    func existingURLs(from urls: [URL]) -> [URL]
    func isDirectory(_ url: URL) -> Bool
}

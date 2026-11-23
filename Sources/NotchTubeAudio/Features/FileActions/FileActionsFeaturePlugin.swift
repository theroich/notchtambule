//
//  FileActionsFeaturePlugin.swift
//  NotchTubeAudio
//

import Foundation
import Observation
import SwiftUI

/// Built-in module that detects copied file URLs (`ClipboardPayload.files`)
/// and offers quick actions to reveal in Finder, copy POSIX paths, open with
/// the default application, or optionally open the folder in Terminal.
@MainActor
@Observable
final class FileActionsFeaturePlugin: ClipboardFeaturePlugin {
    static let pluginID = "com.notchclip.plugin.file-actions"

    enum PreferenceKey {
        static let terminalApp = "notchtube.file-actions.terminal-app"
        static let confirmManyFiles = "notchtube.file-actions.confirm-many-files"
        static let showFullPaths = "notchtube.file-actions.show-full-paths"
    }

    static let defaultConfirmManyFilesThreshold = 5

    let id: String = FileActionsFeaturePlugin.pluginID
    var displayName: String { L10n.string("plugin.file_actions.name") }
    var summary: String { L10n.string("plugin.file_actions.summary") }
    let iconSystemName: String = "doc.on.folder"
    let priority: FeaturePriority = .normal
    let defaultTriggerBehavior: FeatureTriggerBehavior = .historyActionOnly
    let supportsPrompt: Bool = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let performer: any FileActionPerforming
    @ObservationIgnored private var promptTargetItemID: UUID?

    var terminalApp: FileActionsTerminalApp {
        didSet {
            defaults.set(terminalApp.rawValue, forKey: PreferenceKey.terminalApp)
        }
    }

    var confirmManyFilesThreshold: Int {
        didSet {
            let clamped = max(0, confirmManyFilesThreshold)
            if clamped != confirmManyFilesThreshold {
                confirmManyFilesThreshold = clamped
            }
            defaults.set(confirmManyFilesThreshold, forKey: PreferenceKey.confirmManyFiles)
        }
    }

    var showFullPathsInPrompt: Bool {
        didSet {
            defaults.set(showFullPathsInPrompt, forKey: PreferenceKey.showFullPaths)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        performer: (any FileActionPerforming)? = nil
    ) {
        self.defaults = defaults
        self.performer = performer ?? SystemFileActionPerformer()

        if let rawTerminal = defaults.string(forKey: PreferenceKey.terminalApp),
           let parsedTerminal = FileActionsTerminalApp(rawValue: rawTerminal) {
            self.terminalApp = parsedTerminal
        } else {
            self.terminalApp = .none
        }

        if defaults.object(forKey: PreferenceKey.confirmManyFiles) != nil {
            self.confirmManyFilesThreshold = max(0, defaults.integer(forKey: PreferenceKey.confirmManyFiles))
        } else {
            self.confirmManyFilesThreshold = Self.defaultConfirmManyFilesThreshold
        }

        self.showFullPathsInPrompt = defaults.bool(forKey: PreferenceKey.showFullPaths)
    }

    // MARK: - Detection

    func canHandle(_ item: ClipboardItem) -> Bool {
        guard case .files(let urls) = item.payload else { return false }
        return !Self.normalizedFileURLs(from: urls).isEmpty
    }

    /// Filters non-file URLs and deduplicates standardized file paths while preserving order.
    static func normalizedFileURLs(from urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var result: [URL] = []
        result.reserveCapacity(urls.count)

        for url in urls where url.isFileURL {
            let standardized = url.standardizedFileURL
            if seenPaths.insert(standardized.path).inserted {
                result.append(standardized)
            }
        }
        return result
    }

    // MARK: - Quick Actions

    func quickActions(for item: ClipboardItem, context: FeatureActionContext) -> [FeatureQuickAction] {
        guard case .files(let rawURLs) = item.payload else { return [] }
        let urls = Self.normalizedFileURLs(from: rawURLs)
        guard !urls.isEmpty else { return [] }

        let allDirectories = urls.allSatisfy { performer.isDirectory($0) }
        let openTitle = allDirectories
            ? L10n.string("plugin.file_actions.action.open_in_finder")
            : L10n.string("plugin.file_actions.action.open")

        var actions: [FeatureQuickAction] = [
            FeatureQuickAction(
                id: "\(id).reveal.\(item.id.uuidString)",
                pluginID: id,
                title: L10n.string("plugin.file_actions.action.reveal"),
                iconSystemName: "folder"
            ) { [weak self] in
                self?.revealFiles(urls, context: context)
            },
            FeatureQuickAction(
                id: "\(id).copy-paths.\(item.id.uuidString)",
                pluginID: id,
                title: L10n.string("plugin.file_actions.action.copy_paths"),
                iconSystemName: "doc.on.doc"
            ) { [weak self] in
                self?.copyPaths(urls, context: context)
            },
            FeatureQuickAction(
                id: "\(id).open.\(item.id.uuidString)",
                pluginID: id,
                title: openTitle,
                iconSystemName: "arrow.up.forward.app"
            ) { [weak self] in
                self?.openFiles(urls, for: item, context: context)
            }
        ]

        if terminalApp != .none {
            actions.append(
                FeatureQuickAction(
                    id: "\(id).open-terminal.\(item.id.uuidString)",
                    pluginID: id,
                    title: L10n.string("plugin.file_actions.action.open_terminal"),
                    iconSystemName: "terminal"
                ) { [weak self] in
                    self?.openInTerminal(urls, context: context)
                }
            )
        }

        return actions
    }

    // MARK: - Confirmation Prompt (many files)

    func makePromptView(
        for item: ClipboardItem,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView? {
        guard promptTargetItemID == item.id,
              case .files(let rawURLs) = item.payload else {
            return nil
        }

        let urls = Self.normalizedFileURLs(from: rawURLs)
        guard !urls.isEmpty else { return nil }

        let existing = Set(performer.existingURLs(from: urls))

        return AnyView(
            FileActionsPromptView(
                urls: urls,
                existingURLs: existing,
                showFullPaths: showFullPathsInPrompt,
                onOpenAll: { [weak self] in
                    self?.promptTargetItemID = nil
                    self?.performOpen(urls, context: context)
                    onComplete()
                },
                onRevealInFinder: { [weak self] in
                    self?.promptTargetItemID = nil
                    self?.revealFiles(urls, context: context)
                    onComplete()
                },
                onCopyPaths: { [weak self] in
                    self?.promptTargetItemID = nil
                    self?.copyPaths(urls, context: context)
                    onComplete()
                },
                onCancel: { [weak self] in
                    self?.promptTargetItemID = nil
                    onDismiss()
                }
            )
        )
    }

    // MARK: - Settings View

    func makeSettingsView() -> AnyView? {
        AnyView(FileActionsSettingsView(plugin: self))
    }

    // MARK: - Actions Implementation

    func revealFiles(_ urls: [URL], context: FeatureActionContext) {
        let existing = performer.existingURLs(from: urls)
        guard !existing.isEmpty else {
            context.notifyUser(
                message: L10n.string("plugin.file_actions.notify.no_existing_files"),
                icon: "exclamationmark.triangle"
            )
            return
        }

        performer.reveal(existing)
        let missingCount = urls.count - existing.count
        if missingCount > 0 {
            context.notifyUser(
                message: L10n.format("plugin.file_actions.notify.partial_missing", Int64(missingCount)),
                icon: "exclamationmark.triangle"
            )
        }
    }

    func copyPaths(_ urls: [URL], context: FeatureActionContext) {
        let formatted = FileActions.formatPOSIXPaths(urls)
        context.writeToClipboard(.text(formatted))

        let message: String
        if urls.count == 1 {
            message = L10n.string("plugin.file_actions.notify.paths_copied_one")
        } else {
            message = L10n.format("plugin.file_actions.notify.paths_copied", Int64(urls.count))
        }
        context.notifyUser(message: message, icon: "doc.on.doc")
    }

    func openFiles(_ urls: [URL], for item: ClipboardItem, context: FeatureActionContext) {
        let existing = performer.existingURLs(from: urls)
        guard !existing.isEmpty else {
            context.notifyUser(
                message: L10n.string("plugin.file_actions.notify.no_existing_files"),
                icon: "exclamationmark.triangle"
            )
            return
        }

        if confirmManyFilesThreshold > 0 && existing.count > confirmManyFilesThreshold {
            promptTargetItemID = item.id
            context.presentPluginPrompt(pluginID: id, for: item)
            return
        }

        performOpen(urls, context: context)
    }

    private func performOpen(_ urls: [URL], context: FeatureActionContext) {
        let existing = performer.existingURLs(from: urls)
        guard !existing.isEmpty else {
            context.notifyUser(
                message: L10n.string("plugin.file_actions.notify.no_existing_files"),
                icon: "exclamationmark.triangle"
            )
            return
        }

        let failed = performer.open(existing)
        if !failed.isEmpty {
            context.notifyUser(
                message: L10n.format("plugin.file_actions.notify.open_failed", Int64(failed.count)),
                icon: "exclamationmark.triangle"
            )
            return
        }

        let missingCount = urls.count - existing.count
        if missingCount > 0 {
            context.notifyUser(
                message: L10n.format("plugin.file_actions.notify.partial_missing", Int64(missingCount)),
                icon: "exclamationmark.triangle"
            )
        }
    }

    func openInTerminal(_ urls: [URL], context: FeatureActionContext) {
        guard terminalApp != .none else {
            context.notifyUser(
                message: L10n.format("plugin.file_actions.notify.terminal_unavailable", terminalApp.displayName),
                icon: "exclamationmark.triangle"
            )
            return
        }

        let existing = performer.existingURLs(from: urls)
        guard let firstExisting = existing.first else {
            context.notifyUser(
                message: L10n.string("plugin.file_actions.notify.no_existing_files"),
                icon: "exclamationmark.triangle"
            )
            return
        }

        let targetDirectory = performer.isDirectory(firstExisting)
            ? firstExisting
            : firstExisting.deletingLastPathComponent()

        do {
            try performer.openInTerminal(directory: targetDirectory, application: terminalApp)
        } catch {
            context.notifyUser(
                message: error.localizedDescription,
                icon: "exclamationmark.triangle"
            )
        }
    }
}

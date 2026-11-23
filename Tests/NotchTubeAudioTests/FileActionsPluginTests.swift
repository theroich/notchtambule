//
//  FileActionsPluginTests.swift
//  NotchTubeAudioTests
//

import Foundation
import Testing
@testable import NotchTubeAudio

@MainActor
private final class MockFileActionPerformer: FileActionPerforming {
    var existingPaths: Set<String> = []
    var directoryPaths: Set<String> = []
    var failingOpenPaths: Set<String> = []
    var terminalError: Error?

    private(set) var revealedBatches: [[URL]] = []
    private(set) var openedBatches: [[URL]] = []
    private(set) var terminalCalls: [(directory: URL, application: FileActionsTerminalApp)] = []

    func reveal(_ urls: [URL]) {
        revealedBatches.append(urls)
    }

    func open(_ urls: [URL]) -> [URL] {
        openedBatches.append(urls)
        return urls.filter { failingOpenPaths.contains($0.path) }
    }

    func openInTerminal(directory: URL, application: FileActionsTerminalApp) throws {
        if let terminalError {
            throw terminalError
        }
        terminalCalls.append((directory, application))
    }

    func existingURLs(from urls: [URL]) -> [URL] {
        urls.filter { existingPaths.contains($0.path) }
    }

    func isDirectory(_ url: URL) -> Bool {
        directoryPaths.contains(url.path)
    }
}

@MainActor
struct FileActionsPluginTests {
    private func makeIsolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "notchtube.file-actions.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeFilesItem(_ urls: [URL]) -> ClipboardItem {
        ClipboardItem(changeCount: 1, payload: .files(urls))
    }

    // MARK: - 1. Detection

    @Test func canHandleAcceptsFilesAndRejectsOtherPayloadsAndEmptyArrays() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let plugin = FileActionsFeaturePlugin(defaults: defaults, performer: MockFileActionPerformer())

        #expect(plugin.id == "com.notchclip.plugin.file-actions")
        #expect(plugin.priority == .normal)
        #expect(plugin.defaultTriggerBehavior == .historyActionOnly)
        #expect(plugin.supportsPrompt == false)

        let fileItem = makeFilesItem([URL(fileURLWithPath: "/tmp/documento.pdf")])
        let emptyFilesItem = makeFilesItem([])
        let remoteURLItem = makeFilesItem([try #require(URL(string: "https://example.com/file.pdf"))])
        let textItem = ClipboardItem(changeCount: 2, payload: .text("/tmp/documento.pdf"))
        let urlItem = ClipboardItem(changeCount: 3, payload: .url(try #require(URL(string: "https://apple.com")), rawText: "https://apple.com"))
        let imageItem = ClipboardItem(changeCount: 4, payload: .image(ImagePayload(size: CGSize(width: 10, height: 10), tiffOrPngData: Data([1, 2, 3]))))

        #expect(plugin.canHandle(fileItem) == true)
        #expect(plugin.canHandle(emptyFilesItem) == false)
        #expect(plugin.canHandle(remoteURLItem) == false)
        #expect(plugin.canHandle(textItem) == false)
        #expect(plugin.canHandle(urlItem) == false)
        #expect(plugin.canHandle(imageItem) == false)
    }

    @Test func normalizedFileURLsDeduplicatesAndPreservesOrder() throws {
        let remote = try #require(URL(string: "https://example.com/a.txt"))
        let first = URL(fileURLWithPath: "/tmp/a.txt")
        let duplicateWithDot = URL(fileURLWithPath: "/tmp/./a.txt")
        let second = URL(fileURLWithPath: "/tmp/carpeta con espacios/canción 🎵.mp3")

        let normalized = FileActionsFeaturePlugin.normalizedFileURLs(from: [remote, first, duplicateWithDot, second])
        #expect(normalized.map(\.path) == [
            first.standardizedFileURL.path,
            second.standardizedFileURL.path
        ])
    }

    // MARK: - 2. Quick Actions & Copy Paths

    @Test func quickActionsReturnExpectedActionsAndCopyPOSIXPathsInOrder() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let performer = MockFileActionPerformer()
        let plugin = FileActionsFeaturePlugin(defaults: defaults, performer: performer)
        let context = FeatureActionContext.noop

        let singleURL = URL(fileURLWithPath: "/tmp/Mi Archivo (Español) ñoño.txt")
        let singleItem = makeFilesItem([singleURL])
        let singleActions = plugin.quickActions(for: singleItem, context: context)
        #expect(singleActions.map(\.title) == ["Revelar en Finder", "Copiar rutas", "Abrir"])

        // Single path copied without trailing newline
        singleActions[1].handler()
        #expect(context.writtenPayloads.last == .text("/tmp/Mi Archivo (Español) ñoño.txt"))
        #expect(context.lastNotification?.message == "Ruta copiada")
        #expect(context.lastNotification?.icon == "doc.on.doc")

        // Multiple paths copied in order separated by newline, deduplicated
        let urlA = URL(fileURLWithPath: "/tmp/uno.txt")
        let urlB = URL(fileURLWithPath: "/tmp/dos espacios/áéíóú.pdf")
        let multiItem = makeFilesItem([urlA, URL(fileURLWithPath: "/tmp/./uno.txt"), urlB])
        let multiActions = plugin.quickActions(for: multiItem, context: context)
        multiActions[1].handler()

        #expect(context.writtenPayloads.last == .text("/tmp/uno.txt\n/tmp/dos espacios/áéíóú.pdf"))
        #expect(context.lastNotification?.message == "2 rutas copiadas")
    }

    // MARK: - 3. Reveal & Open

    @Test func revealInFinderFiltersExistingAndWarnsWhenMissing() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let performer = MockFileActionPerformer()
        let existingURL = URL(fileURLWithPath: "/tmp/exists.txt")
        let missingURL = URL(fileURLWithPath: "/tmp/missing.txt")
        performer.existingPaths = [existingURL.path]

        let plugin = FileActionsFeaturePlugin(defaults: defaults, performer: performer)
        let context = FeatureActionContext.noop

        // Partial missing
        let partialItem = makeFilesItem([existingURL, missingURL])
        let revealPartial = try #require(plugin.quickActions(for: partialItem, context: context).first)
        revealPartial.handler()

        #expect(performer.revealedBatches == [[existingURL.standardizedFileURL]])
        #expect(context.lastNotification?.icon == "exclamationmark.triangle")
        #expect(context.lastNotification?.message == "1 archivo(s) ya no existen")

        // All missing
        let allMissingItem = makeFilesItem([missingURL])
        let revealMissing = try #require(plugin.quickActions(for: allMissingItem, context: context).first)
        revealMissing.handler()

        #expect(performer.revealedBatches.count == 1)
        #expect(context.lastNotification?.message == "Ninguno de los archivos existe ya")
    }

    @Test func openFilesCallsPerformerAndHandlesFailuresAndManyFilesPrompt() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let performer = MockFileActionPerformer()
        let file1 = URL(fileURLWithPath: "/tmp/f1.txt")
        let file2 = URL(fileURLWithPath: "/tmp/f2.txt")
        performer.existingPaths = [file1.path, file2.path]
        performer.failingOpenPaths = [file2.path]

        let plugin = FileActionsFeaturePlugin(defaults: defaults, performer: performer)
        let context = FeatureActionContext.noop

        let item = makeFilesItem([file1, file2])
        let actions = plugin.quickActions(for: item, context: context)
        actions[2].handler()

        #expect(performer.openedBatches == [[file1.standardizedFileURL, file2.standardizedFileURL]])
        #expect(context.lastNotification?.message == "No se pudieron abrir 1 archivo(s)")

        // Many files confirmation prompt
        plugin.confirmManyFilesThreshold = 1
        let manyItem = makeFilesItem([file1, file2])
        let manyActions = plugin.quickActions(for: manyItem, context: context)
        manyActions[2].handler()

        #expect(context.lastPresentedPrompt?.pluginID == FileActionsFeaturePlugin.pluginID)
        #expect(context.lastPresentedPrompt?.item.id == manyItem.id)
        #expect(plugin.makePromptView(for: manyItem, context: context, onComplete: {}, onDismiss: {}) != nil)
    }

    @Test func directoryAdaptsOpenTitleToOpenInFinder() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let performer = MockFileActionPerformer()
        let folderURL = URL(fileURLWithPath: "/tmp/MyFolder")
        performer.existingPaths = [folderURL.path]
        performer.directoryPaths = [folderURL.path]

        let plugin = FileActionsFeaturePlugin(defaults: defaults, performer: performer)
        let actions = plugin.quickActions(for: makeFilesItem([folderURL]), context: .noop)
        #expect(actions[2].title == "Abrir en Finder")
    }

    // MARK: - 4. Open in Terminal & Preferences

    @Test func openInTerminalUsesFolderOrParentAndReportsLocalizedErrors() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let performer = MockFileActionPerformer()
        let fileURL = URL(fileURLWithPath: "/tmp/sub/note.txt")
        let folderURL = URL(fileURLWithPath: "/tmp/sub")
        performer.existingPaths = [fileURL.path, folderURL.path]
        performer.directoryPaths = [folderURL.path]

        let plugin = FileActionsFeaturePlugin(defaults: defaults, performer: performer)
        plugin.terminalApp = .iterm
        #expect(defaults.string(forKey: FileActionsFeaturePlugin.PreferenceKey.terminalApp) == "iterm")

        let context = FeatureActionContext.noop
        let actions = plugin.quickActions(for: makeFilesItem([fileURL]), context: context)
        #expect(actions.count == 4)
        #expect(actions[3].title == "Abrir en Terminal")

        actions[3].handler()
        #expect(performer.terminalCalls.count == 1)
        #expect(performer.terminalCalls.first?.directory.path == folderURL.standardizedFileURL.path)
        #expect(performer.terminalCalls.first?.application == .iterm)

        // Terminal error is localized
        performer.terminalError = FileActionError.terminalUnavailable("iTerm2")
        actions[3].handler()
        #expect(context.lastNotification?.message == "iTerm2 no está disponible")
        #expect(context.lastNotification?.icon == "exclamationmark.triangle")
    }

    // MARK: - 5. Registry Integration

    @Test func featureRegistryMatchesFileActionsAndRespectsDisablement() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        let plugin = FileActionsFeaturePlugin(defaults: defaults, performer: MockFileActionPerformer())
        let registry = FeatureRegistry(settings: settings, plugins: [plugin])

        let item = makeFilesItem([URL(fileURLWithPath: "/tmp/sample.txt")])
        #expect(registry.matchingPlugins(for: item).map(\.id) == [FileActionsFeaturePlugin.pluginID])
        #expect(registry.primaryPromptPlugin(for: item) == nil)
        #expect(registry.quickActions(for: item, context: .noop).count == 3)

        registry.setPluginEnabled(FileActionsFeaturePlugin.pluginID, false)
        #expect(registry.matchingPlugins(for: item).isEmpty)
        #expect(registry.quickActions(for: item, context: .noop).isEmpty)
    }
}

//
//  AutoPasteServiceTests.swift
//  NotchTubeAudioTests
//

import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI
import Testing
@testable import NotchTubeAudio

@MainActor
private final class MockTargetApp: AutoPasteTargetApplication {
    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t
    var isTerminated: Bool
    var isActive: Bool
    var activateResult: Bool = true
    var activatesImmediately: Bool = true
    var activatesAfterCalls: Int = 1
    var onActivate: (() -> Void)?

    private(set) var activateCallCount = 0

    init(
        bundleIdentifier: String? = "com.apple.TextEdit",
        localizedName: String? = "TextEdit",
        processIdentifier: pid_t = 4242,
        isTerminated: Bool = false,
        isActive: Bool = false
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
        self.isTerminated = isTerminated
        self.isActive = isActive
    }

    @discardableResult
    func activate() -> Bool {
        activateCallCount += 1
        onActivate?()
        if activatesImmediately && activateCallCount >= activatesAfterCalls {
            isActive = true
        }
        return activateResult
    }
}

@MainActor
private final class MockAutoPasteEnvironment: AutoPasteSystemEnvironment {
    var trusted: Bool = true
    var secureInputEnabled: Bool = false
    var frontmostApp: (any AutoPasteTargetApplication)?
    var postKeystrokesSucceeds: Bool = true
    var openSettingsSucceeds: Bool = true

    private(set) var trustChecks: [Bool] = []
    private(set) var openSettingsCallCount = 0
    private(set) var postCommandVCallCount = 0
    private(set) var sleepDurationsMs: [Int] = []

    func isAccessibilityTrusted(promptIfNeeded: Bool) -> Bool {
        trustChecks.append(promptIfNeeded)
        return trusted
    }

    @discardableResult
    func openAccessibilitySystemSettings() -> Bool {
        openSettingsCallCount += 1
        return openSettingsSucceeds
    }

    func isSecureEventInputEnabled() -> Bool {
        secureInputEnabled
    }

    func currentFrontmostApplication() -> (any AutoPasteTargetApplication)? {
        frontmostApp
    }

    func postCommandVKeystrokes() -> Bool {
        postCommandVCallCount += 1
        return postKeystrokesSucceeds
    }

    func sleep(milliseconds: Int) async {
        sleepDurationsMs.append(milliseconds)
    }
}

@MainActor
private final class AutoPasteMockPresenter: NotchPresenting {
    private(set) var presentPromptCount = 0
    private(set) var presentPanelCalls: [TimeInterval?] = []
    private(set) var hideCount = 0
    private(set) var hideImmediatelyForAutoPasteCount = 0
    var onHideImmediatelyForAutoPaste: (() -> Void)?

    func presentPrompt() {
        presentPromptCount += 1
    }

    func presentPanel(autoHideAfter seconds: TimeInterval?) {
        presentPanelCalls.append(seconds)
    }

    func hide() {
        hideCount += 1
    }

    func hideImmediatelyForAutoPaste() async {
        hideImmediatelyForAutoPasteCount += 1
        hideCount += 1
        onHideImmediatelyForAutoPaste?()
    }
}

@MainActor
struct AutoPasteServiceTests {
    private struct Harness {
        let appState: AppState
        let presenter: AutoPasteMockPresenter
        let autoPasteService: AutoPasteService
        let environment: MockAutoPasteEnvironment
        let historyStore: ClipboardHistoryStore
        let monitor: ClipboardMonitor
        let pasteboard: MockPasteboard
        let settings: SettingsManager
        let defaults: UserDefaults
        let suiteName: String
        let tempDir: URL

        @MainActor
        func cleanup() {
            monitor.stop()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeHarness(
        trusted: Bool = true,
        autoPasteOnSelect: Bool = true
    ) throws -> Harness {
        let suiteName = "notchtube.autopaste.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsManager(defaults: defaults)
        settings.persistClipboardHistory = false
        settings.autoPasteOnSelect = autoPasteOnSelect

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTubeAutoPasteTests-\(UUID().uuidString)", isDirectory: true)
        let storage = ClipboardStorage(baseDirectory: tempDir, debounceInterval: 0)
        let pasteboard = MockPasteboard()
        let monitor = ClipboardMonitor(
            settings: settings,
            pasteboard: pasteboard
        )
        let historyStore = ClipboardHistoryStore(
            settings: settings,
            storage: storage,
            pasteboard: pasteboard,
            clipboardMonitor: monitor
        )
        let featureRegistry = FeatureRegistry(settings: settings, plugins: [])

        let environment = MockAutoPasteEnvironment()
        environment.trusted = trusted
        let autoPasteService = AutoPasteService(
            environment: environment,
            ownBundleIdentifier: "com.notchtube.audio",
            ownProcessIdentifier: 9999
        )
        autoPasteService.postActivationDelayMilliseconds = 10
        autoPasteService.focusPollIntervalMilliseconds = 5

        let appState = AppState(
            settings: settings,
            historyStore: historyStore,
            featureRegistry: featureRegistry,
            autoPasteService: autoPasteService
        )
        let presenter = AutoPasteMockPresenter()
        appState.presenter = presenter

        monitor.onCapture = { [weak appState] (item: ClipboardItem) in
            appState?.handleCapturedItem(item)
        }

        return Harness(
            appState: appState,
            presenter: presenter,
            autoPasteService: autoPasteService,
            environment: environment,
            historyStore: historyStore,
            monitor: monitor,
            pasteboard: pasteboard,
            settings: settings,
            defaults: defaults,
            suiteName: suiteName,
            tempDir: tempDir
        )
    }

    @Test func ansiVKeyCodeAndSettingsPersistence() throws {
        #expect(AutoPasteService.ansiVVirtualKeyCode == CGKeyCode(kVK_ANSI_V))
        #expect(AutoPasteService.ansiVVirtualKeyCode == 0x09)

        let suiteName = "notchtube.autopaste.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        #expect(settings.autoPasteOnSelect == true)

        settings.autoPasteOnSelect = false
        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.autoPasteOnSelect == false)
    }

    @Test func remembersExternalFrontmostAppAndIgnoresOwnProcess() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        let safariApp = MockTargetApp(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            processIdentifier: 1001
        )
        harness.environment.frontmostApp = safariApp

        let remembered = harness.autoPasteService.rememberFrontmostApp()
        #expect(remembered?.bundleIdentifier == "com.apple.Safari")
        #expect(harness.autoPasteService.rememberedApp?.processIdentifier == 1001)

        // If our own process becomes frontmost (e.g. Settings window), keep Safari remembered
        let ownApp = MockTargetApp(
            bundleIdentifier: "com.notchtube.audio",
            localizedName: "NotchTubeAudio",
            processIdentifier: 9999
        )
        harness.environment.frontmostApp = ownApp

        let stillSafari = harness.autoPasteService.rememberFrontmostApp()
        #expect(stillSafari?.bundleIdentifier == "com.apple.Safari")
    }

    @Test func autoPasteWithAccessibilityPermissionCopiesCollapsesNotchActivatesAppAndPostsCommandV() async throws {
        let harness = try makeHarness(trusted: true, autoPasteOnSelect: true)
        defer { harness.cleanup() }

        let targetApp = MockTargetApp(
            bundleIdentifier: "com.apple.dt.Xcode",
            localizedName: "Xcode",
            processIdentifier: 2048,
            isActive: false
        )
        harness.environment.frontmostApp = targetApp

        let item1 = ClipboardItem(changeCount: 1, payload: .text("Primer texto"))
        let item2 = ClipboardItem(changeCount: 2, payload: .text("Segundo texto"))
        harness.historyStore.record(item1)
        harness.historyStore.record(item2)

        // Hovering over the notch captures the frontmost app (Xcode) and opens the panel
        harness.appState.showPanelFromHover()
        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))
        #expect(harness.autoPasteService.rememberedApp?.bundleIdentifier == "com.apple.dt.Xcode")

        // Click on item1 to auto-paste
        let result = await harness.appState.autoPaste(item: item1)
        #expect(result == .pasted)
        #expect(harness.appState.lastPasteResult == .pasted)

        // 1. Item was written to pasteboard and promoted to top of history without duplicating
        #expect(harness.pasteboard.string(forType: .string) == "Primer texto")
        #expect(harness.historyStore.items.count == 2)
        #expect(harness.historyStore.items.first?.id == item1.id)

        // 2. Subsequent monitor poll does NOT create a duplicate history entry
        harness.monitor.poll()
        #expect(harness.historyStore.items.count == 2)

        // 3. Notch collapsed before pasting
        #expect(harness.appState.notchMode == .idle)
        #expect(harness.presenter.hideCount == 1)

        // 4. Target app was activated and ⌘V was posted once
        #expect(targetApp.activateCallCount >= 1)
        #expect(targetApp.isActive == true)
        #expect(harness.environment.postCommandVCallCount == 1)
    }

    @Test func autoPasteRetriesFocusRestorationUntilTargetAppBecomesActive() async throws {
        let harness = try makeHarness(trusted: true, autoPasteOnSelect: true)
        defer { harness.cleanup() }

        let slowFullscreenApp = MockTargetApp(
            bundleIdentifier: "com.apple.Terminal",
            localizedName: "Terminal",
            processIdentifier: 3333,
            isActive: false
        )
        // Requires 3 activate() calls before macOS reports it active (e.g. fullscreen space transition)
        slowFullscreenApp.activatesAfterCalls = 3
        harness.environment.frontmostApp = slowFullscreenApp

        harness.appState.showPanelFromHover()
        let item = ClipboardItem(changeCount: 1, payload: .text("echo 'hola'"))
        harness.historyStore.record(item)

        let result = await harness.appState.autoPaste(item: item)
        #expect(result == .pasted)
        #expect(slowFullscreenApp.activateCallCount == 3)
        #expect(slowFullscreenApp.isActive == true)
        #expect(harness.environment.postCommandVCallCount == 1)
    }

    @Test func degradesToCopyOnlyWithoutAccessibilityPermissionAndNotifiesUser() async throws {
        let harness = try makeHarness(trusted: false, autoPasteOnSelect: true)
        defer { harness.cleanup() }

        let targetApp = MockTargetApp(bundleIdentifier: "com.apple.Notes", localizedName: "Notes")
        harness.environment.frontmostApp = targetApp
        harness.appState.showPanelFromHover()

        let item = ClipboardItem(changeCount: 1, payload: .text("Nota sin permiso"))
        harness.historyStore.record(item)

        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let result = await harness.appState.autoPaste(item: item)
        #expect(result == .copiedOnly(reason: .accessibilityPermissionMissing))
        #expect(harness.pasteboard.string(forType: .string) == "Nota sin permiso")
        #expect(harness.environment.postCommandVCallCount == 0)
        // Notch stays open so the user sees the notification banner and "Copiado" badge
        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))
        #expect(harness.appState.activeNotification?.message.contains("Accesibilidad") == true)

        // Opening Accessibility settings from AutoPasteService prompts and opens System Settings URL
        #expect(harness.autoPasteService.openAccessibilitySettings(promptIfNeeded: true) == true)
        #expect(harness.environment.openSettingsCallCount == 1)
        #expect(harness.environment.trustChecks.contains(true))
    }

    @Test func degradesToCopyOnlyWhenSecureEventInputIsActive() async throws {
        let harness = try makeHarness(trusted: true, autoPasteOnSelect: true)
        defer { harness.cleanup() }

        let targetApp = MockTargetApp(bundleIdentifier: "com.1password.1password", localizedName: "1Password")
        harness.environment.frontmostApp = targetApp
        harness.environment.secureInputEnabled = true
        harness.appState.showPanelFromHover()

        let item = ClipboardItem(changeCount: 1, payload: .text("Texto en campo seguro"))
        harness.historyStore.record(item)

        let result = await harness.appState.autoPaste(item: item)
        #expect(result == .copiedOnly(reason: .secureEventInputActive))
        #expect(harness.pasteboard.string(forType: .string) == "Texto en campo seguro")
        #expect(harness.environment.postCommandVCallCount == 0)
    }

    @Test func degradesToCopyOnlyWhenSettingDisabledOrOptionModifierForced() async throws {
        let harness = try makeHarness(trusted: true, autoPasteOnSelect: true)
        defer { harness.cleanup() }

        let targetApp = MockTargetApp(bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
        harness.environment.frontmostApp = targetApp
        harness.appState.showPanelFromHover()

        let item = ClipboardItem(changeCount: 1, payload: .text("Texto con modificador"))
        harness.historyStore.record(item)

        // 1. Force copy-only via ⌥+Click (forceCopyOnly: true)
        let modifierResult = await harness.appState.autoPaste(item: item, forceCopyOnly: true)
        #expect(modifierResult == .copiedOnly(reason: .forcedCopyModifier))
        #expect(harness.pasteboard.string(forType: .string) == "Texto con modificador")
        #expect(harness.environment.postCommandVCallCount == 0)
        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))

        // 2. Disable setting "Pegar al hacer click"
        harness.settings.autoPasteOnSelect = false
        let disabledResult = await harness.appState.autoPaste(item: item, forceCopyOnly: false)
        #expect(disabledResult == .copiedOnly(reason: .disabledInSettings))
        #expect(harness.environment.postCommandVCallCount == 0)
        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))
    }

    @Test func nonTextPayloadsImagesAndFilesCopyAndSynthesizePasteWithFallback() async throws {
        let harness = try makeHarness(trusted: true, autoPasteOnSelect: true)
        defer { harness.cleanup() }

        let finderApp = MockTargetApp(bundleIdentifier: "com.apple.finder", localizedName: "Finder")
        harness.environment.frontmostApp = finderApp
        harness.appState.showPanelFromHover()

        let fileURL = URL(fileURLWithPath: "/tmp/archivo-prueba.txt")
        let fileItem = ClipboardItem(changeCount: 1, payload: .files([fileURL]))
        harness.historyStore.record(fileItem)

        let result = await harness.appState.autoPaste(item: fileItem)
        #expect(result == .pasted)
        #expect(harness.pasteboard.readFileURLs() == [fileURL])
        #expect(harness.environment.postCommandVCallCount == 1)
    }

    @Test func rowViewAndSettingsViewReflectAutoPasteAndAccessibilityState() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let harness = try makeHarness(trusted: false, autoPasteOnSelect: true)
        defer { harness.cleanup() }

        let item = ClipboardItem(changeCount: 1, payload: .text("Fila UI"))
        let rowCopyOnly = ClipboardItemRowView(
            item: item,
            quickActions: [],
            matchedPlugins: [],
            isCopiedFeedbackActive: true,
            feedbackState: .copied,
            isAutoPasteEnabled: false,
            onCopy: {},
            onTogglePin: {},
            onRemove: {}
        )
        #expect(rowCopyOnly.rowHelpTooltip == "Clic para copiar al portapapeles")
        #expect(ClipboardItemClickFeedback.copied.badgeTitle == "Copiado")
        #expect(ClipboardItemClickFeedback.pasted.badgeTitle == "Pegado")

        let rowAutoPaste = ClipboardItemRowView(
            item: item,
            quickActions: [],
            matchedPlugins: [],
            isCopiedFeedbackActive: true,
            feedbackState: .pasted,
            isAutoPasteEnabled: true,
            onCopy: {},
            onTogglePin: {},
            onRemove: {}
        )
        #expect(rowAutoPaste.rowHelpTooltip.contains("Clic para pegar"))

        let settingsView = SettingsView(
            settings: harness.settings,
            featureRegistry: harness.appState.featureRegistry,
            historyStore: harness.historyStore,
            autoPasteService: harness.autoPasteService
        )
        let hosting = NSHostingView(rootView: settingsView)
        hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.width == 600)
    }

    @Test func autoPasteHidesNotchImmediatelyAndReactivatesAlreadyActiveTargetApp() async throws {
        let harness = try makeHarness(trusted: true, autoPasteOnSelect: true)
        defer { harness.cleanup() }

        var events: [String] = []
        // Simulate a non-activating panel scenario where the underlying app still reports isActive == true
        let activeTargetApp = MockTargetApp(
            bundleIdentifier: "com.apple.Notes",
            localizedName: "Notes",
            processIdentifier: 5150,
            isActive: true
        )
        activeTargetApp.onActivate = {
            events.append("activate")
        }
        harness.presenter.onHideImmediatelyForAutoPaste = {
            events.append("hideImmediate")
        }
        harness.environment.frontmostApp = activeTargetApp

        let item = ClipboardItem(changeCount: 1, payload: .text("Texto desde panel no activador"))
        harness.historyStore.record(item)
        harness.appState.showPanelFromHover()

        let result = await harness.appState.autoPaste(item: item)
        #expect(result == .pasted)
        #expect(harness.presenter.hideImmediatelyForAutoPasteCount == 1)
        #expect(activeTargetApp.activateCallCount >= 1)
        #expect(events.first == "hideImmediate")
        #expect(events.contains("activate"))
        #expect(harness.environment.postCommandVCallCount == 1)
    }

    @Test func recordActivatedApplicationTracksExternalAppsAndIgnoresSelf() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        let notes = MockTargetApp(
            bundleIdentifier: "com.apple.Notes",
            localizedName: "Notes",
            processIdentifier: 6001
        )
        harness.autoPasteService.recordActivatedApplication(notes)
        #expect(harness.autoPasteService.rememberedApp?.bundleIdentifier == "com.apple.Notes")

        let ownApp = MockTargetApp(
            bundleIdentifier: "com.notchtube.audio",
            localizedName: "NotchTubeAudio",
            processIdentifier: 9999
        )
        harness.autoPasteService.recordActivatedApplication(ownApp)
        #expect(harness.autoPasteService.rememberedApp?.bundleIdentifier == "com.apple.Notes")
    }
}

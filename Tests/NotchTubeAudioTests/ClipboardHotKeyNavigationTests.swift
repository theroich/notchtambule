//
//  ClipboardHotKeyNavigationTests.swift
//  NotchTubeAudioTests
//
//  Created for Issue #19.
//

import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI
import Testing
@testable import NotchTubeAudio

// MARK: - Mocks

@MainActor
private final class FakeHotKeyRegistrar: GlobalHotKeyRegistering {
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var registeredHotKeys: [HotKey] = []
    private var triggerHandler: (@MainActor () -> Void)?

    var errorToThrow: GlobalHotKeyError?

    func register(hotKey: HotKey, onTrigger: @escaping @MainActor () -> Void) throws {
        registerCallCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
        registeredHotKeys.append(hotKey)
        triggerHandler = onTrigger
    }

    func unregister() {
        unregisterCallCount += 1
        triggerHandler = nil
    }

    func simulateTrigger() {
        triggerHandler?()
    }
}

@MainActor
private final class HotKeyMockPresenter: NotchPresenting {
    private(set) var presentPromptCount = 0
    private(set) var presentPanelCalls: [TimeInterval?] = []
    private(set) var hideCount = 0
    private(set) var hideImmediatelyForAutoPasteCount = 0
    private(set) var focusNotchForKeyboardInputCount = 0

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
    }

    func focusNotchForKeyboardInput() {
        focusNotchForKeyboardInputCount += 1
    }
}

@MainActor
private final class HotKeyMockTargetApp: AutoPasteTargetApplication {
    let bundleIdentifier: String? = "com.apple.Notes"
    let localizedName: String? = "Notes"
    let processIdentifier: pid_t = 9001
    var isTerminated: Bool = false
    var isActive: Bool = false

    @discardableResult
    func activate() -> Bool {
        isActive = true
        return true
    }
}

@MainActor
private final class HotKeyMockAutoPasteEnv: AutoPasteSystemEnvironment {
    var trusted = true
    var secureInput = false
    var frontmostApp: (any AutoPasteTargetApplication)? = HotKeyMockTargetApp()
    var postCommandVCount = 0
    var suspendDuringPost = false

    func isAccessibilityTrusted(promptIfNeeded: Bool) -> Bool {
        trusted
    }

    @discardableResult
    func openAccessibilitySystemSettings() -> Bool {
        true
    }

    func isSecureEventInputEnabled() -> Bool {
        secureInput
    }

    func currentFrontmostApplication() -> (any AutoPasteTargetApplication)? {
        frontmostApp
    }

    func postCommandVKeystrokes() -> Bool {
        postCommandVCount += 1
        return true
    }

    func sleep(milliseconds: Int) async {
        if suspendDuringPost {
            await Task.yield()
        }
    }
}

@MainActor
private final class HotKeyPromptTestPlugin: ClipboardFeaturePlugin {
    let id = "com.notchclip.test.prompt"
    let displayName = "Prompt Test"
    let summary = "Test"
    let iconSystemName = "bolt.fill"
    let priority: FeaturePriority = .high
    let defaultTriggerBehavior: FeatureTriggerBehavior = .automaticPrompt
    let hasActivityPanel = false
    var activeTasksCount = 0

    func start() {}
    func shutdown() {}

    func canHandle(_ item: ClipboardItem) -> Bool {
        true
    }

    func makePromptView(
        for item: ClipboardItem,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView? {
        AnyView(EmptyView())
    }

    func makeActivityPanelView(context: FeatureActionContext) -> AnyView? {
        nil
    }
}

// MARK: - Tests

@MainActor
struct ClipboardHotKeyNavigationTests {
    private struct Harness {
        let appState: AppState
        let presenter: HotKeyMockPresenter
        let historyStore: ClipboardHistoryStore
        let pasteboard: MockPasteboard
        let autoPasteEnv: HotKeyMockAutoPasteEnv
        let settings: SettingsManager
        let defaults: UserDefaults
        let suiteName: String
        let tempDir: URL

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeHarness(plugins: [any ClipboardFeaturePlugin] = []) throws -> Harness {
        let suiteName = "notchtube.hotkey.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsManager(defaults: defaults)
        settings.persistClipboardHistory = false
        settings.autoPasteOnSelect = true

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTubeHotKeyTests-\(UUID().uuidString)", isDirectory: true)
        let storage = ClipboardStorage(baseDirectory: tempDir, debounceInterval: 0)
        let pasteboard = MockPasteboard()
        let historyStore = ClipboardHistoryStore(
            settings: settings,
            storage: storage,
            pasteboard: pasteboard
        )
        let featureRegistry = FeatureRegistry(settings: settings, plugins: plugins)
        let autoPasteEnv = HotKeyMockAutoPasteEnv()
        let autoPasteService = AutoPasteService(
            environment: autoPasteEnv,
            ownBundleIdentifier: "com.notchtube.test",
            ownProcessIdentifier: 1234
        )
        autoPasteService.postActivationDelayMilliseconds = 0
        autoPasteService.focusPollIntervalMilliseconds = 0

        let appState = AppState(
            settings: settings,
            historyStore: historyStore,
            featureRegistry: featureRegistry,
            autoPasteService: autoPasteService
        )
        let presenter = HotKeyMockPresenter()
        appState.presenter = presenter

        return Harness(
            appState: appState,
            presenter: presenter,
            historyStore: historyStore,
            pasteboard: pasteboard,
            autoPasteEnv: autoPasteEnv,
            settings: settings,
            defaults: defaults,
            suiteName: suiteName,
            tempDir: tempDir
        )
    }

    private func recordItems(_ texts: [String], in store: ClipboardHistoryStore) {
        for (index, text) in texts.enumerated() {
            store.record(
                ClipboardItem(
                    capturedAt: Date().addingTimeInterval(TimeInterval(index)),
                    changeCount: index + 1,
                    payload: .text(text)
                )
            )
        }
    }

    // MARK: - GlobalHotKeyService

    @Test func globalHotKeyServiceRegistersOnceAndStopsCleanly() throws {
        let registrar = FakeHotKeyRegistrar()
        let service = GlobalHotKeyService(registrar: registrar)

        var triggerCount = 0
        service.onHotKey = { triggerCount += 1 }

        try service.start()
        try service.start() // idempotent

        #expect(registrar.registerCallCount == 1)
        #expect(registrar.registeredHotKeys == [.clipboardDefault])
        #expect(service.isRegistered)
        #expect(service.status == .active)

        registrar.simulateTrigger()
        #expect(triggerCount == 1)

        service.stop()
        #expect(registrar.unregisterCallCount == 1)
        #expect(!service.isRegistered)
        #expect(service.status == .inactive)

        // Calling stop again is a no-op
        service.stop()
        #expect(registrar.unregisterCallCount == 1)
    }

    @Test func globalHotKeyServiceHandlesConflictWithoutCrashing() {
        let registrar = FakeHotKeyRegistrar()
        registrar.errorToThrow = .alreadyInUse
        let service = GlobalHotKeyService(registrar: registrar)

        #expect(throws: GlobalHotKeyError.alreadyInUse) {
            try service.start()
        }
        #expect(!service.isRegistered)
        #expect(service.status == .conflict)
    }

    // MARK: - AppState Open & Selection

    @Test func openClipboardFromHotKeySelectsFirstItemAndFocusesPanel() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        recordItems(["first", "second", "third"], in: harness.historyStore)
        harness.appState.activeTab = .pluginActivity(pluginID: "com.notchtube.youtube")

        harness.appState.openClipboardFromHotKey()

        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))
        #expect(harness.appState.activeTab == .clipboardHistory)
        #expect(harness.appState.isKeyboardNavigationActive)
        #expect(harness.appState.selectedClipboardItem?.payload.stringValue == "third")
        #expect(harness.presenter.presentPanelCalls == [nil])
        #expect(harness.presenter.focusNotchForKeyboardInputCount == 1)
        #expect(harness.appState.autoPasteService.rememberedApp != nil)
    }

    @Test func openClipboardFromHotKeyCancelsActivePrompt() throws {
        let promptPlugin = HotKeyPromptTestPlugin()
        let harness = try makeHarness(plugins: [promptPlugin])
        defer { harness.cleanup() }

        harness.appState.handleCapturedItem(ClipboardItem(changeCount: 1, payload: .text("hello")))
        #expect(harness.appState.notchMode.isPrompting)

        harness.appState.openClipboardFromHotKey()

        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))
        #expect(harness.appState.selectedClipboardItem?.payload.stringValue == "hello")
        #expect(harness.presenter.focusNotchForKeyboardInputCount == 1)
    }

    @Test func moveClipboardSelectionDoesNotWrapAtBoundaries() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        recordItems(["one", "two", "three"], in: harness.historyStore)
        harness.appState.openClipboardFromHotKey()
        // filteredItems order: ["three", "two", "one"]
        #expect(harness.appState.selectedClipboardItem?.payload.stringValue == "three")

        // Already at first item -> .up stays on first
        harness.appState.moveClipboardSelection(.up)
        #expect(harness.appState.selectedClipboardItem?.payload.stringValue == "three")

        harness.appState.moveClipboardSelection(.down)
        #expect(harness.appState.selectedClipboardItem?.payload.stringValue == "two")

        harness.appState.moveClipboardSelection(.down)
        #expect(harness.appState.selectedClipboardItem?.payload.stringValue == "one")

        // Already at last item -> .down stays on last
        harness.appState.moveClipboardSelection(.down)
        #expect(harness.appState.selectedClipboardItem?.payload.stringValue == "one")

        harness.appState.moveClipboardSelection(.up)
        #expect(harness.appState.selectedClipboardItem?.payload.stringValue == "two")
    }

    @Test func selectionReconcilesWithSearchAndFilterChanges() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        recordItems(["alpha", "beta", "https://example.com"], in: harness.historyStore)
        harness.appState.openClipboardFromHotKey()
        harness.appState.moveClipboardSelection(.down)
        #expect(harness.appState.selectedClipboardItem?.payload.stringValue == "beta")

        // Search excludes "beta"
        harness.historyStore.searchQuery = "alpha"
        harness.appState.reconcileClipboardSelection()
        #expect(harness.appState.selectedClipboardItem?.payload.stringValue == "alpha")

        // Search with no results -> nil
        harness.historyStore.searchQuery = "nonexistent"
        harness.appState.reconcileClipboardSelection()
        #expect(harness.appState.selectedClipboardItemID == nil)

        // Clearing search selects first visible item again because keyboard navigation is active
        harness.historyStore.searchQuery = ""
        harness.appState.reconcileClipboardSelection()
        #expect(harness.appState.selectedClipboardItem?.payload.stringValue == "https://example.com")
    }

    @Test func confirmClipboardSelectionPastesSelectedItemAndClearsSelection() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        recordItems(["first", "second"], in: harness.historyStore)
        harness.appState.openClipboardFromHotKey()
        harness.appState.moveClipboardSelection(.down)
        #expect(harness.appState.selectedClipboardItem?.payload.stringValue == "first")

        let result = await harness.appState.confirmClipboardSelection()

        #expect(result == .pasted)
        #expect(harness.pasteboard.stringByType[.string] == "first")
        #expect(harness.autoPasteEnv.postCommandVCount == 1)
        #expect(harness.presenter.hideImmediatelyForAutoPasteCount == 1)
        #expect(harness.appState.notchMode == .idle)
        #expect(harness.appState.selectedClipboardItemID == nil)
        #expect(!harness.appState.isKeyboardNavigationActive)
    }

    @Test func confirmClipboardSelectionOnEmptyHistoryIsSafeNoOp() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        harness.appState.openClipboardFromHotKey()
        #expect(harness.appState.selectedClipboardItemID == nil)

        let result = await harness.appState.confirmClipboardSelection()
        #expect(result == nil)
        #expect(harness.autoPasteEnv.postCommandVCount == 0)
    }

    @Test func doubleConfirmClipboardSelectionOnlyPastesOnce() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        harness.autoPasteEnv.suspendDuringPost = true
        recordItems(["only-once"], in: harness.historyStore)
        harness.appState.openClipboardFromHotKey()

        let appState = harness.appState
        let firstTask = Task { @MainActor in
            await appState.confirmClipboardSelection()
        }
        let secondTask = Task { @MainActor in
            await appState.confirmClipboardSelection()
        }
        let results = await (firstTask.value, secondTask.value)

        #expect(results.0 == .pasted)
        #expect(results.1 == nil)
        #expect(harness.autoPasteEnv.postCommandVCount == 1)
    }

    @Test func confirmClipboardSelectionDegradesToCopyOnlyWithoutAccessibility() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        harness.autoPasteEnv.trusted = false
        recordItems(["secret-note"], in: harness.historyStore)
        harness.appState.openClipboardFromHotKey()

        let result = await harness.appState.confirmClipboardSelection()

        #expect(result == .copiedOnly(reason: .accessibilityPermissionMissing))
        #expect(harness.pasteboard.stringByType[.string] == "secret-note")
        #expect(harness.autoPasteEnv.postCommandVCount == 0)
        #expect(harness.appState.activeNotification != nil)
    }

    // MARK: - NotchController Keyboard Command Mapping

    @Test func keyboardCommandMappingHandlesArrowsEnterEscapeAndPassesTextThrough() {
        // Arrow keys include `.function` and `.numericPad` flags on macOS
        let arrowFlags: NSEvent.ModifierFlags = [.function, .numericPad]
        #expect(NotchController.keyboardCommand(keyCode: UInt16(kVK_UpArrow), modifierFlags: arrowFlags, isARepeat: false) == .moveUp)
        #expect(NotchController.keyboardCommand(keyCode: UInt16(kVK_DownArrow), modifierFlags: arrowFlags, isARepeat: true) == .moveDown)

        // Return / Keypad Enter
        #expect(NotchController.keyboardCommand(keyCode: UInt16(kVK_Return), modifierFlags: [], isARepeat: false) == .confirm)
        #expect(NotchController.keyboardCommand(keyCode: UInt16(kVK_ANSI_KeypadEnter), modifierFlags: [], isARepeat: false) == .confirm)
        #expect(NotchController.keyboardCommand(keyCode: UInt16(kVK_Return), modifierFlags: [], isARepeat: true) == nil)
        #expect(NotchController.keyboardCommand(keyCode: UInt16(kVK_Return), modifierFlags: [.option], isARepeat: false) == .copyOnly)

        // Escape
        #expect(NotchController.keyboardCommand(keyCode: UInt16(kVK_Escape), modifierFlags: [], isARepeat: false) == .dismiss)
        #expect(NotchController.keyboardCommand(keyCode: UInt16(kVK_Escape), modifierFlags: [], isARepeat: true) == nil)

        // Regular typing & command shortcuts pass through to search field
        #expect(NotchController.keyboardCommand(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [], isARepeat: false) == nil)
        #expect(NotchController.keyboardCommand(keyCode: UInt16(kVK_ANSI_V), modifierFlags: [.command], isARepeat: false) == nil)
        #expect(NotchController.keyboardCommand(keyCode: UInt16(kVK_UpArrow), modifierFlags: [.command, .function], isARepeat: false) == nil)
    }
}

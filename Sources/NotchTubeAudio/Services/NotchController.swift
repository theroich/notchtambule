//
//  NotchController.swift
//  NotchTubeAudio
//

import AppKit
import SwiftUI
@preconcurrency import DynamicNotchKit

/// Owns the DynamicNotch window and translates global mouse proximity into
/// notch presentations.
///
/// Zones:
/// - **trigger**: the notch rectangle plus 15 pt. Entering it opens the queue.
/// - **retention**: the expanded notch plus 25 pt. Leaving it collapses the
///   queue / restarts the prompt auto-dismiss timer.
@MainActor
final class NotchController: NotchPresenting {
    private let appState: AppState
    private let settings: SettingsManager

    private lazy var notch: DynamicNotch<NotchRootView, EmptyView, EmptyView> = {
        // Capture the observable state directly: capturing `self` here would
        // create a retain cycle (controller → notch → view → controller).
        let appState = self.appState
        return DynamicNotch(
            hoverBehavior: [.hapticFeedback, .increaseShadow],
            style: .auto
        ) {
            NotchRootView(appState: appState)
        }
    }()

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var proximityTimer: Timer?

    private var promptTimer: Task<Void, Never>?
    private var autoHideTimer: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?

    private var isStarted = false
    private var hasPresented = false
    private var wasInsideRetention = false
    private var suppressHoverUntilExit = false
    private var lastMouseCheck: TimeInterval = 0
    private var currentScreen: NSScreen?
    private var pendingPresentationScreen: NSScreen?

    init(appState: AppState, settings: SettingsManager) {
        self.appState = appState
        self.settings = settings
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMovement()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMovement()
            }
            return event
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenParametersChange()
            }
        }

        // Safety net: global monitors do not receive mouse events that are
        // delivered to our own (transparent) panel, and they can be affected by
        // permissions. A 4 Hz poll of the cursor keeps the trigger/retention
        // zones reliable without measurable cost.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMovement(force: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        proximityTimer = timer

        Log.notch.info("Monitor de proximidad del notch iniciado")
    }

    func stop() {
        isStarted = false

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        proximityTimer?.invalidate()
        proximityTimer = nil

        cancelTimers()
        wasInsideRetention = false
        currentScreen = nil
        pendingPresentationScreen = nil

        if hasPresented {
            hasPresented = false
            enqueueTransition { controller in
                await controller.notch.hide()
            }
        }
    }

    // MARK: - NotchPresenting

    func presentPrompt() {
        cancelTimers()
        pendingPresentationScreen = nil

        guard let screen = promptScreen() else { return }
        expand(on: screen)
        schedulePromptAutoDismiss()
    }

    func presentPanel(autoHideAfter seconds: TimeInterval?) {
        promptTimer?.cancel()
        promptTimer = nil
        autoHideTimer?.cancel()
        autoHideTimer = nil

        let screen = pendingPresentationScreen ?? defaultPresentationScreen()
        pendingPresentationScreen = nil

        guard let screen else { return }
        expand(on: screen)

        if let seconds {
            scheduleAutoHide(after: seconds)
        }
    }

    func hide() {
        cancelTimers()
        pendingPresentationScreen = nil
        wasInsideRetention = false

        // Do not immediately re-open the panel when the user cancels the
        // prompt while the cursor is still over the notch; wait until the
        // pointer leaves the trigger zone.
        suppressHoverUntilExit = isPointerInsideTriggerZone()

        guard hasPresented else { return }
        hasPresented = false
        currentScreen = nil

        enqueueTransition { controller in
            await controller.notch.hide()
        }
    }

    // MARK: - Menu bar

    func toggleFromMenu() {
        switch appState.notchMode {
        case .idle:
            appState.showPanelFromMenu()
        case .promptingFeature:
            appState.dismissPrompt()
        case .showingPanel:
            appState.hideFromHover()
        }
    }

    // MARK: - Presentation

    private func expand(on screen: NSScreen, forceRecreate: Bool = false) {
        let requiresScreenChange = forceRecreate
            || (currentScreen != nil && currentScreen !== screen)
        currentScreen = screen
        hasPresented = true

        enqueueTransition { controller in
            // DynamicNotch does not move an already expanded window, so hide
            // first when the target display changed (multi-monitor support).
            if requiresScreenChange {
                await controller.notch.hide()
            }
            await controller.notch.expand(on: screen)
        }
    }

    /// Serialises presentation changes. The notch animations are asynchronous;
    /// without this queue a quick "hide → show" (cancel a prompt and copy a new
    /// link immediately) could finish with the panel hidden.
    private func enqueueTransition(_ operation: @escaping @MainActor (NotchController) async -> Void) {
        let previous = transitionTask
        transitionTask = Task { @MainActor [weak self] in
            _ = await previous?.value
            guard let self else { return }
            await operation(self)
        }
    }

    private func defaultPresentationScreen() -> NSScreen? {
        // The primary screen is the one with the menu bar.
        if let primary = NSScreen.screens.first, primary.nt_hasNotch {
            return primary
        }
        if let notchScreen = NSScreen.screens.first(where: { $0.nt_hasNotch }) {
            return notchScreen
        }
        if let pointerScreen = pointerScreen() {
            return pointerScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Prompts prefer the built-in camera housing; on notchless Macs they
    /// appear at the top of the primary display.
    private func promptScreen() -> NSScreen? {
        if let notchScreen = NSScreen.screens.first(where: { $0.nt_hasNotch }) {
            return notchScreen
        }
        return NSScreen.screens.first ?? pointerScreen() ?? NSScreen.main
    }

    private func pointerScreen() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    /// The screen whose notch zone should be tested for the current pointer.
    private func hoverScreen(for point: CGPoint) -> NSScreen? {
        let pointer = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
        let primary = NSScreen.screens.first

        if let pointer, pointer.nt_hasNotch {
            return pointer
        }
        if let primary, primary.nt_hasNotch {
            return primary
        }
        if let notchScreen = NSScreen.screens.first(where: { $0.nt_hasNotch }) {
            return notchScreen
        }
        return pointer ?? primary ?? NSScreen.main
    }

    // MARK: - Global mouse proximity

    private func handleMouseMovement(force: Bool = false) {
        guard isStarted else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if !force, now - lastMouseCheck < 0.03 { return }
        lastMouseCheck = now

        let point = NSEvent.mouseLocation
        guard let screen = hoverScreen(for: point) else { return }

        let geometry = NotchGeometry.make(for: screen, contentSize: currentContentSize)
        let insideTrigger = geometry.triggerRect.contains(point)
        let insideRetention = geometry.retentionRect.contains(point)

        switch appState.notchMode {
        case .idle:
            if insideTrigger {
                if suppressHoverUntilExit { break }
                pendingPresentationScreen = screen
                appState.showPanelFromHover()
            } else {
                suppressHoverUntilExit = false
            }

        case .promptingFeature:
            if insideRetention {
                promptTimer?.cancel()
                promptTimer = nil
            } else if wasInsideRetention {
                schedulePromptAutoDismiss()
            }

        case .showingPanel:
            if insideRetention {
                autoHideTimer?.cancel()
                autoHideTimer = nil
            } else if wasInsideRetention, !insideTrigger {
                scheduleCollapse()
            }
        }

        wasInsideRetention = insideRetention
    }

    private func isPointerInsideRetentionZone() -> Bool {
        let point = NSEvent.mouseLocation
        guard
            let screen = hoverScreen(for: point) ?? currentScreen
        else { return false }

        let geometry = NotchGeometry.make(for: screen, contentSize: currentContentSize)
        return geometry.retentionRect.contains(point)
    }

    private func isPointerInsideTriggerZone() -> Bool {
        let point = NSEvent.mouseLocation
        guard let screen = hoverScreen(for: point) else { return false }

        let geometry = NotchGeometry.make(for: screen, contentSize: currentContentSize)
        return geometry.triggerRect.contains(point)
    }

    // MARK: - Timers

    private func schedulePromptAutoDismiss() {
        promptTimer?.cancel()

        let duration = min(
            max(settings.promptAutoDismissSeconds, SettingsManager.minimumPromptDuration),
            SettingsManager.maximumPromptDuration
        )

        promptTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            guard self.appState.notchMode.isPrompting else { return }

            if self.isPointerInsideRetentionZone() {
                self.schedulePromptAutoDismiss()
                return
            }
            self.appState.dismissPromptFromTimeout()
        }
    }

    private func scheduleAutoHide(after seconds: TimeInterval) {
        autoHideTimer?.cancel()

        autoHideTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            guard self.appState.notchMode.isShowingPanel else { return }

            if self.isPointerInsideRetentionZone() {
                self.autoHideTimer = nil
                return
            }
            self.appState.hideFromTimeout()
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()

        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let self else { return }
            guard self.appState.notchMode.isShowingPanel else { return }
            guard !self.isPointerInsideRetentionZone() else { return }
            self.appState.hideFromHover()
        }
    }

    private func cancelTimers() {
        promptTimer?.cancel()
        promptTimer = nil
        autoHideTimer?.cancel()
        autoHideTimer = nil
        collapseTask?.cancel()
        collapseTask = nil
    }

    // MARK: - Screen changes

    private func handleScreenParametersChange() {
        pendingPresentationScreen = nil
        guard appState.notchMode != .idle else { return }
        guard let screen = defaultPresentationScreen() else { return }

        hasPresented = false
        currentScreen = nil
        // Route through this method so the NSScreen is passed as a parameter
        // (transfer-safe) instead of being sent from a local inside an async
        // closure.
        expand(on: screen, forceRecreate: true)
    }

    // MARK: - Geometry

    /// Estimated inner content size used to compute the retention zone. It is
    /// intentionally generous: an exact measurement is not needed thanks to the
    /// 25 pt margin.
    var currentContentSize: CGSize {
        let navigationHeaderHeight: CGFloat = appState.featureRegistry.activityPanelPlugins.isEmpty ? 0 : 34

        switch appState.notchMode {
        case .idle:
            return CGSize(width: NotchMetrics.contentWidth, height: 120)

        case .promptingFeature:
            return CGSize(width: NotchMetrics.contentWidth, height: 156)

        case .showingPanel(let tab):
            switch tab {
            case .clipboardHistory:
                let rows = max(appState.historyStore.filteredItems.count, 1)
                let listHeight = min(
                    CGFloat(rows) * NotchMetrics.queueRowHeight,
                    NotchMetrics.queueListMaxHeight
                )
                return CGSize(
                    width: NotchMetrics.contentWidth,
                    height: navigationHeaderHeight + NotchMetrics.queueHeaderHeight + 16 + listHeight
                )

            case .pluginActivity:
                return CGSize(
                    width: NotchMetrics.contentWidth,
                    height: navigationHeaderHeight + NotchMetrics.queueHeaderHeight + 16 + NotchMetrics.queueListMaxHeight
                )
            }
        }
    }
}

// DynamicNotch is an AppKit-backed ObservableObject that this app only creates
// and drives from the main actor. The conformance lets the `await
// notch.expand()` / `notch.hide()` calls cross the async boundary under Swift 6
// strict concurrency; behaviour is unchanged.
extension DynamicNotch: @retroactive @unchecked Sendable {}

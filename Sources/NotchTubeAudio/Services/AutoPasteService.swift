//
//  AutoPasteService.swift
//  NotchTubeAudio
//

import AppKit
@preconcurrency import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Reason why a clipboard item was only copied to `NSPasteboard` without synthesizing `⌘V`.
enum AutoPasteSkipReason: Equatable, Sendable {
    /// The user disabled "Pegar al hacer click" in Settings.
    case disabledInSettings
    /// The user held a modifier key (e.g. `⌥ Option`) to force copy-only behavior.
    case forcedCopyModifier
    /// macOS Accessibility permission (`AXIsProcessTrusted`) has not been granted.
    case accessibilityPermissionMissing
    /// macOS Secure Event Input is currently enabled (e.g. a password field is focused).
    case secureEventInputActive
    /// No valid target application was recorded or the target app terminated.
    case noTargetApplication
    /// Target application could not be brought to the foreground or `CGEvent` creation failed.
    case eventSynthesisFailed

    /// Short user-facing explanation when auto-paste degrades to copy-only.
    var userFacingMessage: String? {
        switch self {
        case .disabledInSettings, .forcedCopyModifier:
            return nil
        case .accessibilityPermissionMissing:
            return L10n.string("autopaste.skip.accessibility_missing")
        case .secureEventInputActive:
            return L10n.string("autopaste.skip.secure_input")
        case .noTargetApplication:
            return L10n.string("autopaste.skip.no_target_app")
        case .eventSynthesisFailed:
            return L10n.string("autopaste.skip.synthesis_failed")
        }
    }
}

/// Outcome of an auto-paste operation triggered from the clipboard history.
enum PasteResult: Equatable, Sendable {
    /// The item was written to `NSPasteboard` and `⌘V` was synthesized into the target application.
    case pasted
    /// The item was written to `NSPasteboard`, but `⌘V` was not synthesized for the given reason.
    case copiedOnly(reason: AutoPasteSkipReason)

    var didPaste: Bool {
        if case .pasted = self {
            return true
        }
        return false
    }
}

/// Visual feedback state displayed on a clipboard history row after clicking it.
enum ClipboardItemClickFeedback: Equatable, Sendable {
    case copied
    case pasted

    var badgeTitle: String {
        switch self {
        case .copied:
            return L10n.string("clipboard.row.copied")
        case .pasted:
            return L10n.string("clipboard.row.pasted")
        }
    }

    var badgeIcon: String {
        switch self {
        case .copied:
            return "checkmark.circle.fill"
        case .pasted:
            return "doc.on.clipboard.fill"
        }
    }
}

/// Lightweight abstraction over a running macOS application so `AutoPasteService`
/// can be deterministically unit-tested without activating real desktop windows.
@MainActor
protocol AutoPasteTargetApplication: AnyObject {
    var bundleIdentifier: String? { get }
    var localizedName: String? { get }
    var processIdentifier: pid_t { get }
    var isTerminated: Bool { get }
    var isActive: Bool { get }

    @discardableResult
    func activate() -> Bool
}

/// Production wrapper around `NSRunningApplication`.
@MainActor
final class RunningApplicationTarget: AutoPasteTargetApplication {
    let runningApplication: NSRunningApplication

    init(_ runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication
    }

    var bundleIdentifier: String? {
        runningApplication.bundleIdentifier
    }

    var localizedName: String? {
        runningApplication.localizedName
    }

    var processIdentifier: pid_t {
        runningApplication.processIdentifier
    }

    var isTerminated: Bool {
        runningApplication.isTerminated
    }

    var isActive: Bool {
        runningApplication.isActive
    }

    @discardableResult
    func activate() -> Bool {
        if NSApp.isActive {
            NSApp.yieldActivation(to: runningApplication)
        }
        return runningApplication.activate(options: [.activateAllWindows])
    }
}

/// System-level dependencies required by ``AutoPasteService`` (Accessibility trust,
/// frontmost application lookup, Secure Event Input detection, and `⌘V` synthesis).
@MainActor
protocol AutoPasteSystemEnvironment: AnyObject {
    /// Checks whether the current process is trusted for Accessibility (`AXIsProcessTrustedWithOptions`).
    func isAccessibilityTrusted(promptIfNeeded: Bool) -> Bool
    /// Opens macOS System Settings at *Privacy & Security → Accessibility*.
    @discardableResult
    func openAccessibilitySystemSettings() -> Bool
    /// Returns whether macOS Secure Event Input (`IsSecureEventInputEnabled`) is currently active.
    func isSecureEventInputEnabled() -> Bool
    /// Returns the currently frontmost application reported by `NSWorkspace`.
    func currentFrontmostApplication() -> (any AutoPasteTargetApplication)?
    /// Synthesizes a `⌘V` (`kVK_ANSI_V` keyDown + keyUp with `.maskCommand`) to `.cghidEventTap`.
    func postCommandVKeystrokes() -> Bool
    /// Suspends execution for the requested duration.
    func sleep(milliseconds: Int) async
}

/// Default macOS implementation of ``AutoPasteSystemEnvironment``.
@MainActor
final class SystemAutoPasteEnvironment: AutoPasteSystemEnvironment {
    static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func isAccessibilityTrusted(promptIfNeeded: Bool) -> Bool {
        if promptIfNeeded {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [promptKey: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    @discardableResult
    func openAccessibilitySystemSettings() -> Bool {
        NSWorkspace.shared.open(Self.accessibilitySettingsURL)
    }

    func isSecureEventInputEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }

    func currentFrontmostApplication() -> (any AutoPasteTargetApplication)? {
        guard let app = workspace.frontmostApplication else { return nil }
        return RunningApplicationTarget(app)
    }

    func postCommandVKeystrokes() -> Bool {
        let vKeyCode = CGKeyCode(kVK_ANSI_V) // 0x09
        // Prefer `.privateState` so physical mouse button / modifier states from the
        // click that triggered auto-paste do not bleed into the synthesized ⌘V event.
        guard let source = CGEventSource(stateID: .privateState) ?? CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        usleep(10_000)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    func sleep(milliseconds: Int) async {
        guard milliseconds > 0 else { return }
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

/// Service responsible for remembering the application that had focus prior to interacting
/// with the notch, verifying Accessibility permissions, restoring focus, and synthesizing `⌘V`.
@MainActor
final class AutoPasteService {
    /// Virtual key code for ANSI `V` (`0x09`).
    static let ansiVVirtualKeyCode: CGKeyCode = CGKeyCode(kVK_ANSI_V)

    private let environment: any AutoPasteSystemEnvironment
    private let ownBundleIdentifier: String?
    private let ownProcessIdentifier: pid_t

    /// The most recently remembered external frontmost application.
    private(set) var rememberedApp: (any AutoPasteTargetApplication)?
    private var workspaceActivationObserver: NSObjectProtocol?

    /// Delay in milliseconds after hiding the notch and activating the target application
    /// before checking focus / posting `⌘V`.
    var postActivationDelayMilliseconds: Int = 80
    /// Maximum number of additional poll attempts waiting for the target app to become frontmost.
    var maxFocusWaitAttempts: Int = 4
    /// Poll interval in milliseconds between focus checks.
    var focusPollIntervalMilliseconds: Int = 25

    init(
        environment: any AutoPasteSystemEnvironment = SystemAutoPasteEnvironment(),
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.environment = environment
        self.ownBundleIdentifier = ownBundleIdentifier
        self.ownProcessIdentifier = ownProcessIdentifier
    }

    // MARK: - Accessibility Permissions

    /// Returns `true` when the application currently holds macOS Accessibility permission.
    func canAutoPaste() -> Bool {
        environment.isAccessibilityTrusted(promptIfNeeded: false)
    }

    /// Queries macOS Accessibility permission, optionally triggering the system trust prompt.
    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        environment.isAccessibilityTrusted(promptIfNeeded: true)
    }

    /// Opens *System Settings → Privacy & Security → Accessibility* and triggers the system prompt
    /// so the binary is listed in the Accessibility table.
    @discardableResult
    func openAccessibilitySettings(promptIfNeeded: Bool = true) -> Bool {
        if promptIfNeeded {
            _ = environment.isAccessibilityTrusted(promptIfNeeded: true)
        }
        return environment.openAccessibilitySystemSettings()
    }

    // MARK: - Frontmost Application Tracking

    /// Starts observing `NSWorkspace.didActivateApplicationNotification` so the last
    /// external application is always tracked, even when the user opens the menu bar
    /// or Settings window before clicking a clipboard history entry.
    func startObservingFrontmostApplications(workspace: NSWorkspace = .shared) {
        guard workspaceActivationObserver == nil else { return }

        rememberFrontmostApp()
        workspaceActivationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                self?.recordActivatedApplication(RunningApplicationTarget(app))
            }
        }
    }

    /// Stops observing workspace application activations.
    func stopObservingFrontmostApplications(workspace: NSWorkspace = .shared) {
        if let observer = workspaceActivationObserver {
            workspace.notificationCenter.removeObserver(observer)
            workspaceActivationObserver = nil
        }
    }

    /// Records an externally activated application if it is not our own process.
    func recordActivatedApplication(_ app: any AutoPasteTargetApplication) {
        guard !isSelfApplication(app), !app.isTerminated else { return }
        rememberedApp = app
    }

    /// Captures the application that currently holds focus before the notch interacts with the user.
    /// If our own process happens to be frontmost (e.g. Settings window), keeps the previously
    /// remembered external application if it is still running.
    @discardableResult
    func rememberFrontmostApp() -> (any AutoPasteTargetApplication)? {
        if let current = environment.currentFrontmostApplication(),
           !isSelfApplication(current),
           !current.isTerminated {
            rememberedApp = current
            Log.clipboard.debug(
                "Remembered target app for auto-paste: \(current.localizedName ?? "unknown", privacy: .public) (\(current.bundleIdentifier ?? "no-bundle", privacy: .public))"
            )
            return current
        }

        if let rememberedApp, rememberedApp.isTerminated {
            self.rememberedApp = nil
        }
        return rememberedApp
    }

    // MARK: - Paste Execution

    /// Restores focus to `app` (or the remembered frontmost application) and synthesizes `⌘V`.
    ///
    /// - Parameter app: Explicit target application, or `nil` to use the remembered/current external app.
    /// - Returns: `.pasted` when `⌘V` was posted, or `.copiedOnly(reason:)` when auto-paste degraded to copy-only.
    func paste(into app: (any AutoPasteTargetApplication)? = nil) async -> PasteResult {
        guard canAutoPaste() else {
            Log.clipboard.info("Auto-paste degraded to copy-only: missing Accessibility permission")
            return .copiedOnly(reason: .accessibilityPermissionMissing)
        }

        guard !environment.isSecureEventInputEnabled() else {
            Log.clipboard.info("Auto-paste degraded to copy-only: SecureEventInput active")
            return .copiedOnly(reason: .secureEventInputActive)
        }

        guard let target = resolveTargetApplication(preferred: app) else {
            Log.clipboard.info("Auto-paste degraded to copy-only: no active target application")
            return .copiedOnly(reason: .noTargetApplication)
        }

        // Always activate the target app, even if `target.isActive` already reports `true`:
        // a `.nonactivatingPanel` (like the notch) can take key-window focus without
        // deactivating the underlying application, so explicitly re-activating helps
        // restore key focus cleanly before posting ⌘V.
        _ = target.activate()

        await environment.sleep(milliseconds: postActivationDelayMilliseconds)

        var attempt = 0
        while !isTargetFrontmost(target), attempt < maxFocusWaitAttempts {
            _ = target.activate()
            await environment.sleep(milliseconds: focusPollIntervalMilliseconds)
            attempt += 1
        }

        guard !target.isTerminated else {
            return .copiedOnly(reason: .noTargetApplication)
        }

        // Re-check SecureEventInput after the target application regains focus
        // (e.g. focusing a password field inside the target app activates SecureEventInput).
        guard !environment.isSecureEventInputEnabled() else {
            Log.clipboard.info("Auto-paste degraded to copy-only: target app activated SecureEventInput")
            return .copiedOnly(reason: .secureEventInputActive)
        }

        guard environment.postCommandVKeystrokes() else {
            Log.clipboard.error("Could not synthesize Command+V event via CGEvent")
            return .copiedOnly(reason: .eventSynthesisFailed)
        }

        Log.clipboard.info(
            "Synthesized Command+V in \(target.localizedName ?? "app", privacy: .public)"
        )
        return .pasted
    }

    /// Overload accepting a concrete `NSRunningApplication?` as proposed in Issue #14.
    func paste(into runningApp: NSRunningApplication?) async -> PasteResult {
        let target = runningApp.map(RunningApplicationTarget.init)
        return await paste(into: target)
    }

    // MARK: - Helpers

    private func resolveTargetApplication(
        preferred: (any AutoPasteTargetApplication)?
    ) -> (any AutoPasteTargetApplication)? {
        if let preferred, !preferred.isTerminated, !isSelfApplication(preferred) {
            return preferred
        }
        if let rememberedApp, !rememberedApp.isTerminated, !isSelfApplication(rememberedApp) {
            return rememberedApp
        }
        if let current = environment.currentFrontmostApplication(),
           !current.isTerminated,
           !isSelfApplication(current) {
            return current
        }
        return nil
    }

    private func isTargetFrontmost(_ target: any AutoPasteTargetApplication) -> Bool {
        if target.isActive {
            return true
        }
        if let current = environment.currentFrontmostApplication(),
           current.isActive {
            if current.processIdentifier == target.processIdentifier {
                return true
            }
            if let currentBundle = current.bundleIdentifier,
               let targetBundle = target.bundleIdentifier,
               currentBundle == targetBundle {
                return true
            }
        }
        return false
    }

    private func isSelfApplication(_ app: any AutoPasteTargetApplication) -> Bool {
        if app.processIdentifier == ownProcessIdentifier {
            return true
        }
        if let ownBundleIdentifier,
           let appBundle = app.bundleIdentifier,
           ownBundleIdentifier == appBundle {
            return true
        }
        return false
    }
}

//
//  GlobalHotKeyService.swift
//  NotchTubeAudio
//
//  Created for Issue #19.
//

import Carbon.HIToolbox
import Foundation
import Observation

/// Represents a global keyboard shortcut combination.
struct HotKey: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayString: String

    /// Default global shortcut to open the clipboard history (`⌃⌘V`).
    static let clipboardDefault = HotKey(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(controlKey | cmdKey),
        displayString: "⌃⌘V"
    )
}

/// Errors that can occur when registering a global hotkey via Carbon.
enum GlobalHotKeyError: Error, Equatable, Sendable {
    case alreadyInUse
    case handlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
}

/// Registration status for UI diagnostics (e.g. Settings).
enum GlobalHotKeyStatus: Equatable, Sendable {
    case inactive
    case active
    case conflict
    case failed
}

/// Abstraction over Carbon global hotkey registration so `GlobalHotKeyService`
/// can be unit-tested deterministically without touching system-wide hotkeys.
@MainActor
protocol GlobalHotKeyRegistering: AnyObject {
    func register(hotKey: HotKey, onTrigger: @escaping @MainActor () -> Void) throws
    func unregister()
}

private final class HotKeyCallbackBox: @unchecked Sendable {
    let expectedSignature: OSType
    let expectedID: UInt32
    let handler: @MainActor () -> Void

    init(
        expectedSignature: OSType,
        expectedID: UInt32,
        handler: @escaping @MainActor () -> Void
    ) {
        self.expectedSignature = expectedSignature
        self.expectedID = expectedID
        self.handler = handler
    }
}

/// Production Carbon implementation using `RegisterEventHotKey` and `InstallEventHandler`.
/// Carbon consumes the hotkey event globally without requiring Accessibility permission.
@MainActor
final class CarbonHotKeyRegistrar: GlobalHotKeyRegistering {
    private static let hotKeySignature: OSType = 0x4E54_484B // "NTHK"
    private static let hotKeyIdentifier: UInt32 = 1

    private var eventHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var callbackBox: HotKeyCallbackBox?

    func register(hotKey: HotKey, onTrigger: @escaping @MainActor () -> Void) throws {
        unregister()

        let box = HotKeyCallbackBox(
            expectedSignature: Self.hotKeySignature,
            expectedID: Self.hotKeyIdentifier,
            handler: onTrigger
        )
        self.callbackBox = box

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        var handlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.carbonEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(box).toOpaque(),
            &handlerRef
        )

        guard installStatus == noErr, let handlerRef else {
            self.callbackBox = nil
            throw GlobalHotKeyError.handlerInstallationFailed(installStatus)
        }
        self.eventHandlerRef = handlerRef

        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyIdentifier
        )

        var hotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr, let hotKeyRef else {
            RemoveEventHandler(handlerRef)
            self.eventHandlerRef = nil
            self.callbackBox = nil

            if registerStatus == OSStatus(eventHotKeyExistsErr) {
                throw GlobalHotKeyError.alreadyInUse
            }
            throw GlobalHotKeyError.registrationFailed(registerStatus)
        }

        self.eventHotKeyRef = hotKeyRef
    }

    func unregister() {
        if let eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
            self.eventHotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        callbackBox = nil
    }

    private static let carbonEventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        var pressedID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &pressedID
        )

        guard status == noErr else {
            return OSStatus(eventNotHandledErr)
        }

        let box = Unmanaged<HotKeyCallbackBox>.fromOpaque(userData).takeUnretainedValue()
        guard pressedID.signature == box.expectedSignature,
              pressedID.id == box.expectedID else {
            return OSStatus(eventNotHandledErr)
        }

        Task { @MainActor in
            box.handler()
        }
        return noErr
    }
}

/// Manages registration and lifecycle of the global clipboard shortcut (`⌃⌘V`).
@MainActor
@Observable
final class GlobalHotKeyService {
    let hotKey: HotKey
    private let registrar: any GlobalHotKeyRegistering

    private(set) var isRegistered = false
    private(set) var status: GlobalHotKeyStatus = .inactive

    var onHotKey: (@MainActor () -> Void)?

    init(
        hotKey: HotKey = .clipboardDefault,
        registrar: any GlobalHotKeyRegistering = CarbonHotKeyRegistrar()
    ) {
        self.hotKey = hotKey
        self.registrar = registrar
    }

    /// Registers the global hotkey if not already registered. Idempotent.
    func start() throws {
        guard !isRegistered else { return }

        do {
            try registrar.register(hotKey: hotKey) { [weak self] in
                self?.onHotKey?()
            }
            isRegistered = true
            status = .active
            Log.app.info("Registered global hotkey \(self.hotKey.displayString, privacy: .public)")
        } catch GlobalHotKeyError.alreadyInUse {
            isRegistered = false
            status = .conflict
            Log.app.warning("Global hotkey \(self.hotKey.displayString, privacy: .public) is already in use by another application")
            throw GlobalHotKeyError.alreadyInUse
        } catch {
            isRegistered = false
            status = .failed
            Log.app.warning("Failed to register global hotkey \(self.hotKey.displayString, privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Unregisters the global hotkey if active.
    func stop() {
        guard isRegistered || status != .inactive else { return }
        registrar.unregister()
        isRegistered = false
        status = .inactive
        Log.app.info("Unregistered global hotkey \(self.hotKey.displayString, privacy: .public)")
    }
}

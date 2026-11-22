//
//  FeatureModels.swift
//  NotchTubeAudio
//

import Foundation

/// Acción rápida expuesta por un ``ClipboardFeaturePlugin`` para una fila compatible
/// en el historial del portapapeles.
struct FeatureQuickAction: Identifiable {
    let id: String
    let pluginID: String
    let title: String
    let iconSystemName: String
    let handler: @MainActor () -> Void

    init(
        id: String,
        pluginID: String,
        title: String,
        iconSystemName: String,
        handler: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.pluginID = pluginID
        self.title = title
        self.iconSystemName = iconSystemName
        self.handler = handler
    }
}

/// Notificación visual breve solicitada por un plugin a través de ``FeatureActionContext``.
struct FeatureUserNotification: Equatable, Sendable {
    let message: String
    let icon: String

    init(message: String, icon: String) {
        self.message = message
        self.icon = icon
    }
}

/// Proporciona a cualquier ``ClipboardFeaturePlugin`` acceso seguro y desacoplado
/// a las primitivas del sistema (portapapeles, presentación del notch y notificaciones).
@MainActor
final class FeatureActionContext {
    private let onWriteToClipboard: (ClipboardPayload) -> Void
    private let onPresentPluginPrompt: (String, ClipboardItem) -> Void
    private let onSwitchToPluginActivity: (String) -> Void
    private let onHideNotch: () -> Void
    private let onNotifyUser: (String, String) -> Void

    /// Historial de payloads escritos al portapapeles a través de este contexto (útil para inspección/tests).
    private(set) var writtenPayloads: [ClipboardPayload] = []
    /// Último prompt solicitado mediante `presentPluginPrompt(pluginID:for:)`.
    private(set) var lastPresentedPrompt: (pluginID: String, item: ClipboardItem)?
    /// Último panel de actividad activado mediante `switchToPluginActivity(pluginID:)`.
    private(set) var lastSwitchedActivityPluginID: String?
    /// Número de veces que se ha solicitado ocultar el notch.
    private(set) var hideNotchCallCount: Int = 0
    /// Última notificación emitida mediante `notifyUser(message:icon:)`.
    private(set) var lastNotification: FeatureUserNotification?

    init(
        onWriteToClipboard: @escaping (ClipboardPayload) -> Void = { _ in },
        onPresentPluginPrompt: @escaping (String, ClipboardItem) -> Void = { _, _ in },
        onSwitchToPluginActivity: @escaping (String) -> Void = { _ in },
        onHideNotch: @escaping () -> Void = {},
        onNotifyUser: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.onWriteToClipboard = onWriteToClipboard
        self.onPresentPluginPrompt = onPresentPluginPrompt
        self.onSwitchToPluginActivity = onSwitchToPluginActivity
        self.onHideNotch = onHideNotch
        self.onNotifyUser = onNotifyUser
    }

    /// Contexto sin efectos secundarios listo para evaluaciones de vistas o tests unitarios.
    static var noop: FeatureActionContext {
        FeatureActionContext()
    }

    /// Escribe un payload transformado (ej. URL limpia o JSON formateado) de vuelta al portapapeles.
    func writeToClipboard(_ payload: ClipboardPayload) {
        writtenPayloads.append(payload)
        onWriteToClipboard(payload)
    }

    /// Solicita abrir el prompt completo de un plugin en el notch para el ítem indicado.
    func presentPluginPrompt(pluginID: String, for item: ClipboardItem) {
        lastPresentedPrompt = (pluginID, item)
        onPresentPluginPrompt(pluginID, item)
    }

    /// Pasa de la vista actual a la vista de progreso/actividad del plugin en el notch.
    func switchToPluginActivity(pluginID: String) {
        lastSwitchedActivityPluginID = pluginID
        onSwitchToPluginActivity(pluginID)
    }

    /// Oculta o colapsa el notch.
    func hideNotch() {
        hideNotchCallCount += 1
        onHideNotch()
    }

    /// Muestra un feedback visual breve en el notch con un mensaje y un icono SF Symbol.
    func notifyUser(message: String, icon: String) {
        lastNotification = FeatureUserNotification(message: message, icon: icon)
        onNotifyUser(message, icon)
    }
}

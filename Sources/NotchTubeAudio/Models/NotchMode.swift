//
//  NotchMode.swift
//  NotchTubeAudio
//

import Foundation

/// The active tab inside the expanded notch panel.
enum NotchPanelTab: Equatable, Hashable, Sendable {
    /// Vista principal del historial del portapapeles.
    case clipboardHistory
    /// Panel de actividad de un plugin específico (ej. cola de descargas de YouTube).
    case pluginActivity(pluginID: String)
}

/// The three mutually exclusive states of the notch interface.
enum NotchMode: Equatable, Sendable {
    /// El notch está colapsado.
    case idle

    /// Un plugin ha disparado un prompt contextual tras una copia al portapapeles.
    case promptingFeature(pluginID: String, item: ClipboardItem)

    /// El usuario ha abierto el panel del notch (por hover, menú o tras iniciar una acción).
    case showingPanel(tab: NotchPanelTab)

    var isPrompting: Bool {
        if case .promptingFeature = self {
            return true
        }
        return false
    }

    var isShowingPanel: Bool {
        if case .showingPanel = self {
            return true
        }
        return false
    }
}

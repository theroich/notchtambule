//
//  ClipboardFeaturePlugin.swift
//  NotchTubeAudio
//

import SwiftUI

/// Prioridad del módulo cuando varios plugins coinciden con un mismo ClipboardItem.
enum FeaturePriority: Int, Comparable, Sendable {
    case low = 10        // Acciones genéricas (ej. contar palabras, abrir URL)
    case normal = 50     // Transformadores específicos (ej. formatear JSON, limpiar tracking de URL)
    case high = 100      // Acciones ricas con prompt proactivo (ej. Descargador de YouTube)

    static func < (lhs: FeaturePriority, rhs: FeaturePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Comportamiento al detectar un nuevo ítem en el portapapeles.
enum FeatureTriggerBehavior: String, Codable, Sendable, CaseIterable {
    /// Abre automáticamente el prompt del plugin en el notch al copiar un ítem compatible.
    case automaticPrompt
    /// Solo muestra una acción rápida (badge/botón) en la fila del historial del portapapeles.
    case historyActionOnly
}

@MainActor
protocol ClipboardFeaturePlugin: AnyObject, Identifiable {
    /// Identificador único estable (ej. "com.notchclip.plugin.youtube-audio").
    var id: String { get }
    /// Nombre legible para el usuario (ej. "Descargador de Audio de YouTube").
    var displayName: String { get }
    /// Descripción breve mostrada en la pestaña de Módulos de Ajustes.
    var summary: String { get }
    /// Icono SF Symbol representativo del módulo.
    var iconSystemName: String { get }
    /// Prioridad frente a otros plugins.
    var priority: FeaturePriority { get }
    /// Comportamiento por defecto al copiar.
    var defaultTriggerBehavior: FeatureTriggerBehavior { get }

    /// Ciclo de vida
    func start()
    func shutdown()

    /// Evalúa de forma síncrona y rápida si este plugin soporta el ítem del portapapeles.
    func canHandle(_ item: ClipboardItem) -> Bool

    /// Acción rápida opcional que aparece en cada fila compatible dentro del historial del portapapeles.
    func quickActions(for item: ClipboardItem, context: FeatureActionContext) -> [FeatureQuickAction]

    /// Si el plugin soporta prompt proactivo en el notch, prepara su estado para el ítem y devuelve la vista del prompt.
    func makePromptView(
        for item: ClipboardItem,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView?

    /// Pestaña o panel de actividad en segundo plano (ej. cola de descargas activas) si el plugin gestiona tareas asíncronas.
    var hasActivityPanel: Bool { get }
    var activeTasksCount: Int { get }
    func makeActivityPanelView(context: FeatureActionContext) -> AnyView?

    /// Vista de configuración propia del plugin para incrustar en la ventana de Ajustes.
    func makeSettingsView() -> AnyView?
}

extension ClipboardFeaturePlugin {
    var priority: FeaturePriority { .normal }
    var defaultTriggerBehavior: FeatureTriggerBehavior { .historyActionOnly }

    func start() {}
    func shutdown() {}

    func quickActions(for item: ClipboardItem, context: FeatureActionContext) -> [FeatureQuickAction] {
        []
    }

    func makePromptView(
        for item: ClipboardItem,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView? {
        nil
    }

    var hasActivityPanel: Bool { false }
    var activeTasksCount: Int { 0 }

    func makeActivityPanelView(context: FeatureActionContext) -> AnyView? {
        nil
    }

    func makeSettingsView() -> AnyView? {
        nil
    }
}

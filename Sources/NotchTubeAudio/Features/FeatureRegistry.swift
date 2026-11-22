//
//  FeatureRegistry.swift
//  NotchTubeAudio
//

import Foundation
import Observation

/// Catálogo central y enrutador de módulos ``ClipboardFeaturePlugin``.
///
/// Evalúa cada ``ClipboardItem`` frente a los plugins registrados y habilitados,
/// gestiona su ciclo de vida (`start()` / `shutdown()`) y delega la persistencia
/// de preferencias por módulo en ``SettingsManager``.
@MainActor
@Observable
final class FeatureRegistry {
    private(set) var plugins: [any ClipboardFeaturePlugin] = []

    private let settings: SettingsManager
    @ObservationIgnored private var startedPluginIDs: Set<String> = []

    init(
        settings: SettingsManager,
        plugins: [any ClipboardFeaturePlugin] = []
    ) {
        self.settings = settings
        for plugin in plugins {
            register(plugin)
        }
    }

    // MARK: - Registration & Lookup

    /// Registra un plugin en el catálogo central.
    ///
    /// Si ya existía un plugin con el mismo `id`, se detiene el anterior y se reemplaza.
    /// Si el plugin está habilitado según `SettingsManager`, se invoca su `start()`.
    func register(_ plugin: any ClipboardFeaturePlugin) {
        if let existingIndex = plugins.firstIndex(where: { $0.id == plugin.id }) {
            let existing = plugins[existingIndex]
            if startedPluginIDs.remove(existing.id) != nil {
                existing.shutdown()
            }
            plugins[existingIndex] = plugin
        } else {
            plugins.append(plugin)
        }

        if isPluginEnabled(plugin.id) {
            plugin.start()
            startedPluginIDs.insert(plugin.id)
        }
    }

    /// Elimina un plugin del registro por su identificador e invoca `shutdown()` si estaba activo.
    func unregister(id: String) {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else { return }
        let removed = plugins.remove(at: index)
        if startedPluginIDs.remove(removed.id) != nil {
            removed.shutdown()
        }
    }

    /// Busca un plugin registrado por su identificador único.
    func plugin(withID id: String) -> (any ClipboardFeaturePlugin)? {
        plugins.first { $0.id == id }
    }

    // MARK: - Enablement & Trigger Behavior

    /// Devuelve `true` si el plugin está habilitado (por defecto `true` cuando no hay preferencia guardada).
    func isPluginEnabled(_ id: String) -> Bool {
        settings.isPluginEnabled(id)
    }

    /// Habilita o deshabilita un plugin, persistiendo el estado en ``SettingsManager``
    /// e invocando `start()` o `shutdown()` según corresponda.
    func setPluginEnabled(_ id: String, _ enabled: Bool) {
        let wasEnabled = isPluginEnabled(id)
        settings.setPluginEnabled(id, enabled)

        guard let plugin = plugin(withID: id) else { return }

        if enabled {
            if !wasEnabled || !startedPluginIDs.contains(id) {
                plugin.start()
                startedPluginIDs.insert(id)
            }
        } else {
            if wasEnabled || startedPluginIDs.contains(id) {
                startedPluginIDs.remove(id)
                plugin.shutdown()
            }
        }
    }

    /// Devuelve el comportamiento de disparo configurado para el plugin, o su `defaultTriggerBehavior`
    /// si el usuario no lo ha personalizado.
    func triggerBehavior(for id: String) -> FeatureTriggerBehavior {
        let fallback = plugin(withID: id)?.defaultTriggerBehavior ?? .historyActionOnly
        return settings.triggerBehavior(for: id, defaultBehavior: fallback)
    }

    /// Actualiza y persiste el comportamiento de disparo (`automaticPrompt` vs `historyActionOnly`) para un plugin.
    func setTriggerBehavior(_ behavior: FeatureTriggerBehavior, for id: String) {
        settings.setTriggerBehavior(behavior, for: id)
    }

    /// Indica si un plugin soporta mostrar un prompt proactivo en el notch.
    func pluginSupportsPrompt(_ plugin: any ClipboardFeaturePlugin) -> Bool {
        if plugin.supportsPrompt {
            return true
        }
        let probeItem = ClipboardItem(changeCount: 0, payload: .text(""))
        return plugin.makePromptView(
            for: probeItem,
            context: .noop,
            onComplete: {},
            onDismiss: {}
        ) != nil
    }

    // MARK: - Evaluation & Routing

    /// Devuelve todos los plugins habilitados que soportan el `item` dado (`plugin.canHandle(item) == true`),
    /// ordenados de mayor a menor ``FeaturePriority`` (manteniendo el orden de registro en caso de empate).
    func matchingPlugins(for item: ClipboardItem) -> [any ClipboardFeaturePlugin] {
        let enabledMatching = plugins.enumerated().filter { _, plugin in
            isPluginEnabled(plugin.id) && plugin.canHandle(item)
        }

        return enabledMatching
            .sorted { lhs, rhs in
                if lhs.element.priority != rhs.element.priority {
                    return lhs.element.priority > rhs.element.priority
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Devuelve el plugin habilitado y compatible de mayor prioridad cuyo `triggerBehavior` sea `.automaticPrompt`
    /// y cuyo `makePromptView(...)` no sea `nil`.
    func primaryPromptPlugin(
        for item: ClipboardItem,
        context: FeatureActionContext = .noop
    ) -> (any ClipboardFeaturePlugin)? {
        for plugin in matchingPlugins(for: item) {
            guard triggerBehavior(for: plugin.id) == .automaticPrompt else {
                continue
            }
            let promptView = plugin.makePromptView(
                for: item,
                context: context,
                onComplete: {},
                onDismiss: {}
            )
            if promptView != nil {
                return plugin
            }
        }
        return nil
    }

    /// Recopila todas las acciones rápidas (`FeatureQuickAction`) de los plugins habilitados y compatibles
    /// con el `item` (en orden de prioridad descendente), independientemente de si su `triggerBehavior`
    /// es `.automaticPrompt` o `.historyActionOnly`.
    func quickActions(
        for item: ClipboardItem,
        context: FeatureActionContext
    ) -> [FeatureQuickAction] {
        matchingPlugins(for: item).flatMap { plugin in
            plugin.quickActions(for: item, context: context)
        }
    }

    /// Plugins habilitados que disponen de panel de actividad propio (`hasActivityPanel == true`).
    var activityPanelPlugins: [any ClipboardFeaturePlugin] {
        plugins.filter { isPluginEnabled($0.id) && $0.hasActivityPanel }
    }

    /// Suma total de tareas activas en todos los plugins habilitados.
    var totalActiveTasksCount: Int {
        plugins
            .filter { isPluginEnabled($0.id) }
            .reduce(0) { $0 + max(0, $1.activeTasksCount) }
    }

    // MARK: - Lifecycle

    /// Inicia todos los plugins registrados que estén habilitados y aún no hayan sido iniciados.
    func startAllEnabled() {
        for plugin in plugins where isPluginEnabled(plugin.id) {
            if !startedPluginIDs.contains(plugin.id) {
                plugin.start()
                startedPluginIDs.insert(plugin.id)
            }
        }
    }

    /// Detiene todos los plugins activos invocando su `shutdown()`.
    func shutdownAll() {
        for plugin in plugins where startedPluginIDs.remove(plugin.id) != nil {
            plugin.shutdown()
        }
    }
}

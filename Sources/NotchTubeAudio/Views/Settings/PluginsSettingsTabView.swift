//
//  PluginsSettingsTabView.swift
//  NotchTubeAudio
//

import SwiftUI

/// Pestaña 2 de la ventana de Ajustes: Gestor de Módulos / Plugins (`puzzlepiece.extension`).
///
/// Genera dinámicamente la lista de todos los ``ClipboardFeaturePlugin`` registrados en
/// ``FeatureRegistry``, permitiendo activarlos/desactivarlos, configurar su modo de disparo
/// (`.automaticPrompt` vs `.historyActionOnly`) e inyectar la vista de preferencias propia
/// de cada plugin mediante `plugin.makeSettingsView()`.
struct PluginsSettingsTabView: View {
    let featureRegistry: FeatureRegistry

    @State private var selectedPluginID: String?

    var body: some View {
        Group {
            if featureRegistry.plugins.isEmpty {
                emptyModulesState
            } else {
                Form {
                    ForEach(featureRegistry.plugins, id: \.id) { plugin in
                        pluginHeaderSection(for: plugin)

                        if let pluginSettingsView = plugin.makeSettingsView() {
                            pluginSettingsView
                                .disabled(!featureRegistry.isPluginEnabled(plugin.id))
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .onAppear {
            if selectedPluginID == nil {
                selectedPluginID = featureRegistry.plugins.first?.id
            }
        }
    }

    // MARK: - Module Card / Section

    @ViewBuilder
    private func pluginHeaderSection(for plugin: any ClipboardFeaturePlugin) -> some View {
        let isEnabled = featureRegistry.isPluginEnabled(plugin.id)

        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: plugin.iconSystemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill((isEnabled ? Color.accentColor : Color.secondary).opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plugin.displayName)
                            .font(.headline)

                        Text(isEnabled ? "Activo" : "Inactivo")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isEnabled ? .green : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill((isEnabled ? Color.green : Color.secondary).opacity(0.14))
                            )
                    }

                    Text(plugin.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Toggle("Habilitar módulo", isOn: enabledBinding(for: plugin.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help(isEnabled ? "Desactivar \(plugin.displayName)" : "Activar \(plugin.displayName)")
                    .accessibilityLabel("Habilitar \(plugin.displayName)")
            }
            .padding(.vertical, 2)

            if featureRegistry.pluginSupportsPrompt(plugin) {
                Picker("Modo de disparo al copiar", selection: triggerBehaviorBinding(for: plugin.id)) {
                    Text("Mostrar aviso automático en el notch al copiar")
                        .tag(FeatureTriggerBehavior.automaticPrompt)

                    Text("Solo mostrar acción rápida en el historial")
                        .tag(FeatureTriggerBehavior.historyActionOnly)
                }
                .disabled(!isEnabled)
            }
        } header: {
            Label(plugin.displayName, systemImage: plugin.iconSystemName)
        }
    }

    private var emptyModulesState: some View {
        VStack(spacing: 10) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text("No hay módulos registrados")
                .font(.headline)

            Text("Registra instancias de ClipboardFeaturePlugin en FeatureRegistry para configurarlas aquí.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Bindings

    private func enabledBinding(for pluginID: String) -> Binding<Bool> {
        Binding(
            get: { featureRegistry.isPluginEnabled(pluginID) },
            set: { featureRegistry.setPluginEnabled(pluginID, $0) }
        )
    }

    private func triggerBehaviorBinding(for pluginID: String) -> Binding<FeatureTriggerBehavior> {
        Binding(
            get: { featureRegistry.triggerBehavior(for: pluginID) },
            set: { featureRegistry.setTriggerBehavior($0, for: pluginID) }
        )
    }
}

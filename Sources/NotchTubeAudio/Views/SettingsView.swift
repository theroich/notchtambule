//
//  SettingsView.swift
//  NotchTubeAudio
//

import AppKit
import SwiftUI

/// Pestañas principales de la ventana de Ajustes (`⌘,`).
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case clipboardAndGeneral
    case plugins

    var id: String { rawValue }
}

/// SwiftUI settings window (Scene > Settings, Cmd+,).
///
/// Dividida en:
/// 1. **Portapapeles y General** (`doc.on.clipboard`): escucha automática, persistencia,
///    privacidad de contraseñas, límite del historial y duración del aviso en el notch.
/// 2. **Módulos (Funcionalidades)** (`puzzlepiece.extension`): gestión dinámica de
///    todos los ``ClipboardFeaturePlugin`` registrados en ``FeatureRegistry``.
struct SettingsView: View {
    /// Opciones predefinidas para el límite de elementos en el historial del portapapeles.
    static let historyLimitPresets: [Int] = [25, 50, 100, 250, 500]

    let settings: SettingsManager
    let featureRegistry: FeatureRegistry
    let historyStore: ClipboardHistoryStore?

    @State private var selectedTab: SettingsTab = .clipboardAndGeneral
    @State private var isConfirmingClearHistory = false

    init(
        settings: SettingsManager,
        featureRegistry: FeatureRegistry,
        historyStore: ClipboardHistoryStore? = nil
    ) {
        self.settings = settings
        self.featureRegistry = featureRegistry
        self.historyStore = historyStore
    }

    init(environment: AppEnvironment) {
        self.init(
            settings: environment.settings,
            featureRegistry: environment.featureRegistry,
            historyStore: environment.historyStore
        )
    }

    /// Inicializador de compatibilidad cuando solo se inyecta `SettingsManager`.
    init(settings: SettingsManager) {
        let defaultRegistry = FeatureRegistry(
            settings: settings,
            plugins: [YouTubeAudioFeaturePlugin(settings: settings)]
        )
        self.init(
            settings: settings,
            featureRegistry: defaultRegistry,
            historyStore: nil
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            clipboardAndGeneralTab
                .tabItem {
                    Label("Portapapeles y General", systemImage: "doc.on.clipboard")
                }
                .tag(SettingsTab.clipboardAndGeneral)

            PluginsSettingsTabView(featureRegistry: featureRegistry)
                .tabItem {
                    Label("Módulos", systemImage: "puzzlepiece.extension")
                }
                .tag(SettingsTab.plugins)
        }
        .frame(width: 600, height: 500)
    }

    // MARK: - Pestaña 1: Portapapeles y General

    private var clipboardAndGeneralTab: some View {
        Form {
            Section("Monitorización del Portapapeles") {
                Toggle("Escuchar el portapapeles automáticamente", isOn: monitoringBinding)

                Toggle("Persistir historial al cerrar la aplicación", isOn: persistHistoryBinding)

                Toggle("Ignorar contenido confidencial de gestores de contraseñas", isOn: ignoreConfidentialBinding)

                Text("Se excluyen automáticamente las entradas marcadas como confidenciales o transitorias por aplicaciones como 1Password, Bitwarden o macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Historial del Portapapeles") {
                LabeledContent("Límite de elementos en el historial") {
                    Picker("Límite de elementos en el historial", selection: maxHistoryItemsBinding) {
                        ForEach(availableHistoryLimitOptions, id: \.self) { limit in
                            Text("\(limit) elementos").tag(limit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                LabeledContent("Mantenimiento") {
                    HStack(spacing: 10) {
                        if let historyStore {
                            Text("\(historyStore.items.count) elementos guardados")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button("Vaciar historial ahora…", role: .destructive) {
                            isConfirmingClearHistory = true
                        }
                        .disabled(historyStore?.items.isEmpty ?? false)
                    }
                }
                .confirmationDialog(
                    "¿Vaciar todo el historial del portapapeles?",
                    isPresented: $isConfirmingClearHistory,
                    titleVisibility: .visible
                ) {
                    Button("Vaciar todo (incluidos fijados)", role: .destructive) {
                        historyStore?.clearAll()
                    }

                    if historyStore?.items.contains(where: \.isPinned) == true {
                        Button("Vaciar solo elementos no fijados") {
                            historyStore?.clearUnpinned()
                        }
                    }

                    Button("Cancelar", role: .cancel) {}
                } message: {
                    Text("Esta acción eliminará los elementos guardados en el historial del portapapeles.")
                }
            }

            Section("Comportamiento del Notch") {
                LabeledContent("Ocultar el aviso tras") {
                    HStack(spacing: 10) {
                        Slider(
                            value: promptDurationBinding,
                            in: SettingsManager.minimumPromptDuration...SettingsManager.maximumPromptDuration,
                            step: 1
                        )
                        .frame(width: 190)

                        Text("\(Int(settings.promptAutoDismissSeconds)) s")
                            .font(.system(.caption, design: .monospaced))
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                Text("El aviso emergente de los módulos permanece abierto mientras el cursor esté sobre el notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var availableHistoryLimitOptions: [Int] {
        let current = settings.maxClipboardHistoryItems
        if Self.historyLimitPresets.contains(current) {
            return Self.historyLimitPresets
        }
        return (Self.historyLimitPresets + [current]).sorted()
    }

    // MARK: - Bindings

    private var monitoringBinding: Binding<Bool> {
        Binding(
            get: { settings.isClipboardMonitoringEnabled },
            set: { settings.isClipboardMonitoringEnabled = $0 }
        )
    }

    private var persistHistoryBinding: Binding<Bool> {
        Binding(
            get: { settings.persistClipboardHistory },
            set: { newValue in
                settings.persistClipboardHistory = newValue
                historyStore?.flushPendingPersistence()
            }
        )
    }

    private var ignoreConfidentialBinding: Binding<Bool> {
        Binding(
            get: { settings.ignoreConfidentialPasteboardTypes },
            set: { settings.ignoreConfidentialPasteboardTypes = $0 }
        )
    }

    private var maxHistoryItemsBinding: Binding<Int> {
        Binding(
            get: { settings.maxClipboardHistoryItems },
            set: { newValue in
                settings.maxClipboardHistoryItems = newValue
                historyStore?.enforceRetentionLimit()
                historyStore?.flushPendingPersistence()
            }
        )
    }

    private var promptDurationBinding: Binding<Double> {
        Binding(
            get: { settings.promptAutoDismissSeconds },
            set: { settings.promptAutoDismissSeconds = $0 }
        )
    }
}

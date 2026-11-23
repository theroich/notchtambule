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
    let autoPasteService: AutoPasteService
    let globalHotKeyService: GlobalHotKeyService?

    @State private var selectedTab: SettingsTab = .clipboardAndGeneral
    @State private var isConfirmingClearHistory = false
    @State private var isAccessibilityTrusted = false

    init(
        settings: SettingsManager,
        featureRegistry: FeatureRegistry,
        historyStore: ClipboardHistoryStore? = nil,
        autoPasteService: AutoPasteService = AutoPasteService(),
        globalHotKeyService: GlobalHotKeyService? = nil
    ) {
        self.settings = settings
        self.featureRegistry = featureRegistry
        self.historyStore = historyStore
        self.autoPasteService = autoPasteService
        self.globalHotKeyService = globalHotKeyService
        self._isAccessibilityTrusted = State(initialValue: autoPasteService.canAutoPaste())
    }

    init(environment: AppEnvironment) {
        self.init(
            settings: environment.settings,
            featureRegistry: environment.featureRegistry,
            historyStore: environment.historyStore,
            autoPasteService: environment.autoPasteService,
            globalHotKeyService: environment.globalHotKeyService
        )
    }

    /// Inicializador de compatibilidad cuando solo se inyecta `SettingsManager`.
    init(settings: SettingsManager) {
        let defaultRegistry = FeatureRegistry(
            settings: settings,
            plugins: [
                YouTubeAudioFeaturePlugin(settings: settings),
                URLCleanerFeaturePlugin(),
                JSONFormatterFeaturePlugin(),
                ColorConverterFeaturePlugin(),
                OCRFeaturePlugin(),
                FileActionsFeaturePlugin(),
                DeveloperToolkitFeaturePlugin()
            ]
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
                    Label(L10n.string("settings.tab.general"), systemImage: "doc.on.clipboard")
                }
                .tag(SettingsTab.clipboardAndGeneral)

            PluginsSettingsTabView(featureRegistry: featureRegistry)
                .tabItem {
                    Label(L10n.string("settings.tab.modules"), systemImage: "puzzlepiece.extension")
                }
                .tag(SettingsTab.plugins)
        }
        .environment(\.locale, settings.resolvedLocale)
        .frame(width: 600, height: 520)
        .onAppear {
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
    }

    private func refreshAccessibilityStatus() {
        isAccessibilityTrusted = autoPasteService.canAutoPaste()
    }

    @ViewBuilder
    private func hotKeyStatusLabel(for status: GlobalHotKeyStatus) -> some View {
        switch status {
        case .active:
            Label(L10n.string("settings.clipboard.hotkey.active"), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        case .conflict:
            Label(L10n.string("settings.clipboard.hotkey.conflict"), systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        case .inactive, .failed:
            Label(L10n.string("settings.clipboard.hotkey.inactive"), systemImage: "circle.slash")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pestaña 1: Portapapeles y General

    private var clipboardAndGeneralTab: some View {
        Form {
            Section(L10n.string("settings.language.section")) {
                LabeledContent(L10n.string("settings.language.picker.label")) {
                    Picker(L10n.string("settings.language.picker.label"), selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayTitle).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                Text(L10n.string("settings.language.restart_note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("settings.clipboard.monitoring.section")) {
                Toggle(L10n.string("settings.clipboard.monitoring.auto"), isOn: monitoringBinding)

                Toggle(L10n.string("settings.clipboard.monitoring.persist"), isOn: persistHistoryBinding)

                Toggle(L10n.string("settings.clipboard.monitoring.ignore_confidential"), isOn: ignoreConfidentialBinding)

                Text(L10n.string("settings.clipboard.monitoring.ignore_confidential.caption"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("settings.autopaste.section")) {
                Toggle(L10n.string("settings.autopaste.toggle"), isOn: autoPasteBinding)

                Text(L10n.string("settings.autopaste.caption"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent(L10n.string("settings.autopaste.accessibility_permission")) {
                    HStack(spacing: 10) {
                        Label(
                            isAccessibilityTrusted
                                ? L10n.string("settings.autopaste.permission.granted")
                                : L10n.string("settings.autopaste.permission.required"),
                            systemImage: isAccessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isAccessibilityTrusted ? .green : .orange)

                        if !isAccessibilityTrusted {
                            Button(L10n.string("settings.autopaste.open_accessibility")) {
                                autoPasteService.openAccessibilitySettings(promptIfNeeded: true)
                                refreshAccessibilityStatus()
                            }
                        }

                        Button {
                            refreshAccessibilityStatus()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help(L10n.string("settings.autopaste.check_permission.help"))
                    }
                }

                if !isAccessibilityTrusted {
                    Text(L10n.string("settings.autopaste.missing_permission.caption"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let globalHotKeyService {
                    LabeledContent(L10n.string("settings.clipboard.hotkey.title")) {
                        HStack(spacing: 8) {
                            Text(globalHotKeyService.hotKey.displayString)
                                .font(.caption.monospaced().weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.secondary.opacity(0.15))
                                )

                            hotKeyStatusLabel(for: globalHotKeyService.status)
                        }
                    }
                }
            }

            Section(L10n.string("settings.clipboard.history.section")) {
                LabeledContent(L10n.string("settings.clipboard.history.limit")) {
                    Picker(L10n.string("settings.clipboard.history.limit"), selection: maxHistoryItemsBinding) {
                        ForEach(availableHistoryLimitOptions, id: \.self) { limit in
                            Text(L10n.format("settings.clipboard.history.limit.items_count", Int64(limit))).tag(limit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                LabeledContent(L10n.string("settings.clipboard.history.maintenance")) {
                    HStack(spacing: 10) {
                        if let historyStore {
                            Text(L10n.format("settings.clipboard.history.saved_count", Int64(historyStore.items.count)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button(L10n.string("settings.clipboard.history.clear_now"), role: .destructive) {
                            isConfirmingClearHistory = true
                        }
                        .disabled(historyStore?.items.isEmpty ?? false)
                    }
                }
                .confirmationDialog(
                    L10n.string("settings.clipboard.history.clear_dialog.title"),
                    isPresented: $isConfirmingClearHistory,
                    titleVisibility: .visible
                ) {
                    Button(L10n.string("settings.clipboard.history.clear_dialog.clear_all"), role: .destructive) {
                        historyStore?.clearAll()
                    }

                    if historyStore?.items.contains(where: \.isPinned) == true {
                        Button(L10n.string("settings.clipboard.history.clear_dialog.clear_unpinned")) {
                            historyStore?.clearUnpinned()
                        }
                    }

                    Button(L10n.string("common.cancel"), role: .cancel) {}
                } message: {
                    Text(L10n.string("settings.clipboard.history.clear_dialog.message"))
                }
            }

            Section(L10n.string("settings.notch.section")) {
                LabeledContent(L10n.string("settings.notch.auto_dismiss")) {
                    HStack(spacing: 10) {
                        Slider(
                            value: promptDurationBinding,
                            in: SettingsManager.minimumPromptDuration...SettingsManager.maximumPromptDuration,
                            step: 1
                        )
                        .frame(width: 190)

                        Text(L10n.format("settings.notch.seconds_short", Int64(settings.promptAutoDismissSeconds)))
                            .font(.system(.caption, design: .monospaced))
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                Text(L10n.string("settings.notch.caption"))
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

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { settings.appLanguage },
            set: { settings.appLanguage = $0 }
        )
    }

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

    private var autoPasteBinding: Binding<Bool> {
        Binding(
            get: { settings.autoPasteOnSelect },
            set: { settings.autoPasteOnSelect = $0 }
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

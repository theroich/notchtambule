//
//  MenuBarContent.swift
//  NotchTubeAudio
//

import AppKit
import SwiftUI

/// Contents of the `MenuBarExtra` status item menu for the modular Clipboard Manager.
struct MenuBarContent: View {
    static let maxRecentItemsCount = 5

    let appState: AppState
    let historyStore: ClipboardHistoryStore
    let featureRegistry: FeatureRegistry
    let onToggleNotch: () -> Void
    let onRunCurrentClipboardAction: () -> Void

    @Environment(\.openSettings) private var openSettings

    init(environment: AppEnvironment) {
        self.appState = environment.appState
        self.historyStore = environment.historyStore
        self.featureRegistry = environment.featureRegistry
        self.onToggleNotch = {
            environment.notchController.toggleFromMenu()
        }
        self.onRunCurrentClipboardAction = {
            environment.runActionOnCurrentClipboard()
        }
    }

    init(
        appState: AppState,
        historyStore: ClipboardHistoryStore? = nil,
        featureRegistry: FeatureRegistry? = nil,
        onToggleNotch: @escaping () -> Void = {},
        onRunCurrentClipboardAction: @escaping () -> Void = {}
    ) {
        self.appState = appState
        self.historyStore = historyStore ?? appState.historyStore
        self.featureRegistry = featureRegistry ?? appState.featureRegistry
        self.onToggleNotch = onToggleNotch
        self.onRunCurrentClipboardAction = onRunCurrentClipboardAction
    }

    /// Últimos 5 elementos del historial disponibles para copia rápida con un clic.
    var recentItems: [ClipboardItem] {
        Array(historyStore.items.prefix(Self.maxRecentItemsCount))
    }

    /// Título dinámico para la acción principal de mostrar/ocultar el portapapeles en el notch.
    var toggleNotchMenuTitle: String {
        appState.notchMode != .idle
            ? "Ocultar portapapeles en el notch"
            : "Mostrar portapapeles en el notch"
    }

    var body: some View {
        Button(toggleNotchMenuTitle) {
            onToggleNotch()
        }

        Menu("Elementos recientes") {
            if recentItems.isEmpty {
                Text("Sin elementos recientes")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentItems) { item in
                    Button {
                        historyStore.copyToPasteboard(item)
                    } label: {
                        Label(
                            Self.menuItemTitle(for: item),
                            systemImage: Self.menuItemIcon(for: item)
                        )
                    }
                }
            }
        }

        Button("Ejecutar acción sobre el portapapeles actual") {
            onRunCurrentClipboardAction()
        }

        Button("Limpiar historial no fijado") {
            historyStore.clearUnpinned()
        }
        .disabled(!hasUnpinnedItems)

        Divider()

        Button("Configuración…") {
            openSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Salir") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var hasUnpinnedItems: Bool {
        historyStore.items.contains { !$0.isPinned }
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    // MARK: - Menu Item Formatting

    static func menuItemTitle(for item: ClipboardItem, maxLength: Int = 48) -> String {
        let baseTitle = item.previewTitle
        let trimmed: String
        if baseTitle.count > maxLength {
            trimmed = String(baseTitle.prefix(maxLength)) + "…"
        } else {
            trimmed = baseTitle
        }
        return item.isPinned ? "📌 \(trimmed)" : trimmed
    }

    static func menuItemIcon(for item: ClipboardItem) -> String {
        switch item.contentType {
        case .plainText:
            return "doc.text"
        case .url:
            return "link"
        case .image:
            return "photo"
        case .fileURLs:
            return "folder"
        case .colorHex:
            return "paintpalette"
        case .codeSnippet:
            return "chevron.left.forwardslash.chevron.right"
        }
    }
}

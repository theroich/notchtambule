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
            ? L10n.string("menubar.toggle_notch.hide")
            : L10n.string("menubar.toggle_notch.show")
    }

    var body: some View {
        Button(toggleNotchMenuTitle) {
            onToggleNotch()
        }

        Menu(L10n.string("menubar.recent_items")) {
            if recentItems.isEmpty {
                Text(L10n.string("menubar.recent_items.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentItems) { item in
                    Button {
                        Task { @MainActor in
                            let forceCopyOnly = NSEvent.modifierFlags.contains(.option)
                            await appState.autoPaste(item: item, forceCopyOnly: forceCopyOnly)
                        }
                    } label: {
                        Label(
                            Self.menuItemTitle(for: item),
                            systemImage: Self.menuItemIcon(for: item)
                        )
                    }
                }
            }
        }

        Button(L10n.string("menubar.run_action")) {
            onRunCurrentClipboardAction()
        }

        Button(L10n.string("menubar.clear_unpinned")) {
            historyStore.clearUnpinned()
        }
        .disabled(!hasUnpinnedItems)

        Divider()

        Button(L10n.string("menubar.settings")) {
            openSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(L10n.string("menubar.quit")) {
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

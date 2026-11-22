//
//  NotchRootView.swift
//  NotchTubeAudio
//

import SwiftUI

/// Root SwiftUI view hosted inside DynamicNotchKit.
struct NotchRootView: View {
    let appState: AppState

    var body: some View {
        Group {
            switch appState.notchMode {
            case .idle:
                Color.clear
                    .frame(width: NotchMetrics.contentWidth, height: 1)

            case .promptingFeature(let pluginID, let item):
                promptContainerView(pluginID: pluginID, item: item)

            case .showingPanel(let tab):
                panelContainerView(tab: tab)
            }
        }
        .frame(width: NotchMetrics.contentWidth)
        .foregroundStyle(.white)
        .tint(.white)
        .animation(.smooth(duration: 0.28), value: appState.notchMode)
    }

    // MARK: - Prompt Container

    @ViewBuilder
    private func promptContainerView(pluginID: String, item: ClipboardItem) -> some View {
        if let plugin = appState.featureRegistry.plugin(withID: pluginID),
           let promptView = plugin.makePromptView(
               for: item,
               context: appState.actionContext,
               onComplete: {
                   appState.completePrompt(for: pluginID)
               },
               onDismiss: {
                   appState.dismissPrompt()
               }
           ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: plugin.iconSystemName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))

                    Text(plugin.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))

                    Spacer(minLength: 0)

                    Button {
                        appState.returnToHistoryFromPrompt()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("Portapapeles")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .help("Volver al historial del portapapeles")
                }
                .padding(.horizontal, 4)

                promptView
            }
        } else {
            Color.clear
                .frame(width: NotchMetrics.contentWidth, height: 1)
        }
    }

    // MARK: - Panel Container

    private func panelContainerView(tab: NotchPanelTab) -> some View {
        let activityPlugins = appState.featureRegistry.activityPanelPlugins
        let currentTab = appState.activeTab

        return VStack(alignment: .leading, spacing: 8) {
            if !activityPlugins.isEmpty {
                NotchHeaderTabsView(
                    selectedTab: currentTab,
                    clipboardItemCount: appState.historyStore.items.count,
                    activityPlugins: activityPlugins,
                    onSelectTab: { selected in
                        appState.selectTab(selected)
                    }
                )
            }

            Group {
                switch currentTab {
                case .clipboardHistory:
                    clipboardHistoryView

                case .pluginActivity(let pluginID):
                    if let plugin = appState.featureRegistry.plugin(withID: pluginID),
                       let activityView = plugin.makeActivityPanelView(context: appState.actionContext) {
                        activityView
                    } else {
                        clipboardHistoryView
                    }
                }
            }
            .id(currentTab)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.bottom, 1)
    }

    private var clipboardHistoryView: some View {
        ClipboardHistoryView(
            store: appState.historyStore,
            featureRegistry: appState.featureRegistry,
            actionContext: appState.actionContext,
            activeNotification: appState.activeNotification,
            isAutoPasteEnabled: appState.settings.autoPasteOnSelect && appState.autoPasteService.canAutoPaste(),
            onSelectItem: { item, forceCopyOnly in
                await appState.autoPaste(item: item, forceCopyOnly: forceCopyOnly)
            }
        )
    }
}

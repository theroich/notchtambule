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

        return VStack(alignment: .leading, spacing: 8) {
            if !activityPlugins.isEmpty {
                panelNavigationBar(selectedTab: tab, activityPlugins: activityPlugins)
            }

            switch tab {
            case .clipboardHistory:
                clipboardHistorySection

            case .pluginActivity(let pluginID):
                if let plugin = appState.featureRegistry.plugin(withID: pluginID),
                   let activityView = plugin.makeActivityPanelView(context: appState.actionContext) {
                    activityView
                } else {
                    clipboardHistorySection
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 1)
    }

    private func panelNavigationBar(
        selectedTab: NotchPanelTab,
        activityPlugins: [any ClipboardFeaturePlugin]
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tabPill(
                    title: "Portapapeles",
                    iconSystemName: "doc.on.clipboard",
                    badgeCount: 0,
                    isSelected: selectedTab == .clipboardHistory
                ) {
                    appState.selectTab(.clipboardHistory)
                }

                ForEach(activityPlugins, id: \.id) { plugin in
                    let tab = NotchPanelTab.pluginActivity(pluginID: plugin.id)
                    tabPill(
                        title: plugin.displayName,
                        iconSystemName: plugin.iconSystemName,
                        badgeCount: plugin.activeTasksCount,
                        isSelected: selectedTab == tab
                    ) {
                        appState.selectTab(tab)
                    }
                }
            }
        }
    }

    private func tabPill(
        title: String,
        iconSystemName: String,
        badgeCount: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: iconSystemName)
                    .font(.system(size: 10, weight: .semibold))

                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : .black)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(
                            Capsule().fill(isSelected ? .black.opacity(0.75) : .white.opacity(0.85))
                        )
                }
            }
            .foregroundStyle(isSelected ? .black : .white.opacity(0.80))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? .white : .white.opacity(0.09))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Clipboard History View

    private var clipboardHistorySection: some View {
        let items = appState.historyStore.filteredItems

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.70))

                Text("Portapapeles")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)

                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Capsule().fill(.white.opacity(0.85)))
                }

                Spacer(minLength: 0)

                if !appState.historyStore.items.isEmpty {
                    Button {
                        appState.historyStore.clearUnpinned()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 22, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Limpiar elementos no fijados")
                }
            }

            if items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white.opacity(0.22))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Historial vacío")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.80))
                        Text("Cualquier texto, enlace, archivo o imagen que copies aparecerá aquí.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 54)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.04))
                }
            } else {
                let rows = max(items.count, 1)
                let listHeight = min(
                    CGFloat(rows) * NotchMetrics.queueRowHeight,
                    NotchMetrics.queueListMaxHeight
                )

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { item in
                            clipboardRow(for: item)
                        }
                    }
                    .padding(.trailing, 1)
                }
                .frame(height: listHeight)
            }
        }
    }

    private func clipboardRow(for item: ClipboardItem) -> some View {
        let quickActions = appState.featureRegistry.quickActions(for: item, context: appState.actionContext)

        return HStack(spacing: 8) {
            Button {
                appState.historyStore.copyToPasteboard(item)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: iconName(for: item.contentType))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.white.opacity(0.08))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.previewTitle)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let subtitle = item.previewSubtitle {
                            Text(subtitle)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white.opacity(0.50))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(quickActions) { action in
                Button {
                    action.handler()
                } label: {
                    Image(systemName: action.iconSystemName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help(action.title)
            }

            Button {
                appState.historyStore.togglePin(item.id)
            } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(item.isPinned ? .yellow : .white.opacity(0.45))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(item.isPinned ? "Desfijar" : "Fijar")

            Button {
                appState.historyStore.remove(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Eliminar")
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.05))
        }
    }

    private func iconName(for contentType: ClipboardContentType) -> String {
        switch contentType {
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

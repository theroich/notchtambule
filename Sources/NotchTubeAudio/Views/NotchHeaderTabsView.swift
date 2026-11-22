//
//  NotchHeaderTabsView.swift
//  NotchTubeAudio
//

import SwiftUI

/// Navigation header inside the expanded notch panel that allows switching between
/// the main clipboard history tab (`Portapapeles`) and any enabled plugin activity tabs
/// (`hasActivityPanel == true`, e.g., `Descargas`).
struct NotchHeaderTabsView: View {
    let selectedTab: NotchPanelTab
    let clipboardItemCount: Int
    let activityPlugins: [any ClipboardFeaturePlugin]
    let onSelectTab: (NotchPanelTab) -> Void

    var body: some View {
        HStack(spacing: 6) {
            tabPill(
                title: "Portapapeles",
                iconSystemName: "doc.on.clipboard",
                badgeCount: clipboardItemCount,
                isSelected: selectedTab == .clipboardHistory
            ) {
                onSelectTab(.clipboardHistory)
            }

            ForEach(activityPlugins, id: \.id) { plugin in
                let tab = NotchPanelTab.pluginActivity(pluginID: plugin.id)
                tabPill(
                    title: plugin.activityPanelTitle,
                    iconSystemName: plugin.iconSystemName,
                    badgeCount: plugin.activeTasksCount,
                    isSelected: selectedTab == tab
                ) {
                    onSelectTab(tab)
                }
            }
        }
        .padding(2)
        .background(
            Capsule().fill(.white.opacity(0.06))
        )
        .animation(.snappy(duration: 0.18), value: selectedTab)
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
                        .padding(.horizontal, 4.5)
                        .frame(minWidth: 15, minHeight: 14)
                        .background(
                            Capsule().fill(isSelected ? .black.opacity(0.75) : .white.opacity(0.85))
                        )
                }
            }
            .foregroundStyle(isSelected ? .black : .white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)
            .background(
                Capsule().fill(isSelected ? .white : .white.opacity(0.001))
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected ? .white.opacity(0.28) : .clear,
                        lineWidth: 1
                    )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badgeCount > 0 ? "\(title) (\(badgeCount))" : title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

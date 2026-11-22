//
//  ClipboardHistoryView.swift
//  NotchTubeAudio
//

import AppKit
import SwiftUI

/// Main notch view for the Clipboard Manager: instant search bar, category filter pills,
/// clear-unpinned action, virtualized item list (`ScrollView` + `LazyVStack`), and
/// dynamic plugin quick actions per row.
struct ClipboardHistoryView: View {
    @Bindable var store: ClipboardHistoryStore
    let featureRegistry: FeatureRegistry
    let actionContext: FeatureActionContext
    var activeNotification: FeatureUserNotification?
    var isAutoPasteEnabled: Bool = false
    var onSelectItem: (@MainActor (ClipboardItem, Bool) async -> PasteResult)? = nil

    @State private var feedbackItemID: UUID?
    @State private var feedbackState: ClipboardItemClickFeedback = .copied
    @State private var copyFeedbackTask: Task<Void, Never>?

    var body: some View {
        let filteredItems = store.filteredItems

        VStack(alignment: .leading, spacing: 7) {
            searchAndActionsHeader

            ClipboardFilterPillsView(
                selection: store.selectedFilter,
                onSelect: { filter in
                    store.selectedFilter = filter
                }
            )

            if let notification = activeNotification {
                notificationBanner(notification)
            }

            if filteredItems.isEmpty {
                emptyStateView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredItems) { item in
                            ClipboardItemRowView(
                                item: item,
                                quickActions: featureRegistry.quickActions(
                                    for: item,
                                    context: actionContext
                                ),
                                matchedPlugins: featureRegistry.matchingPlugins(for: item),
                                isCopiedFeedbackActive: feedbackItemID == item.id,
                                feedbackState: feedbackItemID == item.id ? feedbackState : .copied,
                                isAutoPasteEnabled: isAutoPasteEnabled,
                                onCopy: {
                                    handleCopy(item)
                                },
                                onTogglePin: {
                                    store.togglePin(item.id)
                                },
                                onRemove: {
                                    store.remove(item.id)
                                }
                            )
                        }
                    }
                    .padding(.trailing, 1)
                }
                .frame(height: listHeight(for: filteredItems.count))
            }
        }
    }

    // MARK: - Search & Header Bar

    private var searchAndActionsHeader: some View {
        HStack(spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))

                TextField("Buscar en el portapapeles…", text: $store.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white)

                if !store.searchQuery.isEmpty {
                    Button {
                        store.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .help("Limpiar búsqueda")
                    .accessibilityLabel("Limpiar búsqueda")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }

            if !store.filteredItems.isEmpty {
                Text("\(store.filteredItems.count)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 17)
                    .background(Capsule().fill(.white.opacity(0.85)))
                    .help("Elementos mostrados")
            }

            if hasUnpinnedItems {
                Button {
                    store.clearUnpinned()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 26, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.white.opacity(0.07))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Vaciar elementos no fijados")
                .accessibilityLabel("Vaciar elementos no fijados")
            }
        }
    }

    private var hasUnpinnedItems: Bool {
        store.items.contains { !$0.isPinned }
    }

    // MARK: - Notification Banner

    private func notificationBanner(_ notification: FeatureUserNotification) -> some View {
        HStack(spacing: 6) {
            Image(systemName: notification.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.green)

            Text(notification.message)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.green.opacity(0.14))
        )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        let isFiltering = !store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || store.selectedFilter != .all

        return HStack(spacing: 10) {
            Image(systemName: isFiltering ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))

            VStack(alignment: .leading, spacing: 2) {
                Text(isFiltering ? "Sin resultados para este filtro" : "Historial del portapapeles vacío")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))

                Text(
                    isFiltering
                        ? "Prueba con otro término de búsqueda o cambia la categoría seleccionada."
                        : "Cualquier texto, enlace, archivo o imagen que copies aparecerá aquí automáticamente."
                )
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(2)
            }

            Spacer(minLength: 0)

            if isFiltering {
                Button {
                    store.searchQuery = ""
                    store.selectedFilter = .all
                } label: {
                    Text("Restablecer")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: NotchMetrics.clipboardRowHeight)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.04))
        }
    }

    // MARK: - Helpers

    private func listHeight(for count: Int) -> CGFloat {
        let rows = max(count, 1)
        return min(
            CGFloat(rows) * NotchMetrics.clipboardRowHeight,
            NotchMetrics.queueListMaxHeight
        )
    }

    private func handleCopy(_ item: ClipboardItem) {
        let forceCopyOnly = NSEvent.modifierFlags.contains(.option)

        copyFeedbackTask?.cancel()
        let itemID = item.id

        if let onSelectItem {
            let expectedState: ClipboardItemClickFeedback = (!forceCopyOnly && isAutoPasteEnabled) ? .pasted : .copied
            withAnimation(.easeInOut(duration: 0.16)) {
                feedbackState = expectedState
                feedbackItemID = itemID
            }

            copyFeedbackTask = Task { @MainActor in
                let result = await onSelectItem(item, forceCopyOnly)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.16)) {
                    feedbackState = result.didPaste ? .pasted : .copied
                    feedbackItemID = itemID
                }

                try? await Task.sleep(for: .milliseconds(1100))
                guard !Task.isCancelled else { return }
                if feedbackItemID == itemID {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        feedbackItemID = nil
                    }
                }
            }
        } else {
            store.copyToPasteboard(item)
            withAnimation(.easeInOut(duration: 0.16)) {
                feedbackState = .copied
                feedbackItemID = itemID
            }

            copyFeedbackTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1100))
                guard !Task.isCancelled else { return }
                if feedbackItemID == itemID {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        feedbackItemID = nil
                    }
                }
            }
        }
    }
}

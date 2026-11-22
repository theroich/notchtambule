//
//  ClipboardFilterPillsView.swift
//  NotchTubeAudio
//

import SwiftUI

/// Horizontal category filter pills (`Todo`, `Texto`, `Enlaces`, `Imágenes`, `Archivos`, `Fijados 📌`)
/// styled consistently with ``FormatPills``.
struct ClipboardFilterPillsView: View {
    let selection: ClipboardContentFilter
    let onSelect: (ClipboardContentFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ClipboardContentFilter.allCases) { filter in
                    let isSelected = (filter == selection)

                    Button {
                        onSelect(filter)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filter.iconSystemName)
                                .font(.system(size: 9.5, weight: .semibold))

                            Text(pillTitle(for: filter))
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.58))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
                        .background {
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.20) : Color.white.opacity(0.05))
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isSelected ? Color.white.opacity(0.28) : Color.white.opacity(0.06),
                                    lineWidth: 1
                                )
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Filtro \(filter.displayTitle)")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 1)
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled(false)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.snappy(duration: 0.18), value: selection)
    }

    func pillTitle(for filter: ClipboardContentFilter) -> String {
        switch filter {
        case .pinned:
            return "Fijados 📌"
        default:
            return filter.displayTitle
        }
    }
}

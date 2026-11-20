//
//  DownloadQueueView.swift
//  NotchTubeAudio
//

import SwiftUI

/// Scrollable queue shown when hovering the notch.
struct DownloadQueueView: View {
    let appState: AppState

    private var manager: DownloadManager {
        appState.downloadManager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if manager.items.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(manager.items) { item in
                            DownloadRowView(
                                item: item,
                                onCancel: { manager.cancel(item) },
                                onReveal: {
                                    if let url = item.outputFileURL {
                                        FileActions.reveal(url)
                                    }
                                },
                                onRetry: { manager.retry(item) }
                            )
                        }
                    }
                    .padding(.trailing, 1)
                }
                .frame(height: listHeight)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 1)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.70))

            Text("Descargas")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)

            if manager.activeCount > 0 {
                Text("\(manager.activeCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(Capsule().fill(.white.opacity(0.85)))
                    .accessibilityLabel("\(manager.activeCount) descargas activas")
            }

            Spacer(minLength: 0)

            if manager.hasFinishedItems {
                Button {
                    manager.clearFinished()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 22, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Limpiar descargas finalizadas")
                .accessibilityLabel("Limpiar descargas finalizadas")
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white.opacity(0.22))

            VStack(alignment: .leading, spacing: 2) {
                Text("Sin descargas")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.80))
                Text("Copia un enlace de YouTube para empezar.")
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
    }

    private var listHeight: CGFloat {
        let rows = max(manager.items.count, 1)
        return min(
            CGFloat(rows) * NotchMetrics.queueRowHeight,
            NotchMetrics.queueListMaxHeight
        )
    }
}

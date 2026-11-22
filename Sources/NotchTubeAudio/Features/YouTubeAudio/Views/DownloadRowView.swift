//
//  DownloadRowView.swift
//  NotchTubeAudio
//

import SwiftUI

/// One row in the notch download queue.
struct DownloadRowView: View {
    let item: DownloadItem
    let onCancel: () -> Void
    let onReveal: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            FormatBadge(format: item.format)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 5) {
                    Text(item.statusText)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)

                    if item.status == .converting {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white.opacity(0.6))
                            .scaleEffect(0.6)
                            .frame(width: 9, height: 9)
                    }

                    Spacer(minLength: 0)
                }

                if item.status == .downloading {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .tint(.white.opacity(0.85))
                        .frame(height: 4)
                        .animation(.linear(duration: 0.2), value: item.progress)
                } else if item.status == .failed, let message = item.errorMessage {
                    Text(message)
                        .font(.system(size: 9))
                        .foregroundStyle(.red.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(message)
                } else if item.status == .queued {
                    ProgressView(value: 0)
                        .progressViewStyle(.linear)
                        .tint(.white.opacity(0.25))
                        .frame(height: 4)
                } else {
                    Spacer(minLength: 0)
                        .frame(height: 4)
                }
            }

            actionButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(height: 58)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.055))
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .queued:
            return .white.opacity(0.45)
        case .downloading, .converting:
            return .white.opacity(0.80)
        case .completed:
            return .green.opacity(0.90)
        case .failed:
            return .red.opacity(0.90)
        case .cancelled:
            return .white.opacity(0.40)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if item.canCancel {
            iconButton(systemName: "xmark.circle.fill", help: "Cancelar descarga", action: onCancel)
        } else if item.canReveal {
            iconButton(systemName: "magnifyingglass", help: "Mostrar en Finder", action: onReveal)
        } else if item.canRetry {
            iconButton(systemName: "arrow.clockwise", help: "Reintentar", action: onRetry)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green.opacity(0.85))
                .frame(width: 22, height: 22)
                .accessibilityLabel("Completado")
        }
    }

    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.70))
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// MP3 / WAV badge with a stable width so titles align.
struct FormatBadge: View {
    let format: AudioFormat

    var body: some View {
        Text(format.displayName)
            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: 30, height: 18)
            .background {
                Capsule().fill(tint.opacity(0.16))
            }
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
            .accessibilityLabel("Formato \(format.displayName)")
    }

    private var tint: Color {
        switch format {
        case .mp3:
            return .green
        case .wav:
            return .cyan
        }
    }
}

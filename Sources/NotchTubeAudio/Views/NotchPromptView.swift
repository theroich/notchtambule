//
//  NotchPromptView.swift
//  NotchTubeAudio
//

import SwiftUI

/// "New YouTube URL" prompt shown inside the notch.
struct NotchPromptView: View {
    let video: DetectedVideo
    let format: AudioFormat
    let binariesAvailable: Bool
    let onSelectFormat: (AudioFormat) -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                ThumbnailView(url: video.thumbnailURL, videoID: video.videoID)
                    .frame(width: 94, height: 70)

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        if video.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white.opacity(0.5))
                                .scaleEffect(0.7)
                                .frame(width: 9, height: 9)
                        }

                        Text(video.authorName ?? video.displayURL)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                FormatPills(selection: format, onSelect: onSelectFormat)

                if !binariesAvailable {
                    Label("Faltan yt-dlp/ffmpeg", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help("Configura las rutas de yt-dlp y ffmpeg en Ajustes")
                }

                Spacer(minLength: 4)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.70))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Cancelar")
                .accessibilityLabel("Cancelar")

                Button(action: onSave) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Guardar audio")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Descargar el audio a la carpeta configurada")
                .accessibilityLabel("Guardar audio")
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 1)
    }
}

//
//  ThumbnailView.swift
//  NotchTubeAudio
//

import SwiftUI

/// Rounded video thumbnail with a dark placeholder and a music note fallback.
struct ThumbnailView: View {
    let url: URL?
    let videoID: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let url {
                AsyncImage(
                    url: url,
                    transaction: Transaction(animation: .easeOut(duration: 0.18))
                ) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white.opacity(0.55))
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityLabel("Miniatura del vídeo")
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white.opacity(0.30))
    }
}

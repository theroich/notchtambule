//
//  NotchPromptView.swift
//  NotchTubeAudio
//

import SwiftUI

/// "New YouTube URL" prompt shown inside the notch.
struct NotchPromptView: View {
    let video: DetectedVideo
    let format: DownloadFormat
    let binariesAvailable: Bool
    let onSelectFormat: (DownloadFormat) -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    var primaryActionTitle: String {
        format.isVideo
            ? L10n.string("youtube.prompt.save_video")
            : L10n.string("youtube.prompt.save_audio")
    }

    var primaryActionHelp: String {
        format.isVideo
            ? L10n.string("youtube.prompt.save_video.help")
            : L10n.string("youtube.prompt.save_audio.help")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if !binariesAvailable {
                    Label(L10n.string("youtube.prompt.missing_binaries"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(L10n.string("youtube.prompt.missing_binaries.help"))
                } else if format.isVideo {
                    Text(L10n.string("youtube.prompt.video.quality_help"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.tail)
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
                .help(L10n.string("common.cancel"))
                .accessibilityLabel(L10n.string("common.cancel"))

                Button(action: onSave) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(primaryActionTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(primaryActionHelp)
                .accessibilityLabel(primaryActionTitle)
            }
            .frame(minHeight: 26)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 1)
    }
}

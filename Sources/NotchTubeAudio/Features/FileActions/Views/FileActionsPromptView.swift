//
//  FileActionsPromptView.swift
//  NotchTubeAudio
//

import SwiftUI

/// Confirmation and file-list prompt shown in the notch when opening more files
/// than the configured threshold.
@MainActor
struct FileActionsPromptView: View {
    let urls: [URL]
    let existingURLs: Set<URL>
    let showFullPaths: Bool
    let onOpenAll: () -> Void
    let onRevealInFinder: () -> Void
    let onCopyPaths: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.folder")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                Text(L10n.format("plugin.file_actions.prompt.title", Int64(urls.count)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(urls, id: \.path) { url in
                        let exists = existingURLs.contains(url)
                        HStack(spacing: 6) {
                            Image(systemName: exists ? "doc" : "exclamationmark.triangle")
                                .font(.system(size: 10))
                                .foregroundStyle(exists ? .white.opacity(0.65) : .orange)

                            Text(showFullPaths ? url.path : url.lastPathComponent)
                                .font(.system(size: 10.5, design: showFullPaths ? .monospaced : .default))
                                .foregroundStyle(exists ? .white.opacity(0.88) : .white.opacity(0.45))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer(minLength: 0)

                            if !exists {
                                Text(L10n.string("plugin.file_actions.prompt.missing_file"))
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 96)

            HStack(spacing: 8) {
                Button(action: onRevealInFinder) {
                    Label(L10n.string("plugin.file_actions.action.reveal"), systemImage: "folder")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Button(action: onCopyPaths) {
                    Label(L10n.string("plugin.file_actions.action.copy_paths"), systemImage: "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help(L10n.string("common.cancel"))
                .accessibilityLabel(L10n.string("common.cancel"))

                Button(action: onOpenAll) {
                    Label(L10n.string("plugin.file_actions.action.open"), systemImage: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                .disabled(existingURLs.isEmpty)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

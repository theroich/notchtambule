//
//  FormatPills.swift
//  NotchTubeAudio
//

import SwiftUI

/// Grouped Audio (MP3 / WAV) and Video (720p / 1080p) segmented pills used in
/// the YouTube detection prompt.
struct FormatPills: View {
    let selection: DownloadFormat
    let onSelect: (DownloadFormat) -> Void

    @State private var lastAudioFormat: DownloadFormat = .mp3
    @State private var lastVideoFormat: DownloadFormat = .mp4_1080p

    var body: some View {
        HStack(spacing: 6) {
            kindSelector
            formatSelector
        }
        .onAppear {
            remember(selection)
        }
        .onChange(of: selection) { _, newValue in
            remember(newValue)
        }
    }

    private var kindSelector: some View {
        HStack(spacing: 2) {
            ForEach(DownloadFormat.Kind.allCases) { kind in
                let isSelected = selection.kind == kind
                Button {
                    selectKind(kind)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: kind.iconSystemName)
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(kind.displayName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background {
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.20) : Color.clear)
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isSelected ? Color.white.opacity(0.28) : Color.clear,
                                lineWidth: 1
                            )
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.displayName)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.07)))
        .animation(.snappy(duration: 0.18), value: selection.kind)
    }

    private var formatSelector: some View {
        HStack(spacing: 2) {
            ForEach(selection.kind.formats) { format in
                let isSelected = format == selection
                Button {
                    remember(format)
                    onSelect(format)
                } label: {
                    Text(format.shortBadge)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.20) : Color.clear)
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isSelected ? Color.white.opacity(0.28) : Color.clear,
                                    lineWidth: 1
                                )
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.format("format.accessibility.label", format.displayName))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.07)))
        .animation(.snappy(duration: 0.18), value: selection)
    }

    private func selectKind(_ kind: DownloadFormat.Kind) {
        guard kind != selection.kind else { return }
        switch kind {
        case .audio:
            onSelect(lastAudioFormat)
        case .video:
            onSelect(lastVideoFormat)
        }
    }

    private func remember(_ format: DownloadFormat) {
        switch format.kind {
        case .audio:
            lastAudioFormat = format
        case .video:
            lastVideoFormat = format
        }
    }
}

//
//  FormatPills.swift
//  NotchTubeAudio
//

import SwiftUI

/// MP3 / WAV segmented pills used in the detection prompt.
struct FormatPills: View {
    let selection: AudioFormat
    let onSelect: (AudioFormat) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AudioFormat.allCases) { format in
                Button {
                    onSelect(format)
                } label: {
                    Text(format.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(format == selection ? Color.white : Color.white.opacity(0.55))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(format == selection ? Color.white.opacity(0.20) : Color.clear)
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    format == selection ? Color.white.opacity(0.28) : Color.clear,
                                    lineWidth: 1
                                )
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.format("format.accessibility.label", format.displayName))
                .accessibilityAddTraits(format == selection ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.07)))
        .animation(.snappy(duration: 0.18), value: selection)
    }
}

//
//  ClipboardItemRowView.swift
//  NotchTubeAudio
//

import AppKit
import SwiftUI

/// Rich clipboard history row rendered inside the notch.
///
/// Displays a type-aware thumbnail or icon (image preview, file icon via `NSWorkspace`,
/// plugin badge for recognized URLs, color swatch, or code/text symbol), two-line metadata
/// including relative timestamp and source application, one-click restore with visual
/// `"Copiado"` feedback, dynamic ``FeatureQuickAction`` buttons, pin toggle, and removal.
struct ClipboardItemRowView: View {
    let item: ClipboardItem
    let quickActions: [FeatureQuickAction]
    let matchedPlugins: [any ClipboardFeaturePlugin]
    let isCopiedFeedbackActive: Bool
    var feedbackState: ClipboardItemClickFeedback = .copied
    var isAutoPasteEnabled: Bool = false
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onCopy) {
                HStack(spacing: 9) {
                    leadingThumbnailOrIcon

                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 5) {
                            Text(item.previewTitle)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            if item.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(.yellow.opacity(0.90))
                            }
                        }

                        HStack(spacing: 4) {
                            Text(formattedMetadataLine)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white.opacity(0.50))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            if let primaryPlugin = matchedPlugins.first {
                                pluginBadge(for: primaryPlugin)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(rowHelpTooltip)

            trailingActions
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(height: NotchMetrics.clipboardRowHeight)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(backgroundOpacity))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isCopiedFeedbackActive
                        ? Color.green.opacity(0.45)
                        : Color.white.opacity(isHovered ? 0.14 : 0.05),
                    lineWidth: 1
                )
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundOpacity: Double {
        if isCopiedFeedbackActive {
            return 0.11
        }
        return isHovered ? 0.085 : 0.05
    }

    var rowHelpTooltip: String {
        if isAutoPasteEnabled {
            return "Clic para pegar en la app activa (⌥+Clic para solo copiar)"
        }
        return "Clic para copiar al portapapeles"
    }

    // MARK: - Leading Icon / Thumbnail

    @ViewBuilder
    private var leadingThumbnailOrIcon: some View {
        switch item.payload {
        case .image(let imagePayload):
            imageThumbnailView(for: imagePayload)

        case .files(let urls):
            fileIconView(for: urls)

        case .url:
            urlIconView

        case .text(let text):
            textIconView(for: text)
        }
    }

    @ViewBuilder
    private func imageThumbnailView(for imagePayload: ImagePayload) -> some View {
        if let nsImage = NSImage(data: imagePayload.tiffOrPngData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                }
        } else {
            iconBadge(systemName: "photo", tint: .purple)
        }
    }

    @ViewBuilder
    private func fileIconView(for urls: [URL]) -> some View {
        if let firstURL = urls.first {
            let icon = NSWorkspace.shared.icon(forFile: firstURL.path)
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.white.opacity(0.08))
                    )

                if urls.count > 1 {
                    Text("\(urls.count)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 3.5)
                        .frame(minWidth: 13, minHeight: 13)
                        .background(Capsule().fill(.white.opacity(0.92)))
                        .offset(x: 2, y: 2)
                }
            }
        } else {
            iconBadge(systemName: "folder", tint: .orange)
        }
    }

    @ViewBuilder
    private var urlIconView: some View {
        if let primaryPlugin = matchedPlugins.first {
            ZStack(alignment: .bottomTrailing) {
                iconBadge(systemName: primaryPlugin.iconSystemName, tint: .red)

                Image(systemName: "link")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(.black.opacity(0.85)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                    .offset(x: 2, y: 2)
            }
        } else {
            iconBadge(systemName: "link", tint: .blue)
        }
    }

    @ViewBuilder
    private func textIconView(for rawText: String) -> some View {
        switch item.contentType {
        case .colorHex:
            if let color = Self.parseHexColor(rawText) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color)
                    .frame(width: 34, height: 34)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    }
            } else {
                iconBadge(systemName: "paintpalette", tint: .pink)
            }

        case .codeSnippet:
            iconBadge(systemName: "chevron.left.forwardslash.chevron.right", tint: .cyan)

        default:
            iconBadge(systemName: "doc.on.clipboard", tint: .white)
        }
    }

    private func iconBadge(systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint == .white ? .white.opacity(0.78) : tint.opacity(0.92))
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint == .white ? .white.opacity(0.08) : tint.opacity(0.15))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(tint == .white ? .white.opacity(0.08) : tint.opacity(0.25), lineWidth: 1)
            }
    }

    private func pluginBadge(for plugin: any ClipboardFeaturePlugin) -> some View {
        HStack(spacing: 3) {
            Image(systemName: plugin.iconSystemName)
                .font(.system(size: 7.5, weight: .bold))
            Text(plugin.displayName)
                .font(.system(size: 8.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(
            Capsule().fill(.white.opacity(0.11))
        )
    }

    // MARK: - Trailing Actions

    @ViewBuilder
    private var trailingActions: some View {
        if isCopiedFeedbackActive {
            HStack(spacing: 4) {
                Image(systemName: feedbackState.badgeIcon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.green)

                Text(feedbackState.badgeTitle)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.green.opacity(0.16))
            )
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        } else {
            HStack(spacing: 4) {
                ForEach(quickActions) { action in
                    Button {
                        action.handler()
                    } label: {
                        Image(systemName: action.iconSystemName)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.90))
                            .frame(width: 24, height: 24)
                            .background(
                                Circle().fill(.white.opacity(0.13))
                            )
                            .overlay {
                                Circle().strokeBorder(.white.opacity(0.20), lineWidth: 0.8)
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(action.title)
                    .accessibilityLabel(action.title)
                }

                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(item.isPinned ? .yellow : .white.opacity(isHovered ? 0.72 : 0.42))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(item.isPinned ? Color.yellow.opacity(0.14) : Color.clear)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Desfijar elemento" : "Fijar elemento")
                .accessibilityLabel(item.isPinned ? "Desfijar elemento" : "Fijar elemento")

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(isHovered ? 0.72 : 0.40))
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Eliminar del historial")
                .accessibilityLabel("Eliminar del historial")
            }
        }
    }

    // MARK: - Formatting Helpers

    /// Combines `previewSubtitle` (which includes source app and domain/size/character count)
    /// with the relative capture timestamp (`hace 2 min`).
    var formattedMetadataLine: String {
        let relativeTime = Self.formatRelativeTimestamp(item.capturedAt)
        if let subtitle = item.previewSubtitle, !subtitle.isEmpty {
            return "\(subtitle) · \(relativeTime)"
        }
        return relativeTime
    }

    static func formatRelativeTimestamp(_ date: Date, relativeTo now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 5 {
            return "ahora"
        }
        return relativeDateFormatter.localizedString(for: date, relativeTo: now)
    }

    static func parseHexColor(_ raw: String) -> Color? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let hex = String(trimmed.dropFirst())

        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }

        switch hex.count {
        case 3:
            let r = Double((value >> 8) & 0xF) / 15.0
            let g = Double((value >> 4) & 0xF) / 15.0
            let b = Double(value & 0xF) / 15.0
            return Color(red: r, green: g, blue: b)
        case 6:
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            return Color(red: r, green: g, blue: b)
        case 8:
            let r = Double((value >> 24) & 0xFF) / 255.0
            let g = Double((value >> 16) & 0xFF) / 255.0
            let b = Double((value >> 8) & 0xFF) / 255.0
            let a = Double(value & 0xFF) / 255.0
            return Color(red: r, green: g, blue: b, opacity: a)
        default:
            return nil
        }
    }
}

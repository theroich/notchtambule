//
//  ColorConverterFeaturePlugin.swift
//  NotchTubeAudio
//

import Foundation
import SwiftUI

/// Representación normalizada de un color detectado en el portapapeles (componentes 0...255).
struct ParsedClipboardColor: Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int

    init(red: Int, green: Int, blue: Int, alpha: Int = 255) {
        self.red = min(max(red, 0), 255)
        self.green = min(max(green, 0), 255)
        self.blue = min(max(blue, 0), 255)
        self.alpha = min(max(alpha, 0), 255)
    }

    var hexString: String {
        if alpha < 255 {
            return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
        }
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    var rgbString: String {
        if alpha < 255 {
            let normalizedAlpha = (Double(alpha) / 255.0 * 100).rounded() / 100
            return String(format: "rgba(%d, %d, %d, %.2f)", red, green, blue, normalizedAlpha)
        }
        return "rgb(\(red), \(green), \(blue))"
    }

    var swiftUIColorString: String {
        let r = Double(red) / 255.0
        let g = Double(green) / 255.0
        let b = Double(blue) / 255.0
        if alpha < 255 {
            let a = Double(alpha) / 255.0
            return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f, opacity: %.3f)", r, g, b, a)
        }
        return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", r, g, b)
    }
}

/// Plugin integrado que detecta códigos de color en texto (`#RRGGBB`, `#RGB`, `#RRGGBBAA`, `rgb(r, g, b)`)
/// y ofrece acciones rápidas para convertirlos entre HEX, RGB y `SwiftUI Color`.
@MainActor
final class ColorConverterFeaturePlugin: ClipboardFeaturePlugin {
    static let pluginID = "com.notchclip.plugin.color-converter"

    let id: String = ColorConverterFeaturePlugin.pluginID
    var displayName: String { L10n.string("plugin.color_converter.name") }
    var summary: String { L10n.string("plugin.color_converter.summary") }
    let iconSystemName: String = "paintpalette"
    let priority: FeaturePriority = .low
    let defaultTriggerBehavior: FeatureTriggerBehavior = .historyActionOnly

    init() {}

    // MARK: - Detection

    func canHandle(_ item: ClipboardItem) -> Bool {
        Self.extractColor(from: item) != nil
    }

    // MARK: - Quick Actions

    func quickActions(for item: ClipboardItem, context: FeatureActionContext) -> [FeatureQuickAction] {
        guard let color = Self.extractColor(from: item) else { return [] }

        return [
            FeatureQuickAction(
                id: "\(id).copy-rgb.\(item.id.uuidString)",
                pluginID: id,
                title: L10n.string("plugin.color_converter.action.copy_rgb"),
                iconSystemName: "paintpalette"
            ) {
                let rgb = color.rgbString
                context.writeToClipboard(.text(rgb))
                context.notifyUser(
                    message: L10n.format("plugin.color_converter.notify.copied_as", rgb),
                    icon: "paintpalette"
                )
            },
            FeatureQuickAction(
                id: "\(id).copy-hex.\(item.id.uuidString)",
                pluginID: id,
                title: L10n.string("plugin.color_converter.action.copy_hex"),
                iconSystemName: "number"
            ) {
                let hex = color.hexString
                context.writeToClipboard(.text(hex))
                context.notifyUser(
                    message: L10n.format("plugin.color_converter.notify.copied_as", hex),
                    icon: "number"
                )
            },
            FeatureQuickAction(
                id: "\(id).copy-swiftui.\(item.id.uuidString)",
                pluginID: id,
                title: L10n.string("plugin.color_converter.action.copy_swiftui"),
                iconSystemName: "swift"
            ) {
                let swiftUI = color.swiftUIColorString
                context.writeToClipboard(.text(swiftUI))
                context.notifyUser(
                    message: L10n.string("plugin.color_converter.notify.copied_swiftui"),
                    icon: "swift"
                )
            }
        ]
    }

    // MARK: - Color Parsing

    nonisolated(unsafe) private static let hexPattern = #/^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/#
    nonisolated(unsafe) private static let rgbPattern = #/^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$/#

    static func extractColor(from item: ClipboardItem) -> ParsedClipboardColor? {
        guard case .text(let rawText) = item.payload else {
            return nil
        }
        return parseColor(rawText)
    }

    static func parseColor(_ rawText: String) -> ParsedClipboardColor? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let hexMatch = trimmed.wholeMatch(of: hexPattern) {
            return parseHexDigits(String(hexMatch.1))
        }

        let lowered = trimmed.lowercased()
        if let rgbMatch = lowered.wholeMatch(of: rgbPattern) {
            guard let r = Int(rgbMatch.1),
                  let g = Int(rgbMatch.2),
                  let b = Int(rgbMatch.3),
                  (0...255).contains(r),
                  (0...255).contains(g),
                  (0...255).contains(b) else {
                return nil
            }
            return ParsedClipboardColor(red: r, green: g, blue: b)
        }

        return nil
    }

    private static func parseHexDigits(_ digits: String) -> ParsedClipboardColor? {
        switch digits.count {
        case 3:
            let chars = Array(digits)
            guard let r = Int(String([chars[0], chars[0]]), radix: 16),
                  let g = Int(String([chars[1], chars[1]]), radix: 16),
                  let b = Int(String([chars[2], chars[2]]), radix: 16) else {
                return nil
            }
            return ParsedClipboardColor(red: r, green: g, blue: b)

        case 6:
            guard let value = UInt32(digits, radix: 16) else { return nil }
            let r = Int((value >> 16) & 0xFF)
            let g = Int((value >> 8) & 0xFF)
            let b = Int(value & 0xFF)
            return ParsedClipboardColor(red: r, green: g, blue: b)

        case 8:
            guard let value = UInt32(digits, radix: 16) else { return nil }
            let r = Int((value >> 24) & 0xFF)
            let g = Int((value >> 16) & 0xFF)
            let b = Int((value >> 8) & 0xFF)
            let a = Int(value & 0xFF)
            return ParsedClipboardColor(red: r, green: g, blue: b, alpha: a)

        default:
            return nil
        }
    }
}

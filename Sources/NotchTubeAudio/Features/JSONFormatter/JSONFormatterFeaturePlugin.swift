//
//  JSONFormatterFeaturePlugin.swift
//  NotchTubeAudio
//

import Foundation
import SwiftUI

/// Plugin integrado que detecta documentos JSON válidos (objetos `{...}` o arrays `[...]`)
/// y ofrece acciones rápidas para formatearlos con indentación o minificarlos en una sola línea.
@MainActor
final class JSONFormatterFeaturePlugin: ClipboardFeaturePlugin {
    static let pluginID = "com.notchclip.plugin.json-formatter"

    let id: String = JSONFormatterFeaturePlugin.pluginID
    let displayName: String = "Formateador JSON"
    let summary: String = "Detecta documentos JSON válidos en el portapapeles y permite formatearlos (Prettify) o compactarlos (Minify)."
    let iconSystemName: String = "curlybraces"
    let priority: FeaturePriority = .normal
    let defaultTriggerBehavior: FeatureTriggerBehavior = .historyActionOnly

    init() {}

    // MARK: - Detection

    func canHandle(_ item: ClipboardItem) -> Bool {
        guard let rawText = Self.extractCandidateText(from: item) else { return false }
        return Self.isValidJSONDocument(rawText)
    }

    // MARK: - Quick Actions

    func quickActions(for item: ClipboardItem, context: FeatureActionContext) -> [FeatureQuickAction] {
        guard let rawText = Self.extractCandidateText(from: item),
              Self.isValidJSONDocument(rawText) else {
            return []
        }

        return [
            FeatureQuickAction(
                id: "\(id).prettify.\(item.id.uuidString)",
                pluginID: id,
                title: "Prettify JSON",
                iconSystemName: "curlybraces"
            ) {
                guard let formatted = Self.prettifyJSON(rawText) else { return }
                context.writeToClipboard(.text(formatted))
                context.notifyUser(message: "JSON formateado copiado", icon: "curlybraces")
            },
            FeatureQuickAction(
                id: "\(id).minify.\(item.id.uuidString)",
                pluginID: id,
                title: "Minify JSON",
                iconSystemName: "arrow.down.right.and.arrow.up.left"
            ) {
                guard let minified = Self.minifyJSON(rawText) else { return }
                context.writeToClipboard(.text(minified))
                context.notifyUser(message: "JSON minificado copiado", icon: "arrow.down.right.and.arrow.up.left")
            }
        ]
    }

    // MARK: - JSON Parsing & Formatting

    static func extractCandidateText(from item: ClipboardItem) -> String? {
        switch item.payload {
        case .text(let text):
            return text
        default:
            return nil
        }
    }

    static func isValidJSONDocument(_ rawText: String) -> Bool {
        parseJSONObject(from: rawText) != nil
    }

    static func prettifyJSON(_ rawText: String) -> String? {
        guard let object = parseJSONObject(from: rawText),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let pretty = String(data: data, encoding: .utf8) else {
            return nil
        }
        return normalizeIndentationToTwoSpaces(pretty)
    }

    static func minifyJSON(_ rawText: String) -> String? {
        guard let object = parseJSONObject(from: rawText),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys, .withoutEscapingSlashes]
              ),
              let minified = String(data: data, encoding: .utf8) else {
            return nil
        }
        return minified
    }

    private static func parseJSONObject(from rawText: String) -> Any? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first,
              first == "{" || first == "[",
              let data = trimmed.data(using: .utf8) else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              JSONSerialization.isValidJSONObject(object) else {
            return nil
        }
        return object
    }

    /// `JSONSerialization` en Foundation utiliza múltiplos de 2 o 4 espacios según versión;
    /// normalizamos los espacios iniciales de cada línea para garantizar indentación de 2 espacios.
    private static func normalizeIndentationToTwoSpaces(_ json: String) -> String {
        let lines = json.components(separatedBy: "\n")
        let leadingCounts = lines.compactMap { line -> Int? in
            let count = line.prefix(while: { $0 == " " }).count
            return count > 0 ? count : nil
        }
        guard let minIndent = leadingCounts.min(), minIndent == 4 else {
            return json
        }

        return lines.map { line in
            let spaceCount = line.prefix(while: { $0 == " " }).count
            guard spaceCount > 0 else { return line }
            let normalizedSpaces = String(repeating: " ", count: (spaceCount / 4) * 2 + (spaceCount % 4))
            return normalizedSpaces + line.dropFirst(spaceCount)
        }.joined(separator: "\n")
    }
}

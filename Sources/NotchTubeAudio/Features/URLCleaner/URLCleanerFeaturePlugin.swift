//
//  URLCleanerFeaturePlugin.swift
//  NotchTubeAudio
//

import Foundation
import SwiftUI

/// Plugin integrado que detecta URLs con parámetros de seguimiento o analítica
/// (`utm_*`, `fbclid`, `gclid`, `igshid`, `si`, `mc_eid`, `_hsenc`, `mkt_tok`, etc.)
/// y permite limpiarlos preservando el resto de la URL.
@MainActor
final class URLCleanerFeaturePlugin: ClipboardFeaturePlugin {
    static let pluginID = "com.notchclip.plugin.url-cleaner"

    /// Nombres exactos de parámetros de tracking conocidos (en minúsculas).
    static let knownTrackingParameters: Set<String> = [
        "utm_source",
        "utm_medium",
        "utm_campaign",
        "utm_term",
        "utm_content",
        "utm_id",
        "fbclid",
        "gclid",
        "dclid",
        "msclkid",
        "twclid",
        "igshid",
        "si",
        "mc_eid",
        "mc_cid",
        "_hsenc",
        "_hsmi",
        "mkt_tok",
        "vero_id",
        "oly_enc_id",
        "oly_anon_id",
        "rb_clickid",
        "s_kwcid",
        "yclid",
        "gbraid",
        "wbraid"
    ]

    /// Prefijos de familias de parámetros de rastreo (en minúsculas).
    static let knownTrackingPrefixes: [String] = [
        "utm_",
        "hsa_"
    ]

    let id: String = URLCleanerFeaturePlugin.pluginID
    let displayName: String = "Limpiador de URLs"
    let summary: String = "Detecta parámetros de seguimiento en enlaces (utm_*, fbclid, gclid, si…) y los elimina con un clic."
    let iconSystemName: String = "sparkles"
    let priority: FeaturePriority = .normal
    let defaultTriggerBehavior: FeatureTriggerBehavior = .historyActionOnly
    let supportsPrompt: Bool = true

    init() {}

    // MARK: - Detection

    func canHandle(_ item: ClipboardItem) -> Bool {
        guard let url = Self.extractURL(from: item) else { return false }
        return Self.hasTrackingParameters(in: url)
    }

    // MARK: - Quick Actions

    func quickActions(for item: ClipboardItem, context: FeatureActionContext) -> [FeatureQuickAction] {
        guard let url = Self.extractURL(from: item),
              let result = Self.cleanTrackingParameters(from: url) else {
            return []
        }

        return [
            FeatureQuickAction(
                id: "\(id).clean.\(item.id.uuidString)",
                pluginID: id,
                title: "Limpiar URL (quitar tracking)",
                iconSystemName: "sparkles"
            ) {
                Self.applyCleanedURL(result.cleanedURL, removedCount: result.removedParameters.count, context: context)
            }
        ]
    }

    // MARK: - Prompt View (para modo .automaticPrompt opcional)

    func makePromptView(
        for item: ClipboardItem,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView? {
        guard let url = Self.extractURL(from: item),
              let result = Self.cleanTrackingParameters(from: url) else {
            return nil
        }

        return AnyView(
            URLCleanerPromptView(
                originalURL: url,
                cleanedURL: result.cleanedURL,
                removedParameters: result.removedParameters,
                onClean: {
                    Self.applyCleanedURL(result.cleanedURL, removedCount: result.removedParameters.count, context: context)
                    onComplete()
                },
                onCancel: onDismiss
            )
        )
    }

    // MARK: - URL Extraction & Cleaning

    struct CleaningResult: Equatable, Sendable {
        let cleanedURL: URL
        let removedParameters: [String]
    }

    static func extractURL(from item: ClipboardItem) -> URL? {
        switch item.payload {
        case .url(let url, _):
            return isWebURL(url) ? url : nil
        case .text(let rawText):
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.contains(where: \.isWhitespace),
                  let url = URL(string: trimmed),
                  isWebURL(url) else {
                return nil
            }
            return url
        default:
            return nil
        }
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    static func isTrackingParameter(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if knownTrackingParameters.contains(lowered) {
            return true
        }
        return knownTrackingPrefixes.contains { lowered.hasPrefix($0) }
    }

    static func hasTrackingParameters(in url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              !queryItems.isEmpty else {
            return false
        }
        return queryItems.contains { isTrackingParameter($0.name) }
    }

    static func cleanTrackingParameters(from url: URL) -> CleaningResult? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              !queryItems.isEmpty else {
            return nil
        }

        var keptItems: [URLQueryItem] = []
        var removedNames: [String] = []

        for queryItem in queryItems {
            if isTrackingParameter(queryItem.name) {
                removedNames.append(queryItem.name)
            } else {
                keptItems.append(queryItem)
            }
        }

        guard !removedNames.isEmpty else {
            return nil
        }

        components.queryItems = keptItems.isEmpty ? nil : keptItems
        guard let cleanedURL = components.url else {
            return nil
        }

        return CleaningResult(cleanedURL: cleanedURL, removedParameters: removedNames)
    }

    private static func applyCleanedURL(_ cleanURL: URL, removedCount: Int, context: FeatureActionContext) {
        context.writeToClipboard(.url(cleanURL, rawText: cleanURL.absoluteString))
        let label = removedCount == 1 ? "1 parámetro eliminado" : "\(removedCount) parámetros eliminados"
        context.notifyUser(message: "URL limpia copiada (\(label))", icon: "sparkles")
    }
}

// MARK: - Prompt View

@MainActor
private struct URLCleanerPromptView: View {
    let originalURL: URL
    let cleanedURL: URL
    let removedParameters: [String]
    let onClean: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(cleanedURL.absoluteString)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text("Se eliminarán: \(removedParameters.joined(separator: ", "))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Button(action: onClean) {
                    Label("Limpiar URL", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

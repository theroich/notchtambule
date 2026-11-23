//
//  DeveloperToolkitFeaturePlugin.swift
//  NotchTubeAudio
//

import Foundation
import SwiftUI

/// Módulo de utilidades para desarrolladores que detecta JWTs, texto Base64/Base64URL
/// y texto con percent-encoding de forma local, determinista y sin dependencias externas.
///
/// Nota: No realiza verificación criptográfica de firmas JWT ni sustituye a una librería
/// dedicada de validación de tokens.
@MainActor
final class DeveloperToolkitFeaturePlugin: ClipboardFeaturePlugin {
    static let pluginID = "com.notchclip.plugin.developer-toolkit"

    let id: String = DeveloperToolkitFeaturePlugin.pluginID
    var displayName: String { L10n.string("plugin.developer_toolkit.name") }
    var summary: String { L10n.string("plugin.developer_toolkit.summary") }
    let iconSystemName: String = "chevron.left.forwardslash.chevron.right"
    let priority: FeaturePriority = .normal
    let defaultTriggerBehavior: FeatureTriggerBehavior = .historyActionOnly
    let supportsPrompt: Bool = true

    init() {}

    // MARK: - Detection

    func canHandle(_ item: ClipboardItem) -> Bool {
        Self.detectContent(in: item) != nil
    }

    static func detectContent(in item: ClipboardItem) -> DeveloperToolkitDetectedKind? {
        guard let rawText = item.payload.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawText.isEmpty else {
            return nil
        }

        // Prioridad: JWT antes que Base64, porque los segmentos del JWT son Base64URL.
        if let jwt = JWTParser.parse(rawText) {
            return .jwt(jwt)
        }

        if case .text(let decodedBase64) = Base64Decoder.decode(rawText) {
            return .base64(decodedBase64)
        }

        if case .decoded(let decodedPercent) = PercentEncodingDecoder.decode(rawText) {
            return .percentEncoded(decodedPercent)
        }

        return nil
    }

    // MARK: - Quick Actions

    func quickActions(for item: ClipboardItem, context: FeatureActionContext) -> [FeatureQuickAction] {
        guard let detected = Self.detectContent(in: item) else {
            return []
        }

        switch detected {
        case .jwt:
            return [
                FeatureQuickAction(
                    id: "\(id).decode-jwt.\(item.id.uuidString)",
                    pluginID: id,
                    title: L10n.string("plugin.developer_toolkit.action.decode_jwt"),
                    iconSystemName: "key.viewfinder"
                ) { [id] in
                    context.presentPluginPrompt(pluginID: id, for: item)
                }
            ]

        case .base64:
            guard let rawText = item.payload.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return []
            }
            return [
                FeatureQuickAction(
                    id: "\(id).decode-base64.\(item.id.uuidString)",
                    pluginID: id,
                    title: L10n.string("plugin.developer_toolkit.action.decode_base64"),
                    iconSystemName: "text.alignleft"
                ) {
                    switch Base64Decoder.decode(rawText) {
                    case .text(let decoded):
                        context.writeToClipboard(.text(decoded))
                        context.notifyUser(
                            message: L10n.string("plugin.developer_toolkit.notify.base64_copied"),
                            icon: "checkmark.circle"
                        )
                    case .binary, .invalid:
                        context.notifyUser(
                            message: L10n.string("plugin.developer_toolkit.notify.invalid_base64"),
                            icon: "exclamationmark.triangle"
                        )
                    }
                }
            ]

        case .percentEncoded:
            guard let rawText = item.payload.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return []
            }
            return [
                FeatureQuickAction(
                    id: "\(id).decode-url.\(item.id.uuidString)",
                    pluginID: id,
                    title: L10n.string("plugin.developer_toolkit.action.decode_url"),
                    iconSystemName: "link"
                ) {
                    switch PercentEncodingDecoder.decode(rawText) {
                    case .decoded(let decoded):
                        context.writeToClipboard(.text(decoded))
                        context.notifyUser(
                            message: L10n.string("plugin.developer_toolkit.notify.url_copied"),
                            icon: "checkmark.circle"
                        )
                    case .unchanged, .invalid:
                        context.notifyUser(
                            message: L10n.string("plugin.developer_toolkit.notify.invalid_url"),
                            icon: "exclamationmark.triangle"
                        )
                    }
                }
            ]
        }
    }

    // MARK: - Prompt View (JWT)

    func makePromptView(
        for item: ClipboardItem,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView? {
        guard case .jwt(let jwt) = Self.detectContent(in: item) else {
            return nil
        }

        return AnyView(
            JWTPromptView(
                jwt: jwt,
                onCopyHeader: {
                    context.writeToClipboard(.text(jwt.formattedHeader))
                    context.notifyUser(
                        message: L10n.string("plugin.developer_toolkit.jwt.copy_header"),
                        icon: "doc.on.doc"
                    )
                },
                onCopyPayload: {
                    context.writeToClipboard(.text(jwt.formattedPayload))
                    context.notifyUser(
                        message: L10n.string("plugin.developer_toolkit.jwt.copy_payload"),
                        icon: "doc.on.doc"
                    )
                },
                onCopyAll: {
                    context.writeToClipboard(.text(jwt.formattedCombinedJSON))
                    context.notifyUser(
                        message: L10n.string("plugin.developer_toolkit.jwt.copy_all"),
                        icon: "doc.on.doc"
                    )
                },
                onClose: onDismiss
            )
        )
    }
}

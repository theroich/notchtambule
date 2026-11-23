//
//  OCRFeaturePlugin.swift
//  NotchTubeAudio
//
//  Created by NotchTubeAudio.
//

import Foundation
import SwiftUI

/// Local OCR feature plugin that detects images in clipboard history and
/// extracts selectable, copyable text using Apple's Vision framework.
@MainActor
final class OCRFeaturePlugin: ClipboardFeaturePlugin {
    static let pluginID = "com.notchclip.plugin.ocr"

    let id: String = OCRFeaturePlugin.pluginID
    var displayName: String { L10n.string("plugin.ocr.name") }
    var summary: String { L10n.string("plugin.ocr.summary") }
    let iconSystemName: String = "text.viewfinder"
    let priority: FeaturePriority = .normal
    let defaultTriggerBehavior: FeatureTriggerBehavior = .historyActionOnly
    let supportsPrompt: Bool = true

    let settingsStore: OCRSettingsStore
    private let ocrService: any OCRServicing

    init(
        settingsStore: OCRSettingsStore = OCRSettingsStore(),
        ocrService: any OCRServicing = VisionOCRService()
    ) {
        self.settingsStore = settingsStore
        self.ocrService = ocrService
    }

    // MARK: - Detection

    func canHandle(_ item: ClipboardItem) -> Bool {
        if case .image = item.payload {
            return true
        }
        return false
    }

    // MARK: - Quick Actions

    func quickActions(for item: ClipboardItem, context: FeatureActionContext) -> [FeatureQuickAction] {
        guard canHandle(item) else { return [] }

        let pluginID = id
        return [
            FeatureQuickAction(
                id: "\(id).extract.\(item.id.uuidString)",
                pluginID: pluginID,
                title: L10n.string("plugin.ocr.action.extract"),
                iconSystemName: iconSystemName
            ) {
                context.presentPluginPrompt(pluginID: pluginID, for: item)
            }
        ]
    }

    // MARK: - Prompt View

    func makePromptView(
        for item: ClipboardItem,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView? {
        guard case .image(let imagePayload) = item.payload else {
            return nil
        }

        return AnyView(
            OCRPromptView(
                imagePayload: imagePayload,
                options: settingsStore.currentOptions,
                ocrService: ocrService,
                context: context,
                onComplete: onComplete,
                onDismiss: onDismiss
            )
        )
    }

    // MARK: - Settings View

    func makeSettingsView() -> AnyView? {
        AnyView(OCRSettingsView(settingsStore: settingsStore))
    }
}

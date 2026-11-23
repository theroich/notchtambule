//
//  OCRSettingsView.swift
//  NotchTubeAudio
//
//  Created by NotchTubeAudio.
//

import SwiftUI

/// Plugin-specific preferences view for ``OCRFeaturePlugin``.
struct OCRSettingsView: View {
    let settingsStore: OCRSettingsStore

    @Environment(\.locale) private var locale
    @State private var showAllLanguages = false

    private let primaryLanguages = ["es-ES", "en-US"]
    private let availableLanguages: [String] = {
        let supported = VisionOCRService.supportedLanguages(for: .accurate)
        let prioritized = ["es-ES", "en-US", "fr-FR", "de-DE", "it-IT", "pt-BR", "ca-ES", "ja-JP", "zh-Hans"]
        var ordered: [String] = []
        var seen: Set<String> = []
        for code in prioritized where supported.contains(code) || code == "es-ES" || code == "en-US" {
            if seen.insert(code).inserted {
                ordered.append(code)
            }
        }
        for code in supported where seen.insert(code).inserted {
            ordered.append(code)
        }
        return ordered
    }()

    var body: some View {
        Section {
            LabeledContent(L10n.string("plugin.ocr.settings.recognition_level")) {
                Picker(L10n.string("plugin.ocr.settings.recognition_level"), selection: recognitionLevelBinding) {
                    Text(L10n.string("plugin.ocr.settings.level.accurate"))
                        .tag(OCRRecognitionLevel.accurate)
                    Text(L10n.string("plugin.ocr.settings.level.fast"))
                        .tag(OCRRecognitionLevel.fast)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }

            Toggle(L10n.string("plugin.ocr.settings.language_correction"), isOn: languageCorrectionBinding)

            Toggle(L10n.string("plugin.ocr.settings.preserve_line_breaks"), isOn: preserveLineBreaksBinding)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.string("plugin.ocr.settings.languages"))
                        .font(.body)

                    Spacer()

                    Button(showAllLanguages ? L10n.string("plugin.ocr.settings.languages.less") : L10n.string("plugin.ocr.settings.languages.more")) {
                        showAllLanguages.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }

                let displayedLanguages = showAllLanguages
                    ? availableLanguages
                    : availableLanguages.filter { primaryLanguages.contains($0) || settingsStore.isLanguageEnabled($0) }

                ForEach(displayedLanguages, id: \.self) { code in
                    Toggle(languageDisplayName(for: code), isOn: languageBinding(for: code))
                        .disabled(settingsStore.isLanguageEnabled(code) && settingsStore.languages.count <= 1)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Helpers

    private func languageDisplayName(for code: String) -> String {
        if let localized = locale.localizedString(forIdentifier: code), !localized.isEmpty {
            return "\(localized.localizedCapitalized) (\(code))"
        }
        return code
    }

    // MARK: - Bindings

    private var recognitionLevelBinding: Binding<OCRRecognitionLevel> {
        Binding(
            get: { settingsStore.recognitionLevel },
            set: { settingsStore.recognitionLevel = $0 }
        )
    }

    private var languageCorrectionBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.usesLanguageCorrection },
            set: { settingsStore.usesLanguageCorrection = $0 }
        )
    }

    private var preserveLineBreaksBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.preserveLineBreaks },
            set: { settingsStore.preserveLineBreaks = $0 }
        )
    }

    private func languageBinding(for code: String) -> Binding<Bool> {
        Binding(
            get: { settingsStore.isLanguageEnabled(code) },
            set: { settingsStore.setLanguage(code, enabled: $0) }
        )
    }
}

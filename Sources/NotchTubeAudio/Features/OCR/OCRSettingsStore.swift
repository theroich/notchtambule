//
//  OCRSettingsStore.swift
//  NotchTubeAudio
//
//  Created by NotchTubeAudio.
//

import Foundation
import Observation

/// Persists OCR module preferences in `UserDefaults` using module-scoped keys.
@MainActor
@Observable
final class OCRSettingsStore {
    enum Keys {
        static let languages = "notchtube.ocr.languages"
        static let recognitionLevel = "notchtube.ocr.recognitionLevel"
        static let usesLanguageCorrection = "notchtube.ocr.usesLanguageCorrection"
        static let preserveLineBreaks = "notchtube.ocr.preserveLineBreaks"
    }

    static let defaultLanguages: [String] = ["es-ES", "en-US"]

    @ObservationIgnored private let defaults: UserDefaults

    var languages: [String] {
        didSet {
            let normalized = Self.normalizeLanguages(languages)
            if normalized != languages {
                languages = normalized
                return
            }
            defaults.set(normalized, forKey: Keys.languages)
        }
    }

    var recognitionLevel: OCRRecognitionLevel {
        didSet {
            defaults.set(recognitionLevel.rawValue, forKey: Keys.recognitionLevel)
        }
    }

    var usesLanguageCorrection: Bool {
        didSet {
            defaults.set(usesLanguageCorrection, forKey: Keys.usesLanguageCorrection)
        }
    }

    var preserveLineBreaks: Bool {
        didSet {
            defaults.set(preserveLineBreaks, forKey: Keys.preserveLineBreaks)
        }
    }

    var currentOptions: OCROptions {
        OCROptions(
            languages: languages,
            recognitionLevel: recognitionLevel,
            usesLanguageCorrection: usesLanguageCorrection,
            preserveLineBreaks: preserveLineBreaks
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let savedLanguages = defaults.stringArray(forKey: Keys.languages) {
            self.languages = Self.normalizeLanguages(savedLanguages)
        } else {
            self.languages = Self.defaultLanguages
        }

        if let rawLevel = defaults.string(forKey: Keys.recognitionLevel),
           let parsedLevel = OCRRecognitionLevel(rawValue: rawLevel) {
            self.recognitionLevel = parsedLevel
        } else {
            self.recognitionLevel = .accurate
        }

        if defaults.object(forKey: Keys.usesLanguageCorrection) != nil {
            self.usesLanguageCorrection = defaults.bool(forKey: Keys.usesLanguageCorrection)
        } else {
            self.usesLanguageCorrection = true
        }

        if defaults.object(forKey: Keys.preserveLineBreaks) != nil {
            self.preserveLineBreaks = defaults.bool(forKey: Keys.preserveLineBreaks)
        } else {
            self.preserveLineBreaks = true
        }
    }

    func isLanguageEnabled(_ code: String) -> Bool {
        languages.contains(code)
    }

    func setLanguage(_ code: String, enabled: Bool) {
        if enabled {
            if !languages.contains(code) {
                languages.append(code)
            }
        } else {
            let remaining = languages.filter { $0 != code }
            if !remaining.isEmpty {
                languages = remaining
            }
        }
    }

    private static func normalizeLanguages(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        let deduplicated = raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return deduplicated.isEmpty ? defaultLanguages : deduplicated
    }
}

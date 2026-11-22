//
//  L10n.swift
//  NotchTubeAudio
//

import Foundation
import os

/// Supported application language options selectable in Settings.
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Follows the macOS preferred language (`en` when English is primary, `es` otherwise).
    case system
    /// Forces Spanish (`es`).
    case spanish = "es"
    /// Forces English (`en`).
    case english = "en"

    var id: String { rawValue }

    /// Localized title displayed in the Settings picker.
    var displayTitle: String {
        switch self {
        case .system:
            return L10n.string("settings.language.option.system")
        case .spanish:
            return L10n.string("settings.language.option.es")
        case .english:
            return L10n.string("settings.language.option.en")
        }
    }

    /// Reads the macOS global preferred languages, bypassing any per-app `AppleLanguages` override.
    static var systemPreferredLanguages: [String] {
        if let globalLanguages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String],
           !globalLanguages.isEmpty {
            return globalLanguages
        }
        return Locale.preferredLanguages
    }

    /// Resolves the effective two-letter language code (`"es"` or `"en"`).
    ///
    /// - `.spanish` -> `"es"`
    /// - `.english` -> `"en"`
    /// - `.system` -> `"en"` when the primary system language starts with `"en"`,
    ///   and `"es"` for Spanish or any other language.
    func resolvedLanguageCode(preferredLanguages: [String] = AppLanguage.systemPreferredLanguages) -> String {
        switch self {
        case .spanish:
            return "es"
        case .english:
            return "en"
        case .system:
            guard let primary = preferredLanguages.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !primary.isEmpty else {
                return "es"
            }
            if primary == "en" || primary.hasPrefix("en-") || primary.hasPrefix("en_") {
                return "en"
            }
            return "es"
        }
    }

    /// Resolves the `Locale` matching the effective language (`es` or `en`).
    func resolvedLocale(preferredLanguages: [String] = AppLanguage.systemPreferredLanguages) -> Locale {
        Locale(identifier: resolvedLanguageCode(preferredLanguages: preferredLanguages))
    }
}

/// Thread-safe localization resolver backed by `Resources/Localizable.xcstrings`
/// and compiled `.lproj` bundles inside `Bundle.module`.
enum L10n {
    /// Supported language codes in the String Catalog.
    static let supportedLanguageCodes: [String] = ["es", "en"]

    private struct RuntimeState: Sendable {
        var language: AppLanguage = .system
        var systemPreferredLanguagesOverride: [String]?
        var pseudolocalizationEnabled: Bool = false
    }

    private static let state = OSAllocatedUnfairLock(initialState: RuntimeState())
    @TaskLocal private static var taskScopedState: RuntimeState?

    /// Decoded String Catalog structure used when reading `Localizable.xcstrings` directly.
    struct CatalogDocument: Codable, Sendable {
        struct Entry: Codable, Sendable {
            struct Localization: Codable, Sendable {
                struct StringUnit: Codable, Sendable {
                    let state: String
                    let value: String
                }
                let stringUnit: StringUnit?
            }
            let extractionState: String?
            let localizations: [String: Localization]?
        }

        let sourceLanguage: String
        let strings: [String: Entry]
        let version: String
    }

    /// Preloaded catalog dictionary `[key: [languageCode: value]]` and `.lproj` bundles.
    private static let catalogTable: [String: [String: String]] = loadCatalogTable()
    private static let languageBundles: [String: Bundle] = loadLanguageBundles()

    // MARK: - Active Language Configuration

    /// Current application language preference.
    static var currentLanguage: AppLanguage {
        get {
            state.withLock { $0.language }
        }
        set {
            state.withLock { $0.language = newValue }
        }
    }

    /// Optional override for the system's preferred languages (used in deterministic tests).
    static var systemPreferredLanguagesOverride: [String]? {
        get {
            state.withLock { $0.systemPreferredLanguagesOverride }
        }
        set {
            state.withLock { $0.systemPreferredLanguagesOverride = newValue }
        }
    }

    /// Enables or disables pseudolocalization expansion (`[⟪…⟫]`) for layout overflow testing.
    static var isPseudolocalizationEnabled: Bool {
        get {
            state.withLock { $0.pseudolocalizationEnabled }
        }
        set {
            state.withLock { $0.pseudolocalizationEnabled = newValue }
        }
    }

    private static var activeState: RuntimeState {
        if let scoped = taskScopedState {
            return scoped
        }
        return state.withLock { $0 }
    }

    /// Effective language code (`"es"` or `"en"`) for the active configuration.
    static var effectiveLanguageCode: String {
        let current = activeState
        let preferred = current.systemPreferredLanguagesOverride ?? AppLanguage.systemPreferredLanguages
        return current.language.resolvedLanguageCode(preferredLanguages: preferred)
    }

    /// Effective `Locale` for the active configuration.
    static var currentLocale: Locale {
        Locale(identifier: effectiveLanguageCode)
    }

    // MARK: - String Resolution

    /// Resolves a localized string for `key` in the active language (or an explicit `languageCode`).
    static func string(_ key: String, languageCode: String? = nil) -> String {
        let resolvedCode = normalizeLanguageCode(languageCode ?? effectiveLanguageCode)
        let rawValue = rawTranslation(forKey: key, languageCode: resolvedCode)
            ?? rawTranslation(forKey: key, languageCode: "es")
            ?? key

        if activeState.pseudolocalizationEnabled {
            return pseudolocalize(rawValue)
        }
        return rawValue
    }

    /// Resolves a localized string for `key` matching a specific `Locale`.
    static func string(_ key: String, locale: Locale) -> String {
        let identifier = locale.identifier.lowercased()
        let code = (identifier == "en" || identifier.hasPrefix("en-") || identifier.hasPrefix("en_")) ? "en" : "es"
        return string(key, languageCode: code)
    }

    /// Resolves and formats a localized string template (`%lld`, `%@`, `%1$@`, etc.).
    static func format(_ key: String, languageCode: String? = nil, _ arguments: CVarArg...) -> String {
        let resolvedCode = normalizeLanguageCode(languageCode ?? effectiveLanguageCode)
        let template = string(key, languageCode: resolvedCode)
        let locale = Locale(identifier: resolvedCode)
        return String(format: template, locale: locale, arguments: arguments)
    }

    /// Formats a byte count using the active locale (e.g. `12 KB`, `1,4 MB` / `1.4 MB`).
    static func formatByteCount(_ bytes: Int, locale: Locale? = nil) -> String {
        let targetLocale = locale ?? currentLocale
        let clampedBytes = Int64(max(1024, bytes))
        let style = ByteCountFormatStyle(
            style: .file,
            allowedUnits: [.kb, .mb, .gb],
            spellsOutZero: false,
            includesActualByteCount: false,
            locale: targetLocale
        )
        return style.format(clampedBytes)
    }

    /// Executes `operation` while temporarily overriding language settings in the current task scope.
    static func withLanguage<T>(
        _ language: AppLanguage,
        systemPreferredLanguages: [String]? = nil,
        pseudolocalized: Bool = false,
        operation: () throws -> T
    ) rethrows -> T {
        var scoped = activeState
        scoped.language = language
        if let systemPreferredLanguages {
            scoped.systemPreferredLanguagesOverride = systemPreferredLanguages
        }
        scoped.pseudolocalizationEnabled = pseudolocalized
        return try $taskScopedState.withValue(scoped) {
            try operation()
        }
    }

    // MARK: - Catalog Inspection

    /// Locates the `Localizable.xcstrings` file in `Bundle.module` or the source tree.
    static func catalogURL() -> URL? {
        if let bundled = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings") {
            return bundled
        }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Localizable.xcstrings", isDirectory: false)
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            return sourceURL
        }
        return nil
    }

    /// Loads and decodes the raw `Localizable.xcstrings` catalog document.
    static func loadCatalogDocument() throws -> CatalogDocument {
        guard let url = catalogURL() else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CatalogDocument.self, from: data)
    }

    // MARK: - Private Helpers

    private static func normalizeLanguageCode(_ code: String) -> String {
        let lowered = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered == "en" || lowered.hasPrefix("en-") || lowered.hasPrefix("en_") {
            return "en"
        }
        return "es"
    }

    private static func rawTranslation(forKey key: String, languageCode: String) -> String? {
        if let catalogValue = catalogTable[key]?[languageCode], !catalogValue.isEmpty {
            return catalogValue
        }
        if let bundle = languageBundles[languageCode] {
            let sentinel = "__MISSING_KEY_\(key)__"
            let value = bundle.localizedString(forKey: key, value: sentinel, table: "Localizable")
            if value != sentinel {
                return value
            }
        }
        return nil
    }

    private static func loadCatalogTable() -> [String: [String: String]] {
        guard let document = try? loadCatalogDocument() else {
            return [:]
        }
        var table: [String: [String: String]] = [:]
        for (key, entry) in document.strings {
            var perLanguage: [String: String] = [:]
            if let localizations = entry.localizations {
                for (lang, localization) in localizations {
                    if let value = localization.stringUnit?.value {
                        perLanguage[lang] = value
                    }
                }
            }
            table[key] = perLanguage
        }
        return table
    }

    private static func loadLanguageBundles() -> [String: Bundle] {
        var result: [String: Bundle] = [:]
        for code in supportedLanguageCodes {
            if let path = Bundle.module.path(forResource: code, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                result[code] = bundle
            }
        }
        return result
    }

    /// Expands plain text while preserving format specifiers (`%@`, `%lld`, `%1$@`, `%2$lld`)
    /// so layout tests can detect clipping in narrow notch views.
    static func pseudolocalize(_ input: String) -> String {
        let map: [Character: Character] = [
            "a": "á", "e": "ë", "i": "î", "o": "ö", "u": "ü",
            "A": "Á", "E": "Ë", "I": "Î", "O": "Ö", "U": "Ü"
        ]
        var output = "⟪"
        var index = input.startIndex
        while index < input.endIndex {
            let ch = input[index]
            if ch == "%" {
                // Keep format specifiers untouched (%@, %lld, %1$@, %2$lld, %%)
                output.append(ch)
                index = input.index(after: index)
                while index < input.endIndex {
                    let specChar = input[index]
                    output.append(specChar)
                    index = input.index(after: index)
                    if specChar == "@" || specChar == "d" || specChar == "f" || specChar == "%" {
                        break
                    }
                }
                continue
            }
            output.append(map[ch] ?? ch)
            index = input.index(after: index)
        }
        output.append("⟫")
        return output
    }
}

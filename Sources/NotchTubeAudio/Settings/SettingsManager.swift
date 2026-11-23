//
//  SettingsManager.swift
//  NotchTubeAudio
//

import Foundation
import Observation

/// Persistent preferences backed by `UserDefaults`.
///
/// Every mutation is written immediately, so the Settings window, the menu bar
/// and the notch always observe the same values through the Observation
/// framework.
@MainActor
@Observable
final class SettingsManager {
    static let defaultYTDLPPath = "/opt/homebrew/bin/yt-dlp"
    static let defaultFFmpegPath = "/opt/homebrew/bin/ffmpeg"
    static let minimumPromptDuration: Double = 3
    static let maximumPromptDuration: Double = 15
    static let defaultPromptDuration: Double = 8
    static let minimumClipboardHistoryItems: Int = 10
    static let maximumClipboardHistoryItems: Int = 500
    static let defaultMaxClipboardHistoryItems: Int = 100

    private enum Key {
        static let appLanguage = "notchtube.appLanguage"
        static let appleLanguages = "AppleLanguages"
        static let downloadDirectory = "notchtube.downloadDirectory"
        static let defaultFormat = "notchtube.defaultFormat"
        static let ytDlpPath = "notchtube.ytDlpPath"
        static let ffmpegPath = "notchtube.ffmpegPath"
        static let clipboardMonitoring = "notchtube.clipboardMonitoring"
        static let ignoreConfidentialTypes = "notchtube.ignoreConfidentialTypes"
        static let maxClipboardHistoryItems = "notchtube.maxClipboardHistoryItems"
        static let persistClipboardHistory = "notchtube.persistClipboardHistory"
        static let autoPasteOnSelect = "notchtube.autoPasteOnSelect"
        static let promptDuration = "notchtube.promptDuration"
        static let pluginEnabledStates = "notchtube.pluginEnabledStates"
        static let pluginTriggerBehaviors = "notchtube.pluginTriggerBehaviors"
    }

    private let defaults: UserDefaults

    var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Key.appLanguage)
            applyLanguagePreference()
        }
    }

    var resolvedLanguageCode: String {
        appLanguage.resolvedLanguageCode()
    }

    var resolvedLocale: Locale {
        appLanguage.resolvedLocale()
    }

    var downloadDirectory: URL {
        didSet {
            defaults.set(downloadDirectory.path, forKey: Key.downloadDirectory)
        }
    }

    var defaultFormat: DownloadFormat {
        didSet {
            defaults.set(defaultFormat.rawValue, forKey: Key.defaultFormat)
        }
    }

    var ytDlpPath: String {
        didSet {
            defaults.set(ytDlpPath, forKey: Key.ytDlpPath)
        }
    }

    var ffmpegPath: String {
        didSet {
            defaults.set(ffmpegPath, forKey: Key.ffmpegPath)
        }
    }

    var isClipboardMonitoringEnabled: Bool {
        didSet {
            defaults.set(isClipboardMonitoringEnabled, forKey: Key.clipboardMonitoring)
        }
    }

    var ignoreConfidentialPasteboardTypes: Bool {
        didSet {
            defaults.set(ignoreConfidentialPasteboardTypes, forKey: Key.ignoreConfidentialTypes)
        }
    }

    var maxClipboardHistoryItems: Int {
        didSet {
            let clamped = min(
                max(maxClipboardHistoryItems, Self.minimumClipboardHistoryItems),
                Self.maximumClipboardHistoryItems
            )
            if clamped != maxClipboardHistoryItems {
                maxClipboardHistoryItems = clamped
            }
            defaults.set(maxClipboardHistoryItems, forKey: Key.maxClipboardHistoryItems)
        }
    }

    ///Alias for `maxClipboardHistoryItems` matching the Issue #2 retention policy wording.
    var maxHistoryItems: Int {
        get { maxClipboardHistoryItems }
        set { maxClipboardHistoryItems = newValue }
    }

    var persistClipboardHistory: Bool {
        didSet {
            defaults.set(persistClipboardHistory, forKey: Key.persistClipboardHistory)
        }
    }

    /// Alias for `persistClipboardHistory` matching the Issue #2 storage option wording.
    var persistHistoryAcrossLaunches: Bool {
        get { persistClipboardHistory }
        set { persistClipboardHistory = newValue }
    }

    /// Whether clicking an item in the clipboard history automatically pastes it (`⌘V`)
    /// into the previously active application when Accessibility permission is granted.
    var autoPasteOnSelect: Bool {
        didSet {
            defaults.set(autoPasteOnSelect, forKey: Key.autoPasteOnSelect)
        }
    }

    var promptAutoDismissSeconds: Double {
        didSet {
            let clamped = min(max(promptAutoDismissSeconds, Self.minimumPromptDuration), Self.maximumPromptDuration)
            if clamped != promptAutoDismissSeconds {
                promptAutoDismissSeconds = clamped
            }
            defaults.set(promptAutoDismissSeconds, forKey: Key.promptDuration)
        }
    }

    /// Persistent map of `[pluginID: isEnabled]`. Plugins omitted from this dictionary default to `true`.
    var pluginEnabledStates: [String: Bool] {
        didSet {
            defaults.set(pluginEnabledStates, forKey: Key.pluginEnabledStates)
        }
    }

    /// Persistent map of `[pluginID: FeatureTriggerBehavior]` configured by the user.
    var pluginTriggerBehaviors: [String: FeatureTriggerBehavior] {
        didSet {
            let rawDictionary = pluginTriggerBehaviors.mapValues(\.rawValue)
            defaults.set(rawDictionary, forKey: Key.pluginTriggerBehaviors)
        }
    }

    var isYTDLPAvailable: Bool {
        BinaryLocator.isExecutable(ytDlpPath)
    }

    var isFFmpegAvailable: Bool {
        BinaryLocator.isExecutable(ffmpegPath)
    }

    var areBinariesAvailable: Bool {
        isYTDLPAvailable && isFFmpegAvailable
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedLanguage = defaults.string(forKey: Key.appLanguage)
        self.appLanguage = storedLanguage.flatMap(AppLanguage.init(rawValue:)) ?? .system

        let fallbackDownloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)

        let storedDirectory = defaults.string(forKey: Key.downloadDirectory)
        self.downloadDirectory = storedDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? fallbackDownloads

        let storedFormat = defaults.string(forKey: Key.defaultFormat)
        self.defaultFormat = DownloadFormat.fromStoredValue(storedFormat)

        let storedYTDLP = defaults.string(forKey: Key.ytDlpPath)
        self.ytDlpPath = storedYTDLP ?? BinaryLocator.locate("yt-dlp") ?? Self.defaultYTDLPPath

        let storedFFmpeg = defaults.string(forKey: Key.ffmpegPath)
        self.ffmpegPath = storedFFmpeg ?? BinaryLocator.locate("ffmpeg") ?? Self.defaultFFmpegPath

        self.isClipboardMonitoringEnabled = (defaults.object(forKey: Key.clipboardMonitoring) as? Bool) ?? true
        self.ignoreConfidentialPasteboardTypes = (defaults.object(forKey: Key.ignoreConfidentialTypes) as? Bool) ?? true

        let storedMaxHistory = (defaults.object(forKey: Key.maxClipboardHistoryItems) as? Int) ?? Self.defaultMaxClipboardHistoryItems
        self.maxClipboardHistoryItems = min(
            max(storedMaxHistory, Self.minimumClipboardHistoryItems),
            Self.maximumClipboardHistoryItems
        )

        self.persistClipboardHistory = (defaults.object(forKey: Key.persistClipboardHistory) as? Bool) ?? true
        self.autoPasteOnSelect = (defaults.object(forKey: Key.autoPasteOnSelect) as? Bool) ?? true

        let storedDuration = (defaults.object(forKey: Key.promptDuration) as? Double) ?? Self.defaultPromptDuration
        self.promptAutoDismissSeconds = min(max(storedDuration, Self.minimumPromptDuration), Self.maximumPromptDuration)

        if let storedEnabled = defaults.dictionary(forKey: Key.pluginEnabledStates) as? [String: Bool] {
            self.pluginEnabledStates = storedEnabled
        } else if let rawDict = defaults.dictionary(forKey: Key.pluginEnabledStates) {
            var parsed: [String: Bool] = [:]
            for (key, value) in rawDict {
                if let boolValue = value as? Bool {
                    parsed[key] = boolValue
                } else if let numberValue = value as? NSNumber {
                    parsed[key] = numberValue.boolValue
                }
            }
            self.pluginEnabledStates = parsed
        } else {
            self.pluginEnabledStates = [:]
        }

        if let rawBehaviors = defaults.dictionary(forKey: Key.pluginTriggerBehaviors) as? [String: String] {
            var parsedBehaviors: [String: FeatureTriggerBehavior] = [:]
            for (pluginID, rawValue) in rawBehaviors {
                if let behavior = FeatureTriggerBehavior(rawValue: rawValue) {
                    parsedBehaviors[pluginID] = behavior
                }
            }
            self.pluginTriggerBehaviors = parsedBehaviors
        } else {
            self.pluginTriggerBehaviors = [:]
        }

        if defaults === UserDefaults.standard || storedLanguage != nil {
            applyLanguagePreference()
        }
    }

    /// Synchronizes `L10n.currentLanguage` and the `AppleLanguages` UserDefaults override.
    func applyLanguagePreference() {
        L10n.currentLanguage = appLanguage
        switch appLanguage {
        case .system:
            defaults.removeObject(forKey: Key.appleLanguages)
        case .spanish, .english:
            defaults.set([appLanguage.rawValue], forKey: Key.appleLanguages)
        }
    }

    // MARK: - Plugin Preferences

    /// Returns whether the plugin with `pluginID` is enabled (`true` by default if never customized).
    func isPluginEnabled(_ pluginID: String) -> Bool {
        pluginEnabledStates[pluginID] ?? true
    }

    /// Persists the enabled/disabled state for `pluginID`.
    func setPluginEnabled(_ pluginID: String, _ enabled: Bool) {
        pluginEnabledStates[pluginID] = enabled
    }

    /// Returns the stored trigger behavior for `pluginID`, or `defaultBehavior` when unset.
    func triggerBehavior(
        for pluginID: String,
        defaultBehavior: FeatureTriggerBehavior = .historyActionOnly
    ) -> FeatureTriggerBehavior {
        pluginTriggerBehaviors[pluginID] ?? defaultBehavior
    }

    /// Persists the user-selected trigger behavior for `pluginID`.
    func setTriggerBehavior(_ behavior: FeatureTriggerBehavior, for pluginID: String) {
        pluginTriggerBehaviors[pluginID] = behavior
    }

    /// Updates both binary paths to the first executable found on this Mac.
    /// - Returns: `true` when both tools were located.
    @discardableResult
    func autodetectBinaries() -> Bool {
        var foundAll = true

        if let ytDlp = BinaryLocator.locate("yt-dlp") {
            ytDlpPath = ytDlp
        } else {
            foundAll = false
        }

        if let ffmpeg = BinaryLocator.locate("ffmpeg") {
            ffmpegPath = ffmpeg
        } else {
            foundAll = false
        }

        Log.settings.info("Binary auto-detection finished (foundAll: \(foundAll))")
        return foundAll
    }
}

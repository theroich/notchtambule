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

    private enum Key {
        static let downloadDirectory = "notchtube.downloadDirectory"
        static let defaultFormat = "notchtube.defaultFormat"
        static let ytDlpPath = "notchtube.ytDlpPath"
        static let ffmpegPath = "notchtube.ffmpegPath"
        static let clipboardMonitoring = "notchtube.clipboardMonitoring"
        static let promptDuration = "notchtube.promptDuration"
    }

    private let defaults: UserDefaults

    var downloadDirectory: URL {
        didSet {
            defaults.set(downloadDirectory.path, forKey: Key.downloadDirectory)
        }
    }

    var defaultFormat: AudioFormat {
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

    var promptAutoDismissSeconds: Double {
        didSet {
            let clamped = min(max(promptAutoDismissSeconds, Self.minimumPromptDuration), Self.maximumPromptDuration)
            if clamped != promptAutoDismissSeconds {
                promptAutoDismissSeconds = clamped
            }
            defaults.set(promptAutoDismissSeconds, forKey: Key.promptDuration)
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

        let fallbackDownloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)

        let storedDirectory = defaults.string(forKey: Key.downloadDirectory)
        self.downloadDirectory = storedDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? fallbackDownloads

        let storedFormat = defaults.string(forKey: Key.defaultFormat)
        self.defaultFormat = storedFormat.flatMap(AudioFormat.init(rawValue:)) ?? .mp3

        let storedYTDLP = defaults.string(forKey: Key.ytDlpPath)
        self.ytDlpPath = storedYTDLP ?? BinaryLocator.locate("yt-dlp") ?? Self.defaultYTDLPPath

        let storedFFmpeg = defaults.string(forKey: Key.ffmpegPath)
        self.ffmpegPath = storedFFmpeg ?? BinaryLocator.locate("ffmpeg") ?? Self.defaultFFmpegPath

        self.isClipboardMonitoringEnabled = (defaults.object(forKey: Key.clipboardMonitoring) as? Bool) ?? true

        let storedDuration = (defaults.object(forKey: Key.promptDuration) as? Double) ?? Self.defaultPromptDuration
        self.promptAutoDismissSeconds = min(max(storedDuration, Self.minimumPromptDuration), Self.maximumPromptDuration)
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

        Log.settings.info("Autodetección de binarios finalizada (todo encontrado: \(foundAll))")
        return foundAll
    }
}

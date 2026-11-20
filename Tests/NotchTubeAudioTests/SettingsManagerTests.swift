//
//  SettingsManagerTests.swift
//  NotchTubeAudioTests
//

import Foundation
import Testing
@testable import NotchTubeAudio

@MainActor
struct SettingsManagerTests {
    @Test func clampsPromptDurationAndPersistsChanges() throws {
        let suiteName = "notchtube.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        #expect(settings.defaultFormat == .mp3)
        #expect(settings.promptAutoDismissSeconds == 8)

        settings.promptAutoDismissSeconds = 1
        #expect(settings.promptAutoDismissSeconds == SettingsManager.minimumPromptDuration)

        settings.promptAutoDismissSeconds = 99
        #expect(settings.promptAutoDismissSeconds == SettingsManager.maximumPromptDuration)

        settings.promptAutoDismissSeconds = 12
        settings.defaultFormat = .wav
        settings.isClipboardMonitoringEnabled = false

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.promptAutoDismissSeconds == 12)
        #expect(reloaded.defaultFormat == .wav)
        #expect(reloaded.isClipboardMonitoringEnabled == false)
    }

    @Test func validatesBinaryPaths() {
        #expect(BinaryLocator.isExecutable("/usr/bin/true"))
        #expect(!BinaryLocator.isExecutable("/usr/bin"))
        #expect(!BinaryLocator.isExecutable("/definitely/not/here"))
        #expect(!BinaryLocator.isExecutable(""))
    }
}

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

    @Test func clampsClipboardHistoryRetentionAndPersistsHistorySettings() throws {
        let suiteName = "notchtube.settings.history.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        #expect(settings.maxClipboardHistoryItems == 100)
        #expect(settings.persistClipboardHistory == true)
        #expect(settings.ignoreConfidentialPasteboardTypes == true)

        settings.maxClipboardHistoryItems = 3
        #expect(settings.maxClipboardHistoryItems == SettingsManager.minimumClipboardHistoryItems)

        settings.maxClipboardHistoryItems = 999
        #expect(settings.maxClipboardHistoryItems == SettingsManager.maximumClipboardHistoryItems)

        settings.maxClipboardHistoryItems = 75
        settings.persistClipboardHistory = false
        settings.ignoreConfidentialPasteboardTypes = false

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.maxClipboardHistoryItems == 75)
        #expect(reloaded.persistClipboardHistory == false)
        #expect(reloaded.ignoreConfidentialPasteboardTypes == false)
    }

    @Test func validatesBinaryPaths() {
        #expect(BinaryLocator.isExecutable("/usr/bin/true"))
        #expect(!BinaryLocator.isExecutable("/usr/bin"))
        #expect(!BinaryLocator.isExecutable("/definitely/not/here"))
        #expect(!BinaryLocator.isExecutable(""))
    }

    @Test func persistsPluginEnabledStatesAndTriggerBehaviors() throws {
        let suiteName = "notchtube.settings.plugins.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        let youtubeID = "com.notchclip.plugin.youtube-audio"
        let cleanerID = "com.notchclip.plugin.url-cleaner"

        #expect(settings.isPluginEnabled(youtubeID) == true)
        #expect(settings.triggerBehavior(for: youtubeID, defaultBehavior: .automaticPrompt) == .automaticPrompt)
        #expect(settings.triggerBehavior(for: cleanerID, defaultBehavior: .historyActionOnly) == .historyActionOnly)

        settings.setPluginEnabled(youtubeID, false)
        settings.setPluginEnabled(cleanerID, true)
        settings.setTriggerBehavior(.historyActionOnly, for: youtubeID)
        settings.setTriggerBehavior(.automaticPrompt, for: cleanerID)

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.isPluginEnabled(youtubeID) == false)
        #expect(reloaded.isPluginEnabled(cleanerID) == true)
        #expect(reloaded.triggerBehavior(for: youtubeID, defaultBehavior: .automaticPrompt) == .historyActionOnly)
        #expect(reloaded.triggerBehavior(for: cleanerID, defaultBehavior: .historyActionOnly) == .automaticPrompt)
    }
}

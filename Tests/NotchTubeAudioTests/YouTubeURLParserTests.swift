//
//  YouTubeURLParserTests.swift
//  NotchTubeAudioTests
//

import Foundation
import Testing
@testable import NotchTubeAudio

struct YouTubeURLParserTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com/watch?v=dQw4w9WgXcQ",
        "http://youtu.be/dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abcd1234",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=42s",
        "https://www.youtube.com/watch?list=PL123&v=dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "youtube.com/watch?v=dQw4w9WgXcQ",
        "  https://youtu.be/dQw4w9WgXcQ\n"
    ])
    func acceptsRequiredForms(_ text: String) {
        let link = YouTubeURLParser.parse(text)
        #expect(link != nil, "debería aceptar \(text)")
        #expect(link?.videoID == "dQw4w9WgXcQ")
        #expect(link?.canonicalURLString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    @Test(arguments: [
        "https://vimeo.com/123456",
        "https://www.youtube.com/watch?v=short",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ extra",
        "mira esto https://youtu.be/dQw4w9WgXcQ",
        "https://www.youtube.com/channel/UC123",
        "https://www.youtube.com/watch",
        "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQdQw4w9WgXcQ",
        "",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ\nhttps://youtu.be/dQw4w9WgXcQ"
    ])
    func rejectsInvalidInput(_ text: String) {
        #expect(YouTubeURLParser.parse(text) == nil, "no debería aceptar \(text)")
    }

    @Test func buildsOEmbedURL() {
        let oembed = YouTubeURLParser.parse("https://youtu.be/dQw4w9WgXcQ?si=x")?
            .oEmbedURL?.absoluteString ?? ""

        #expect(oembed.hasPrefix("https://www.youtube.com/oembed?"))
        #expect(oembed.contains("dQw4w9WgXcQ"))
        #expect(oembed.contains("format=json"))
    }

    @MainActor
    @Test func pluginCanHandleMatchesURLAndTextPayloadsWithValidYouTubeLinks() throws {
        let suiteName = "notchtube.ytparser.plugin.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        let plugin = YouTubeAudioFeaturePlugin(settings: settings)

        #expect(plugin.id == "com.notchclip.plugin.youtube-audio")
        #expect(plugin.displayName == "YouTube Audio")
        #expect(plugin.iconSystemName == "waveform.badge.mic")
        #expect(plugin.priority == .high)
        #expect(plugin.defaultTriggerBehavior == .automaticPrompt)

        let ytURL = try #require(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let urlItem = ClipboardItem(changeCount: 1, payload: .url(ytURL, rawText: ytURL.absoluteString))
        let textYTItem = ClipboardItem(changeCount: 2, payload: .text("https://youtu.be/dQw4w9WgXcQ"))
        let nonYTURL = try #require(URL(string: "https://example.com/watch?v=dQw4w9WgXcQ"))
        let nonYTURLItem = ClipboardItem(changeCount: 3, payload: .url(nonYTURL, rawText: nonYTURL.absoluteString))
        let plainTextItem = ClipboardItem(changeCount: 4, payload: .text("Texto normal sin enlace"))
        let filesItem = ClipboardItem(changeCount: 5, payload: .files([URL(fileURLWithPath: "/tmp/file.mp3")]))

        #expect(plugin.canHandle(urlItem) == true)
        #expect(plugin.canHandle(textYTItem) == true)
        #expect(plugin.canHandle(nonYTURLItem) == false)
        #expect(plugin.canHandle(plainTextItem) == false)
        #expect(plugin.canHandle(filesItem) == false)
    }
}

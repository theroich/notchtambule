//
//  DownloadManagerTests.swift
//  NotchTubeAudioTests
//
//  The tests replace yt-dlp with a tiny shell script so they run offline and
//  deterministically while exercising the real Process + Pipe pipeline.
//

import Foundation
import Testing
@testable import NotchTubeAudio

@MainActor
struct DownloadManagerTests {
    @Test func completesDownloadAndCapturesOutputPath() async throws {
        let context = try TestContext()
        defer { context.cleanup() }

        let manager = DownloadManager(settings: context.settings)
        let item = try manager.enqueueForTesting(title: "Fake Song", format: .mp3)

        let finished = await context.wait(timeout: 8) {
            item.status == .completed
        }
        #expect(finished, "estado: \(item.status), error: \(item.errorMessage ?? "nil")")
        #expect(item.progress == 1)
        #expect(item.outputFileURL?.lastPathComponent == "Fake Song.mp3")
        #expect(FileManager.default.fileExists(atPath: item.outputFileURL?.path ?? ""))
    }

    @Test func reportsStderrWhenProcessFails() async throws {
        let context = try TestContext(script: "#!/bin/sh\necho 'ERROR: vídeo no disponible' >&2\nexit 1\n")
        defer { context.cleanup() }

        let manager = DownloadManager(settings: context.settings)
        let item = try manager.enqueueForTesting(title: "Broken", format: .wav)

        let finished = await context.wait(timeout: 8) { item.status == .failed }
        #expect(finished)
        #expect(item.errorMessage?.contains("vídeo no disponible") == true)
    }

    @Test func cancellingMarksItemAndTerminatesProcess() async throws {
        let context = try TestContext(
            script: "#!/bin/sh\necho '  1.0%'\nwhile true; do sleep 0.2; echo '  2.0%'; done\n"
        )
        defer { context.cleanup() }

        let manager = DownloadManager(settings: context.settings)
        let item = try manager.enqueueForTesting(title: "Long", format: .mp3)

        #expect(await context.wait(timeout: 3) { item.status == .downloading })
        manager.cancel(item)

        #expect(item.status == .cancelled)
        #expect(item.canRetry)
        manager.terminateAllProcesses()
    }

    @Test func missingBinaryFailsGracefully() async throws {
        let context = try TestContext()
        defer { context.cleanup() }
        context.settings.ytDlpPath = "/definitely/not/here/yt-dlp"

        let manager = DownloadManager(settings: context.settings)
        let item = try manager.enqueueForTesting(title: "Nope", format: .mp3)

        let finished = await context.wait(timeout: 3) { item.status == .failed }
        #expect(finished)
        #expect(item.errorMessage?.contains("yt-dlp") == true)
    }

    /// YouTube returns HTTP 403 for some videos on the default player client.
    /// The manager must retry once with the embedded client and succeed.
    @Test func retriesWithFallbackClientAfter403() async throws {
        let context = try TestContext { downloads, root in
            """
            #!/bin/sh
            counter="\(root.path)/attempts"
            n=$(cat "$counter" 2>/dev/null || echo 0)
            n=$((n + 1))
            echo "$n" > "$counter"
            case "$*" in
            *player_client=web_embedded*)
                echo "  50.0%"
                echo "[ExtractAudio] Destination: \(downloads.path)/Retry.mp3"
                printf 'audio' > "\(downloads.path)/Retry.mp3"
                echo "\(downloads.path)/Retry.mp3"
                exit 0
                ;;
            *)
                echo "ERROR: unable to download video data: HTTP Error 403: Forbidden" >&2
                exit 1
                ;;
            esac
            """
        }
        defer { context.cleanup() }

        let manager = DownloadManager(settings: context.settings)
        let item = try manager.enqueueForTesting(title: "Retry", format: .mp3)

        let finished = await context.wait(timeout: 8) { item.status == .completed }
        #expect(finished, "estado: \(item.status), error: \(item.errorMessage ?? "nil")")
        #expect(item.outputFileURL?.lastPathComponent == "Retry.mp3")
        #expect(context.attempts == 2, "debe haber un único reintento")
    }

    @Test func stopsAfterOneFallbackRetry() async throws {
        let context = try TestContext { _, root in
            """
            #!/bin/sh
            counter="\(root.path)/attempts"
            n=$(cat "$counter" 2>/dev/null || echo 0)
            n=$((n + 1))
            echo "$n" > "$counter"
            echo "ERROR: unable to download video data: HTTP Error 403: Forbidden" >&2
            exit 1
            """
        }
        defer { context.cleanup() }

        let manager = DownloadManager(settings: context.settings)
        let item = try manager.enqueueForTesting(title: "Blocked", format: .mp3)

        let finished = await context.wait(timeout: 8) { item.status == .failed }
        #expect(finished)
        #expect(item.errorMessage?.contains("403") == true)
        #expect(item.errorMessage?.contains("brew upgrade yt-dlp") == true)
        #expect(context.attempts == 2, "no debe reintentar indefinidamente")
    }

    // MARK: - YouTubeAudioFeaturePlugin Integration Tests

    @Test func pluginPromptResolvesOEmbedEnqueuesDownloadAndSwitchesToActivityPanel() async throws {
        let context = try TestContext()
        defer { context.cleanup() }

        let expectedThumb = try #require(URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg"))
        let stubMetadata = StubMetadataService(
            result: YouTubeMetadata(
                title: "Fake Song",
                authorName: "Rick Astley",
                thumbnailURL: expectedThumb
            )
        )
        let manager = DownloadManager(settings: context.settings)
        let plugin = YouTubeAudioFeaturePlugin(
            settings: context.settings,
            downloadManager: manager,
            metadataService: stubMetadata
        )

        let ytURL = try #require(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let clipboardItem = ClipboardItem(
            changeCount: 1,
            payload: .url(ytURL, rawText: ytURL.absoluteString)
        )

        let actionContext = FeatureActionContext.noop
        var completed = false

        let promptView = plugin.makePromptView(
            for: clipboardItem,
            context: actionContext,
            onComplete: { completed = true },
            onDismiss: {}
        )
        #expect(promptView != nil)
        #expect(plugin.detectedVideo?.videoID == "dQw4w9WgXcQ")

        let metadataResolved = await context.wait(timeout: 3) {
            plugin.detectedVideo?.isLoading == false
        }
        #expect(metadataResolved)
        #expect(plugin.detectedVideo?.title == "Fake Song")
        #expect(plugin.detectedVideo?.authorName == "Rick Astley")
        #expect(plugin.detectedVideo?.thumbnailURL == expectedThumb)

        // User selects MP3 and presses "Guardar audio"
        plugin.promptFormat = .mp3
        plugin.confirmPromptDownload(context: actionContext) {
            completed = true
        }

        #expect(completed)
        #expect(actionContext.lastSwitchedActivityPluginID == plugin.id)
        #expect(plugin.detectedVideo == nil)
        #expect(manager.items.count == 1)

        let downloadItem = try #require(manager.items.first)
        let finished = await context.wait(timeout: 8) {
            downloadItem.status == .completed
        }
        #expect(finished, "estado: \(downloadItem.status), error: \(downloadItem.errorMessage ?? "nil")")
        #expect(downloadItem.outputFileURL?.lastPathComponent == "Fake Song.mp3")
        #expect(downloadItem.canReveal == true)
    }

    @Test func quickActionsEnqueueMP3AndWAVDirectlyFromHistory() async throws {
        let context = try TestContext()
        defer { context.cleanup() }

        let stubMetadata = StubMetadataService(
            result: YouTubeMetadata(
                title: "Fake Song",
                authorName: "Autor",
                thumbnailURL: nil
            )
        )
        let manager = DownloadManager(settings: context.settings)
        let plugin = YouTubeAudioFeaturePlugin(
            settings: context.settings,
            downloadManager: manager,
            metadataService: stubMetadata
        )

        let ytURL = try #require(URL(string: "https://youtu.be/dQw4w9WgXcQ"))
        let clipboardItem = ClipboardItem(
            changeCount: 1,
            payload: .url(ytURL, rawText: ytURL.absoluteString)
        )

        let actionContext = FeatureActionContext.noop
        let actions = plugin.quickActions(for: clipboardItem, context: actionContext)
        #expect(actions.count == 2)
        #expect(actions[0].title == "Descargar MP3")
        #expect(actions[0].iconSystemName == "arrow.down.circle")
        #expect(actions[1].title == "Descargar WAV")
        #expect(actions[1].iconSystemName == "waveform")

        // Trigger "Descargar WAV" quick action from clipboard history
        actions[1].handler()
        #expect(manager.items.count == 1)
        #expect(manager.items.first?.format == .wav)
        #expect(actionContext.lastSwitchedActivityPluginID == plugin.id)

        // Trigger "Descargar MP3" quick action
        actions[0].handler()
        #expect(manager.items.count == 2)
        #expect(manager.items.first?.format == .mp3)

        manager.terminateAllProcesses()
    }

    @Test func disablingYouTubePluginStoresURLInHistoryWithoutOpeningPromptAndTerminatesProcesses() async throws {
        let context = try TestContext(
            script: "#!/bin/sh\necho '  1.0%'\nwhile true; do sleep 0.2; echo '  2.0%'; done\n"
        )
        defer { context.cleanup() }

        let tempStorageDir = context.root.appendingPathComponent("history", isDirectory: true)
        context.settings.persistClipboardHistory = false
        let storage = ClipboardStorage(baseDirectory: tempStorageDir, debounceInterval: 0)
        let pasteboard = MockPasteboard()
        let historyStore = ClipboardHistoryStore(
            settings: context.settings,
            storage: storage,
            pasteboard: pasteboard
        )

        let manager = DownloadManager(settings: context.settings)
        let plugin = YouTubeAudioFeaturePlugin(
            settings: context.settings,
            downloadManager: manager,
            metadataService: StubMetadataService(result: nil)
        )
        let registry = FeatureRegistry(settings: context.settings, plugins: [plugin])
        let appState = AppState(
            settings: context.settings,
            historyStore: historyStore,
            featureRegistry: registry
        )

        // Start a download and verify activeTasksCount reflects DownloadManager.activeCount
        let runningItem = try manager.enqueueForTesting(title: "Running", format: .mp3)
        #expect(await context.wait(timeout: 3) { runningItem.status == .downloading })
        #expect(plugin.activeTasksCount == 1)
        #expect(plugin.hasActivityPanel == true)
        #expect(plugin.makeActivityPanelView(context: appState.actionContext) != nil)
        #expect(plugin.makeSettingsView() != nil)

        // Disable plugin in FeatureRegistry -> invokes plugin.shutdown(), terminating running processes
        registry.setPluginEnabled(plugin.id, false)
        #expect(plugin.activeTasksCount == 0)

        // Now copy a YouTube link while plugin is disabled: saved as URL in history, no prompt opened
        let ytURL = try #require(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let copiedItem = ClipboardItem(
            changeCount: 10,
            payload: .url(ytURL, rawText: ytURL.absoluteString)
        )
        appState.handleCapturedItem(copiedItem)

        #expect(historyStore.items.count == 1)
        #expect(historyStore.items.first?.contentType == .url)
        #expect(historyStore.items.first?.detectedFeatureIDs.isEmpty == true)
        #expect(appState.notchMode == .idle)
    }
}

private struct StubMetadataService: YouTubeMetadataFetching {
    let result: YouTubeMetadata?

    func metadata(for link: YouTubeLink) async -> YouTubeMetadata? {
        result
    }
}

// MARK: - Test helpers

private extension DownloadManager {
    /// Enqueues a synthetic detected video and returns the created item.
    func enqueueForTesting(title: String, format: AudioFormat) throws -> DownloadItem {
        let url = try #require(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let video = DetectedVideo(
            videoID: "dQw4w9WgXcQ",
            canonicalURL: url,
            title: title,
            authorName: "Test",
            thumbnailURL: nil,
            isLoading: false
        )
        enqueue(video: video, format: format)
        return try #require(items.first)
    }
}

@MainActor
private struct TestContext {
    let root: URL
    let settings: SettingsManager

    init(
        script: String? = nil,
        scriptBuilder: ((_ downloads: URL, _ root: URL) -> String)? = nil
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchtube-tests-\(UUID().uuidString)", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let downloads = root.appendingPathComponent("downloads", isDirectory: true)

        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        let scriptURL = bin.appendingPathComponent("yt-dlp")
        let defaultScript = """
        #!/bin/sh
        sleep 0.05
        echo "  10.0%"
        echo "  55.5%"
        echo "[ExtractAudio] Destination: \(downloads.path)/Fake Song.mp3"
        printf 'fake audio' > "\(downloads.path)/Fake Song.mp3"
        echo "\(downloads.path)/Fake Song.mp3"
        exit 0
        """
        let body = script ?? scriptBuilder?(downloads, root) ?? defaultScript

        try body.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let suiteName = "notchtube.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsManager(defaults: defaults)
        settings.ytDlpPath = scriptURL.path
        settings.ffmpegPath = "/usr/bin/true"
        settings.downloadDirectory = downloads

        self.root = root
        self.settings = settings
    }

    /// Number of times the fake yt-dlp was launched.
    var attempts: Int {
        let url = root.appendingPathComponent("attempts")
        guard
            let contents = try? String(contentsOf: url, encoding: .utf8),
            let value = Int(contents.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return 0
        }
        return value
    }

    func wait(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return condition()
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

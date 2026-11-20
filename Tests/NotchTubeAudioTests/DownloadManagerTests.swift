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

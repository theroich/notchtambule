//
//  DownloadManager.swift
//  NotchTubeAudio
//

import AppKit
import Darwin
import Foundation
import Observation

/// Serialises yt-dlp jobs, keeps at most two running at once and streams
/// progress into ``DownloadItem`` instances on the main actor.
@MainActor
@Observable
final class DownloadManager {
    private(set) var items: [DownloadItem] = []

    @ObservationIgnored private let settings: SettingsManager
    @ObservationIgnored private var running: [UUID: RunningDownload] = [:]
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var isShuttingDown = false
    /// Items that already used the alternate YouTube player client after a 403.
    @ObservationIgnored private var fallbackAttemptedItems: Set<UUID> = []

    /// Two parallel downloads keep the UI responsive without saturating the
    /// network or spawning too many ffmpeg processes.
    @ObservationIgnored private let maximumConcurrentDownloads = 2

    init(settings: SettingsManager) {
        self.settings = settings
        observeApplicationTermination()
    }

    // MARK: - Public API

    var activeItems: [DownloadItem] {
        items.filter { $0.status.isActive }
    }

    var activeCount: Int {
        items.reduce(into: 0) { count, item in
            if item.status.isActive { count += 1 }
        }
    }

    var hasFinishedItems: Bool {
        items.contains { $0.status.isFinished }
    }

    func enqueue(video: DetectedVideo, format: DownloadFormat) {
        isShuttingDown = false
        let item = DownloadItem(video: video, format: format)
        items.insert(item, at: 0)
        Log.downloads.info("Queued download \(item.id.uuidString, privacy: .public) (\(format.rawValue, privacy: .public))")
        startNextIfPossible()
    }

    /// Re-enables scheduling after the plugin is started or re-enabled.
    func resumeAcceptingDownloads() {
        isShuttingDown = false
        startNextIfPossible()
    }

    func cancel(_ item: DownloadItem) {
        guard item.status.isActive else { return }

        if item.status == .queued {
            item.status = .cancelled
            item.finishedAt = Date()
            startNextIfPossible()
            return
        }

        item.status = .cancelled
        item.finishedAt = Date()
        if let run = running.removeValue(forKey: item.id) {
            run.cancelled = true
            run.clearPipeHandlers()
            run.terminate()
        }
        Log.downloads.info("Cancelled download \(item.id.uuidString, privacy: .public)")
        startNextIfPossible()
    }

    func retry(_ item: DownloadItem) {
        guard item.canRetry else { return }
        fallbackAttemptedItems.remove(item.id)
        item.prepareForRetry()
        startNextIfPossible()
    }

    func clearFinished() {
        items.removeAll { $0.status.isFinished }
        let liveIDs = Set(items.map(\.id))
        fallbackAttemptedItems.formIntersection(liveIDs)
    }

    /// Sends SIGTERM to every running yt-dlp process. Called on app termination
    /// and when the notch controller is stopped.
    func terminateAllProcesses() {
        isShuttingDown = true
        for run in running.values {
            run.cancelled = true
            run.terminate()
        }
        running.removeAll()
        for item in items where item.status.isActive {
            item.status = .cancelled
            item.finishedAt = item.finishedAt ?? Date()
        }
        Log.downloads.info("Download processes terminated")
    }

    // MARK: - Scheduling

    private func startNextIfPossible() {
        guard !isShuttingDown else { return }
        while running.count < maximumConcurrentDownloads {
            guard let next = items.first(where: { $0.status == .queued }) else { break }
            start(next)
        }
    }

    private func start(_ item: DownloadItem) {
        let ytDlpPath = settings.ytDlpPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BinaryLocator.isExecutable(ytDlpPath) else {
            fail(item, message: L10n.format("downloads.error.ytdlp_not_found", ytDlpPath))
            return
        }

        let ffmpegPath = settings.ffmpegPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BinaryLocator.isExecutable(ffmpegPath) else {
            fail(item, message: L10n.format("downloads.error.ffmpeg_not_found", ffmpegPath))
            return
        }

        let destination = settings.downloadDirectory
        do {
            try FileActions.ensureDirectory(destination)
        } catch {
            fail(item, message: L10n.format("downloads.error.create_directory_failed", error.localizedDescription))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        process.arguments = arguments(
            for: item,
            ffmpegPath: ffmpegPath,
            destination: destination,
            useFallbackClient: fallbackAttemptedItems.contains(item.id)
        )
        process.currentDirectoryURL = destination
        process.environment = environment(ytDlpPath: ytDlpPath, ffmpegPath: ffmpegPath)
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutAccumulator = LineAccumulator()
        let stderrAccumulator = LineAccumulator()
        let itemID = item.id
        let run = RunningDownload(process: process)
        let runID = run.id

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let lines = stdoutAccumulator.append(data)
            guard !lines.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consume(lines, itemID: itemID, runID: runID, isError: false)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let lines = stderrAccumulator.append(data)
            guard !lines.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consume(lines, itemID: itemID, runID: runID, isError: true)
            }
        }

        process.terminationHandler = { finishedProcess in
            let exitCode = finishedProcess.terminationStatus
            Task { @MainActor [weak self] in
                self?.finish(itemID: itemID, runID: runID, exitCode: exitCode)
            }
        }

        item.progress = 0
        item.status = .downloading
        item.startedAt = Date()
        item.finishedAt = nil
        item.errorMessage = nil
        item.outputFileURL = nil

        running[item.id] = run

        do {
            try process.run()
            Log.downloads.info("Started yt-dlp (pid \(process.processIdentifier)) for \(item.title, privacy: .public)")
        } catch {
            if running[item.id]?.id == runID {
                running.removeValue(forKey: item.id)
            }
            run.clearPipeHandlers()
            fail(item, message: L10n.format("downloads.error.launch_failed", error.localizedDescription))
        }
    }

    // MARK: - yt-dlp command line

    private func arguments(
        for item: DownloadItem,
        ffmpegPath: String,
        destination: URL,
        useFallbackClient: Bool
    ) -> [String] {
        YTDLPCommandBuilder.arguments(
            url: item.url,
            format: item.format,
            ffmpegPath: ffmpegPath,
            destination: destination,
            useFallbackClient: useFallbackClient
        )
    }

    private func environment(ytDlpPath: String, ffmpegPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var paths: [String] = []

        for binary in [ytDlpPath, ffmpegPath] {
            let directory = URL(fileURLWithPath: binary).deletingLastPathComponent().path
            if !directory.isEmpty {
                paths.append(directory)
            }
        }
        paths.append(contentsOf: BinaryLocator.commonDirectories)

        if let existing = environment["PATH"], !existing.isEmpty {
            paths.append(existing)
        }

        environment["PATH"] = paths.joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }

    // MARK: - Output parsing

    private func consume(_ lines: [String], itemID: UUID, runID: UUID, isError: Bool) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        guard let run = running[itemID], run.id == runID else { return }
        let processingStatus: DownloadStatus = item.format.isVideo ? .merging : .converting

        for rawLine in lines {
            let line = ProcessOutputParser.normalize(rawLine)
            guard !line.isEmpty else { continue }

            if isError {
                run.noteError(line)
                continue
            }

            if let percent = ProcessOutputParser.progressPercent(from: line) {
                item.progress = min(max(percent / 100, 0), 1)
                if item.status == .queued {
                    item.status = .downloading
                }
                if !item.format.isVideo, percent >= 99.95, item.status == .downloading {
                    item.status = .converting
                }
                continue
            }

            if ProcessOutputParser.indicatesConversion(line) {
                item.status = processingStatus
                item.progress = max(item.progress, 0.99)
            }

            if let outputURL = ProcessOutputParser.outputFileURL(
                from: line,
                destination: settings.downloadDirectory,
                expectedFormat: item.format
            ) {
                item.outputFileURL = outputURL
                run.unexpectedOutputURL = nil
                if item.status == .downloading {
                    item.status = processingStatus
                }
            } else if let unexpectedURL = ProcessOutputParser.unexpectedOutputFileURL(
                from: line,
                destination: settings.downloadDirectory,
                expectedFormat: item.format
            ) {
                run.unexpectedOutputURL = unexpectedURL
            }
        }
    }

    private func finish(itemID: UUID, runID: UUID, exitCode: Int32) {
        Task { @MainActor [weak self] in
            // The last stdout/stderr chunks are dispatched to the main actor
            // independently from the termination handler. Give them a moment
            // to land before deciding between success, a 403 retry or failure.
            try? await Task.sleep(for: .milliseconds(100))
            self?.complete(itemID: itemID, runID: runID, exitCode: exitCode)
        }
    }

    private func complete(itemID: UUID, runID: UUID, exitCode: Int32) {
        guard let currentRun = running[itemID], currentRun.id == runID else {
            return
        }
        let run = running.removeValue(forKey: itemID)
        run?.clearPipeHandlers()

        defer { startNextIfPossible() }

        guard let item = items.first(where: { $0.id == itemID }) else { return }

        if item.status == .cancelled || run?.cancelled == true {
            item.status = .cancelled
            item.finishedAt = item.finishedAt ?? Date()
            return
        }

        if exitCode == 0 {
            if item.outputFileURL == nil {
                item.outputFileURL = locateOutputFile(for: item)
            }

            if item.outputFileURL == nil, let unexpectedURL = run?.unexpectedOutputURL {
                let message = L10n.format(
                    "downloads.error.unexpected_container",
                    unexpectedURL.pathExtension.uppercased(),
                    item.format.fileExtension.uppercased()
                )
                fail(item, message: message)
                return
            }

            item.progress = 1
            item.status = .completed
            item.finishedAt = Date()

            if item.outputFileURL == nil {
                Log.downloads.error("yt-dlp finished successfully but output file could not be resolved")
            } else {
                Log.downloads.info("Download completed: \(item.outputFileURL?.lastPathComponent ?? "", privacy: .public)")
            }
        } else {
            let message = run?.lastError
                ?? L10n.format("downloads.error.exit_code", Int64(exitCode))

            if Self.isForbiddenError(message), !fallbackAttemptedItems.contains(itemID) {
                // Some videos are blocked for the default YouTube client with
                // HTTP 403 (outdated yt-dlp / PO tokens). Retry once with the
                // embedded client instead of failing the job outright.
                fallbackAttemptedItems.insert(itemID)
                item.status = .queued
                item.progress = 0
                item.startedAt = nil
                item.finishedAt = nil
                item.outputFileURL = nil
                item.errorMessage = nil
                Log.downloads.notice("HTTP 403 detected; retrying with web_embedded client")
            } else {
                item.status = .failed
                item.finishedAt = Date()
                item.errorMessage = Self.friendlyErrorMessage(from: message)
                Log.downloads.error("Download failed (\(exitCode)): \(message, privacy: .public)")
            }
        }
    }

    private static func isForbiddenError(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("403: forbidden")
            || lowercased.contains("http error 403")
            || lowercased.contains("forbidden")
    }

    private static func friendlyErrorMessage(from message: String) -> String {
        if isForbiddenError(message) {
            return L10n.string("downloads.error.http_403")
        }
        return message
    }

    private func fail(_ item: DownloadItem, message: String) {
        item.status = .failed
        item.errorMessage = message
        item.finishedAt = Date()
        Log.downloads.error("\(message, privacy: .public)")
    }

    /// Fallback used when the `after_move:filepath` line could not be parsed.
    func locateOutputFile(for item: DownloadItem) -> URL? {
        let directory = settings.downloadDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let extensionName = item.format.fileExtension
        let since = (item.startedAt ?? item.createdAt).addingTimeInterval(-5)
        let title = item.title
        let normalizedTitle = Self.normalizedTitleForMatching(title)
        let expectedResolutionTag = item.format.maxVideoHeight.map { "[\($0)p]" }

        var matchingTitleAndResolution: [(url: URL, date: Date)] = []
        var matchingTitle: [(url: URL, date: Date)] = []
        var recent: [(url: URL, date: Date)] = []

        for url in contents where url.pathExtension.lowercased() == extensionName {
            guard
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                let modified = values.contentModificationDate,
                modified >= since
            else { continue }

            let fileTitle = url.deletingPathExtension().lastPathComponent
            let normalizedFileTitle = Self.normalizedTitleForMatching(fileTitle)
            let matchesTitle = fileTitle.localizedCaseInsensitiveContains(title)
                || title.localizedCaseInsensitiveContains(fileTitle)
                || (!normalizedTitle.isEmpty && (
                    normalizedFileTitle.localizedCaseInsensitiveContains(normalizedTitle)
                    || normalizedTitle.localizedCaseInsensitiveContains(normalizedFileTitle)
                ))

            if matchesTitle {
                if let tag = expectedResolutionTag,
                   fileTitle.localizedCaseInsensitiveContains(tag) {
                    matchingTitleAndResolution.append((url, modified))
                }
                matchingTitle.append((url, modified))
            } else {
                recent.append((url, modified))
            }
        }

        if let best = matchingTitleAndResolution.max(by: { $0.date < $1.date }) {
            return best.url
        }
        if let best = matchingTitle.max(by: { $0.date < $1.date }) {
            return best.url
        }
        // With a single recent candidate there is no ambiguity.
        if recent.count == 1 {
            return recent[0].url
        }
        return nil
    }

    /// Strips filesystem-substituted punctuation (`/`, `:`, `⧸`, `：`, `\\`, `|`, `?`, `*`)
    /// so sanitized yt-dlp filenames still match titles containing special characters.
    private static func normalizedTitleForMatching(_ value: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/:\\|?*\"<>⧸：_")
        let pieces = value.components(separatedBy: disallowed)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return pieces.joined(separator: " ")
    }

    // MARK: - Termination

    private func observeApplicationTermination() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.terminateAllProcesses()
            }
        }
    }
}

// MARK: - RunningDownload

/// Book-keeping for a live `Process`. Main-actor isolated: the underlying
/// `Process` is only touched from the main actor apart from its own handlers.
@MainActor
private final class RunningDownload {
    let id = UUID()
    let process: Process
    var cancelled = false
    var unexpectedOutputURL: URL?
    private var errorLines: [String] = []

    init(process: Process) {
        self.process = process
    }

    var lastError: String? {
        ProcessOutputParser.meaningfulError(from: errorLines)
    }

    func noteError(_ line: String) {
        errorLines.append(line)
        if errorLines.count > 12 {
            errorLines.removeFirst(errorLines.count - 12)
        }
    }

    func clearPipeHandlers() {
        if let pipe = process.standardOutput as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        if let pipe = process.standardError as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    func terminate() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()

        // SIGTERM is usually enough, but do not leave orphaned ffmpeg
        // processes behind if yt-dlp ignores it.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if self.process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }
}

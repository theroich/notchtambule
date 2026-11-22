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

    func enqueue(video: DetectedVideo, format: AudioFormat) {
        isShuttingDown = false
        let item = DownloadItem(video: video, format: format)
        items.insert(item, at: 0)
        Log.downloads.info("Encolada descarga \(item.id.uuidString, privacy: .public) (\(format.rawValue, privacy: .public))")
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
        if let run = running[item.id] {
            run.cancelled = true
            run.terminate()
        }
        Log.downloads.info("Cancelada descarga \(item.id.uuidString, privacy: .public)")
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
        Log.downloads.info("Procesos de descarga terminados")
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
            fail(item, message: "No se encontró yt-dlp en “\(ytDlpPath)”.")
            return
        }

        let ffmpegPath = settings.ffmpegPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BinaryLocator.isExecutable(ffmpegPath) else {
            fail(item, message: "No se encontró ffmpeg en “\(ffmpegPath)”.")
            return
        }

        let destination = settings.downloadDirectory
        do {
            try FileActions.ensureDirectory(destination)
        } catch {
            fail(item, message: "No se pudo crear la carpeta de destino: \(error.localizedDescription)")
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

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let lines = stdoutAccumulator.append(data)
            guard !lines.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consume(lines, itemID: itemID, isError: false)
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
                self?.consume(lines, itemID: itemID, isError: true)
            }
        }

        process.terminationHandler = { finishedProcess in
            let exitCode = finishedProcess.terminationStatus
            Task { @MainActor [weak self] in
                self?.finish(itemID: itemID, exitCode: exitCode)
            }
        }

        item.progress = 0
        item.status = .downloading
        item.startedAt = Date()
        item.finishedAt = nil
        item.errorMessage = nil
        item.outputFileURL = nil

        let run = RunningDownload(process: process)
        running[item.id] = run

        do {
            try process.run()
            Log.downloads.info("Iniciado yt-dlp (pid \(process.processIdentifier)) para \(item.title, privacy: .public)")
        } catch {
            running.removeValue(forKey: item.id)
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            fail(item, message: "No se pudo ejecutar yt-dlp: \(error.localizedDescription)")
        }
    }

    // MARK: - yt-dlp command line

    private func arguments(
        for item: DownloadItem,
        ffmpegPath: String,
        destination: URL,
        useFallbackClient: Bool
    ) -> [String] {
        let outputTemplate = destination
            .appendingPathComponent("%(title)s.%(ext)s")
            .path

        var arguments = [
            "--newline",
            "--no-playlist",
            // --print implies --quiet; restore the normal log stream so the
            // [ExtractAudio] phase can be detected, then force progress.
            "--print", "after_move:filepath",
            "--no-quiet",
            "--progress",
            "--no-colors",
            "-x",
            "--audio-format", item.format.rawValue,
            "--audio-quality", "0",
            "--ffmpeg-location", ffmpegPath,
            "--progress-template", "download:%(progress._percent_str)s",
            "-o", outputTemplate
        ]

        if useFallbackClient {
            // YouTube frequently blocks the default client with HTTP 403 on
            // certain videos. The embedded web client does not require a GVS
            // PO token and is a reliable audio fallback.
            arguments += ["--extractor-args", "youtube:player_client=web_embedded"]
        }

        arguments.append(item.url.absoluteString)
        return arguments
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

    private func consume(_ lines: [String], itemID: UUID, isError: Bool) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        guard let run = running[itemID] else { return }

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
                if percent >= 99.95, item.status == .downloading {
                    item.status = .converting
                }
                continue
            }

            if ProcessOutputParser.indicatesConversion(line) {
                item.status = .converting
                item.progress = max(item.progress, 0.99)
                continue
            }

            if let outputURL = ProcessOutputParser.outputFileURL(from: line, destination: settings.downloadDirectory) {
                item.outputFileURL = outputURL
                if item.status == .downloading {
                    item.status = .converting
                }
            }
        }
    }

    private func finish(itemID: UUID, exitCode: Int32) {
        Task { @MainActor [weak self] in
            // The last stdout/stderr chunks are dispatched to the main actor
            // independently from the termination handler. Give them a moment
            // to land before deciding between success, a 403 retry or failure.
            try? await Task.sleep(for: .milliseconds(100))
            self?.complete(itemID: itemID, exitCode: exitCode)
        }
    }

    private func complete(itemID: UUID, exitCode: Int32) {
        let run = running.removeValue(forKey: itemID)
        if let run {
            if let pipe = run.process.standardOutput as? Pipe {
                pipe.fileHandleForReading.readabilityHandler = nil
            }
            if let pipe = run.process.standardError as? Pipe {
                pipe.fileHandleForReading.readabilityHandler = nil
            }
        }

        defer { startNextIfPossible() }

        guard let item = items.first(where: { $0.id == itemID }) else { return }

        if item.status == .cancelled || run?.cancelled == true {
            item.status = .cancelled
            item.finishedAt = item.finishedAt ?? Date()
            return
        }

        if exitCode == 0 {
            item.progress = 1
            item.status = .completed
            item.finishedAt = Date()

            if item.outputFileURL == nil {
                item.outputFileURL = locateOutputFile(for: item)
            }
            if item.outputFileURL == nil {
                Log.downloads.error("yt-dlp terminó correctamente pero no se pudo resolver el archivo final")
            } else {
                Log.downloads.info("Descarga completada: \(item.outputFileURL?.lastPathComponent ?? "", privacy: .public)")
            }
        } else {
            let message = run?.lastError
                ?? "yt-dlp terminó con código \(exitCode)."

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
                Log.downloads.notice("HTTP 403 detectado; reintentando con el cliente web_embedded")
            } else {
                item.status = .failed
                item.finishedAt = Date()
                item.errorMessage = Self.friendlyErrorMessage(from: message)
                Log.downloads.error("Descarga fallida (\(exitCode)): \(message, privacy: .public)")
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
            return "HTTP 403: YouTube bloqueó la descarga. Actualiza yt-dlp con «brew upgrade yt-dlp» e inténtalo de nuevo."
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
    private func locateOutputFile(for item: DownloadItem) -> URL? {
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

        var matchingTitle: [(url: URL, date: Date)] = []
        var recent: [(url: URL, date: Date)] = []

        for url in contents where url.pathExtension.lowercased() == extensionName {
            guard
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                let modified = values.contentModificationDate,
                modified >= since
            else { continue }

            let fileTitle = url.deletingPathExtension().lastPathComponent
            if fileTitle.localizedCaseInsensitiveContains(title)
                || title.localizedCaseInsensitiveContains(fileTitle) {
                matchingTitle.append((url, modified))
            } else {
                recent.append((url, modified))
            }
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
    let process: Process
    var cancelled = false
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

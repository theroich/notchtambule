//
//  YouTubeAudioSettingsView.swift
//  NotchTubeAudio
//

import AppKit
import SwiftUI

/// Plugin-specific preferences view for `YouTubeAudioFeaturePlugin`
/// (destination folder, default MP3/WAV format, and yt-dlp / ffmpeg paths).
struct YouTubeAudioSettingsView: View {
    let settings: SettingsManager

    @State private var detectionMessage: String?
    @State private var detectionSucceeded = false

    var body: some View {
        Group {
            Section(L10n.string("notch.tab.downloads")) {
                LabeledContent(L10n.string("youtube.settings.destination_folder")) {
                    HStack(spacing: 8) {
                        Text(settings.downloadDirectory.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: 280, alignment: .trailing)

                        Button(L10n.string("youtube.settings.change_folder")) {
                            chooseDownloadFolder()
                        }

                        Button {
                            FileActions.openFolder(settings.downloadDirectory)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help(L10n.string("youtube.settings.open_in_finder.help"))
                    }
                }

                LabeledContent(L10n.string("youtube.settings.default_format")) {
                    Picker(L10n.string("youtube.settings.default_format"), selection: defaultFormatBinding) {
                        ForEach(AudioFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            Section(L10n.string("youtube.settings.tools.section")) {
                binaryRow(
                    title: "yt-dlp",
                    path: ytDlpBinding,
                    isAvailable: settings.isYTDLPAvailable
                )

                binaryRow(
                    title: "ffmpeg",
                    path: ffmpegBinding,
                    isAvailable: settings.isFFmpegAvailable
                )

                HStack(spacing: 10) {
                    Button(L10n.string("youtube.settings.tools.autodetect")) {
                        autodetect()
                    }

                    if let detectionMessage {
                        Text(detectionMessage)
                            .font(.caption)
                            .foregroundStyle(detectionSucceeded ? .green : .orange)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }

                Text(L10n.string("youtube.settings.tools.caption"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Rows

    private func binaryRow(title: String, path: Binding<String>, isAvailable: Bool) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField("", text: path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .labelsHidden()
                    .frame(minWidth: 260)

                Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isAvailable ? .green : .red)
                    .help(
                        isAvailable
                            ? L10n.string("youtube.settings.binary.valid.help")
                            : L10n.string("youtube.settings.binary.missing.help")
                    )
                    .accessibilityLabel(
                        isAvailable
                            ? L10n.string("youtube.settings.binary.valid.help")
                            : L10n.string("youtube.settings.binary.missing.accessibility")
                    )

                Button(L10n.string("youtube.settings.binary.choose")) {
                    chooseExecutable(for: path)
                }
            }
        }
    }

    // MARK: - Bindings

    private var defaultFormatBinding: Binding<AudioFormat> {
        Binding(
            get: { settings.defaultFormat },
            set: { settings.defaultFormat = $0 }
        )
    }

    private var ytDlpBinding: Binding<String> {
        Binding(
            get: { settings.ytDlpPath },
            set: { settings.ytDlpPath = $0 }
        )
    }

    private var ffmpegBinding: Binding<String> {
        Binding(
            get: { settings.ffmpegPath },
            set: { settings.ffmpegPath = $0 }
        )
    }

    // MARK: - Panels

    private func chooseDownloadFolder() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = L10n.string("youtube.settings.panel.folder.title")
        panel.prompt = L10n.string("youtube.settings.panel.choose_prompt")
        panel.message = L10n.string("youtube.settings.panel.folder.message")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.downloadDirectory

        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadDirectory = url
        }
    }

    private func chooseExecutable(for path: Binding<String>) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = L10n.string("youtube.settings.panel.executable.title")
        panel.prompt = L10n.string("youtube.settings.panel.choose_prompt")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

        let currentPath = path.wrappedValue
        if !currentPath.isEmpty {
            let directory = URL(fileURLWithPath: currentPath).deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: directory.path) {
                panel.directoryURL = directory
            }
        }

        if panel.runModal() == .OK, let url = panel.url {
            path.wrappedValue = url.path
        }
    }

    // MARK: - Actions

    private func autodetect() {
        let foundAll = settings.autodetectBinaries()
        detectionSucceeded = foundAll
        detectionMessage = foundAll
            ? L10n.string("youtube.settings.autodetect.success")
            : L10n.string("youtube.settings.autodetect.failure")
    }
}

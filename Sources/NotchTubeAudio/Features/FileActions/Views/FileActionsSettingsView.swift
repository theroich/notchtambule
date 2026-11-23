//
//  FileActionsSettingsView.swift
//  NotchTubeAudio
//

import SwiftUI

/// Plugin-specific preferences view for ``FileActionsFeaturePlugin``.
@MainActor
struct FileActionsSettingsView: View {
    let plugin: FileActionsFeaturePlugin

    var body: some View {
        Section(L10n.string("plugin.file_actions.name")) {
            Picker(L10n.string("plugin.file_actions.settings.terminal_app"), selection: terminalAppBinding) {
                ForEach(FileActionsTerminalApp.allCases) { app in
                    Text(app.displayName).tag(app)
                }
            }

            Stepper(
                value: confirmManyFilesBinding,
                in: 0...25
            ) {
                HStack {
                    Text(L10n.string("plugin.file_actions.settings.confirm_many_files"))
                    Spacer()
                    Text(
                        plugin.confirmManyFilesThreshold == 0
                            ? L10n.string("plugin.file_actions.settings.confirm_many_files.off")
                            : "\(plugin.confirmManyFilesThreshold)"
                    )
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }

            Toggle(L10n.string("plugin.file_actions.settings.show_full_paths"), isOn: showFullPathsBinding)
        }
    }

    private var terminalAppBinding: Binding<FileActionsTerminalApp> {
        Binding(
            get: { plugin.terminalApp },
            set: { plugin.terminalApp = $0 }
        )
    }

    private var confirmManyFilesBinding: Binding<Int> {
        Binding(
            get: { plugin.confirmManyFilesThreshold },
            set: { plugin.confirmManyFilesThreshold = $0 }
        )
    }

    private var showFullPathsBinding: Binding<Bool> {
        Binding(
            get: { plugin.showFullPathsInPrompt },
            set: { plugin.showFullPathsInPrompt = $0 }
        )
    }
}

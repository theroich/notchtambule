//
//  NotchRootView.swift
//  NotchTubeAudio
//

import SwiftUI

/// Root SwiftUI view hosted inside DynamicNotchKit.
struct NotchRootView: View {
    let appState: AppState

    var body: some View {
        Group {
            switch appState.notchMode {
            case .idle:
                Color.clear
                    .frame(width: NotchMetrics.contentWidth, height: 1)

            case .promptingURL:
                if let video = appState.detectedVideo {
                    NotchPromptView(
                        video: video,
                        format: appState.promptFormat,
                        binariesAvailable: appState.settings.areBinariesAvailable,
                        onSelectFormat: { format in
                            appState.promptFormat = format
                        },
                        onSave: {
                            appState.savePrompt(format: appState.promptFormat)
                        },
                        onCancel: {
                            appState.dismissPrompt()
                        }
                    )
                } else {
                    Color.clear
                        .frame(width: NotchMetrics.contentWidth, height: 1)
                }

            case .showingDownloads:
                DownloadQueueView(appState: appState)
            }
        }
        .frame(width: NotchMetrics.contentWidth)
        .foregroundStyle(.white)
        .tint(.white)
        .animation(.smooth(duration: 0.28), value: appState.notchMode)
    }
}

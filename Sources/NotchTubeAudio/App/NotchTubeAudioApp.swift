//
//  NotchTubeAudioApp.swift
//  NotchTubeAudio
//

import SwiftUI

@main
struct NotchTubeAudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let environment = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(environment: environment)
        } label: {
            Image(systemName: environment.menuBarIconSystemName)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(environment: environment)
        }
    }
}

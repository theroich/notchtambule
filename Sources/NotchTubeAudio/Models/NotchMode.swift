//
//  NotchMode.swift
//  NotchTubeAudio
//

import Foundation

/// The three mutually exclusive states of the notch interface.
enum NotchMode: Equatable, Sendable {
    /// Nothing is presented in the notch.
    case idle

    /// A freshly detected YouTube link is being offered to the user.
    case promptingURL

    /// The download queue / progress list is presented.
    case showingDownloads
}

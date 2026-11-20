//
//  DownloadStatus.swift
//  NotchTubeAudio
//

import Foundation

/// Lifecycle of a single download job.
enum DownloadStatus: String, Equatable, Hashable, Sendable {
    case queued
    case downloading
    case converting
    case completed
    case failed
    case cancelled

    /// `true` while the job still owns a slot in the download queue.
    var isActive: Bool {
        switch self {
        case .queued, .downloading, .converting:
            return true
        case .completed, .failed, .cancelled:
            return false
        }
    }

    var isFinished: Bool {
        !isActive
    }
}

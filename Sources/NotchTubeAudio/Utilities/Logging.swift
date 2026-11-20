//
//  Logging.swift
//  NotchTubeAudio
//

import Foundation
import os

/// Centralised `os.Logger` instances (visible in Console.app / `log stream`).
enum Log {
    private static let subsystem = "com.notchtube.audio"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
    static let metadata = Logger(subsystem: subsystem, category: "metadata")
    static let downloads = Logger(subsystem: subsystem, category: "downloads")
    static let notch = Logger(subsystem: subsystem, category: "notch")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}

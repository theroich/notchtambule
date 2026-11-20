//
//  LineAccumulator.swift
//  NotchTubeAudio
//

import Foundation

/// Converts arbitrary `FileHandle` chunks into complete lines.
///
/// `readabilityHandler` is called on a private queue, sometimes with a partial
/// line or with several lines at once. The lock makes the accumulator safe to
/// use from that queue while the parsed lines are forwarded to the main actor.
final class LineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let maximumBufferSize = 1_048_576

    /// Appends a chunk and returns every complete line it completed.
    func append(_ chunk: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(chunk)

        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = Data(buffer[buffer.startIndex..<newlineIndex])
            buffer.removeSubrange(buffer.startIndex...newlineIndex)

            if let string = String(data: lineData, encoding: .utf8) {
                lines.append(string)
            }
        }

        if buffer.count > maximumBufferSize {
            buffer.removeAll(keepingCapacity: true)
        }

        return lines
    }

    /// Returns the trailing partial line, if any.
    func flush() -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard !buffer.isEmpty else { return nil }
        let data = buffer
        buffer.removeAll(keepingCapacity: true)
        return String(data: data, encoding: .utf8)
    }
}

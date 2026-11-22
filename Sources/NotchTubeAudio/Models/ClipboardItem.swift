//
//  ClipboardItem.swift
//  NotchTubeAudio
//

import Foundation

/// Metadata identifying the application that was frontmost when a clipboard item was captured.
struct ClipboardSourceApp: Equatable, Sendable, Codable {
    let bundleIdentifier: String?
    let localizedName: String?

    init(bundleIdentifier: String?, localizedName: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}

/// A universal clipboard entry captured by ``ClipboardMonitor``.
struct ClipboardItem: Identifiable, Equatable, Sendable, Codable {
    private static let maxPreviewLength = 120

    let id: UUID
    let capturedAt: Date
    let changeCount: Int
    let payload: ClipboardPayload
    let sourceApp: ClipboardSourceApp?
    var isPinned: Bool
    var detectedFeatureIDs: [String]

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        changeCount: Int,
        payload: ClipboardPayload,
        sourceApp: ClipboardSourceApp? = nil,
        isPinned: Bool = false,
        detectedFeatureIDs: [String] = []
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.changeCount = changeCount
        self.payload = payload
        self.sourceApp = sourceApp
        self.isPinned = isPinned
        self.detectedFeatureIDs = detectedFeatureIDs
    }

    /// Semantic content category of this item.
    var contentType: ClipboardContentType {
        payload.contentType
    }

    /// Deterministic hash used for deduplicating consecutive or historical copies.
    var contentHash: String {
        payload.contentHash
    }

    /// Single-line title suitable for list rows and compact notch views.
    var previewTitle: String {
        switch payload {
        case .text(let text):
            let collapsed = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            guard !collapsed.isEmpty else {
                return "Texto vacío"
            }
            if collapsed.count <= Self.maxPreviewLength {
                return collapsed
            }
            return String(collapsed.prefix(Self.maxPreviewLength)) + "…"

        case .url(let url, let rawText):
            if let host = url.host, !host.isEmpty {
                let path = url.path == "/" ? "" : url.path
                let query = url.query.map { "?\($0)" } ?? ""
                let combined = "\(host)\(path)\(query)"
                if combined.count <= Self.maxPreviewLength {
                    return combined
                }
                return String(combined.prefix(Self.maxPreviewLength)) + "…"
            }
            return rawText.isEmpty ? url.absoluteString : rawText

        case .files(let urls):
            guard let first = urls.first else {
                return "Archivos"
            }
            if urls.count == 1 {
                return first.lastPathComponent
            }
            return "\(first.lastPathComponent) y \(urls.count - 1) más"

        case .image(let image):
            let w = Int(image.width.rounded())
            let h = Int(image.height.rounded())
            if w > 0, h > 0 {
                return "Imagen (\(w)×\(h))"
            }
            return "Imagen"
        }
    }

    /// Secondary descriptive text (source app, domain, file count, or byte size).
    var previewSubtitle: String? {
        var parts: [String] = []

        if let appName = sourceApp?.localizedName, !appName.isEmpty {
            parts.append(appName)
        } else if let bundleID = sourceApp?.bundleIdentifier, !bundleID.isEmpty {
            parts.append(bundleID)
        }

        switch payload {
        case .text(let text):
            parts.append("\(text.count) caracteres")
        case .url(let url, _):
            if let host = url.host, !host.isEmpty {
                parts.append(host)
            }
        case .files(let urls):
            if urls.count == 1, let first = urls.first {
                parts.append(first.deletingLastPathComponent().lastPathComponent)
            } else if urls.count > 1 {
                parts.append("\(urls.count) archivos")
            }
        case .image(let image):
            let kb = max(1, image.tiffOrPngData.count / 1024)
            parts.append("\(kb) KB")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

//
//  ClipboardPayload.swift
//  NotchTubeAudio
//

import AppKit
import CoreGraphics
import CryptoKit
import Foundation

/// High-level semantic category of a clipboard entry.
enum ClipboardContentType: String, Codable, Sendable, CaseIterable {
    case plainText
    case url
    case image
    case fileURLs
    case colorHex
    case codeSnippet
}

/// Image data and metadata captured from the system pasteboard.
struct ImagePayload: Equatable, Sendable, Codable {
    let width: Double
    let height: Double
    let tiffOrPngData: Data
    let sha256Hash: String

    var size: CGSize {
        CGSize(width: width, height: height)
    }

    init(size: CGSize, tiffOrPngData: Data, sha256Hash: String? = nil) {
        self.width = Double(size.width)
        self.height = Double(size.height)
        self.tiffOrPngData = tiffOrPngData
        self.sha256Hash = sha256Hash ?? Self.computeSHA256(for: tiffOrPngData)
    }

    /// Initializes an `ImagePayload` extracting pixel/point dimensions from `NSImage` or `CGImageSource`.
    init?(data: Data) {
        guard !data.isEmpty else { return nil }
        let dimensions = Self.extractDimensions(from: data) ?? .zero
        self.init(
            size: dimensions,
            tiffOrPngData: data,
            sha256Hash: Self.computeSHA256(for: data)
        )
    }

    static func computeSHA256(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func extractDimensions(from data: Data) -> CGSize? {
        if let bitmap = NSBitmapImageRep(data: data),
           bitmap.pixelsWide > 0,
           bitmap.pixelsHigh > 0 {
            return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }
        if let image = NSImage(data: data),
           image.size.width > 0,
           image.size.height > 0 {
            return image.size
        }
        return nil
    }
}

/// Typed content stored inside a ``ClipboardItem``.
enum ClipboardPayload: Equatable, Sendable, Codable {
    case text(String)
    case url(URL, rawText: String)
    case files([URL])
    case image(ImagePayload)

    /// Semantic content type inferred from the payload.
    var contentType: ClipboardContentType {
        switch self {
        case .text(let string):
            if Self.looksLikeColorHex(string) {
                return .colorHex
            }
            if Self.looksLikeCodeSnippet(string) {
                return .codeSnippet
            }
            return .plainText
        case .url:
            return .url
        case .files:
            return .fileURLs
        case .image:
            return .image
        }
    }

    /// Deterministic hash used to deduplicate consecutive identical copies.
    var contentHash: String {
        switch self {
        case .text(let text):
            return "text:" + Self.sha256(text)
        case .url(let url, _):
            return "url:" + Self.sha256(url.absoluteString)
        case .files(let urls):
            let normalized = urls
                .map { $0.standardizedFileURL.path }
                .joined(separator: "\n")
            return "files:" + Self.sha256(normalized)
        case .image(let image):
            return "image:" + image.sha256Hash
        }
    }

    /// Plain string representation if the payload carries text or a URL.
    var stringValue: String? {
        switch self {
        case .text(let text):
            return text
        case .url(let url, let rawText):
            return rawText.isEmpty ? url.absoluteString : rawText
        case .files(let urls):
            return urls.map(\.path).joined(separator: "\n")
        case .image:
            return nil
        }
    }

    private static func sha256(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated(unsafe) private static let hexColorPattern = #/^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/#

    private static func looksLikeColorHex(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.wholeMatch(of: hexColorPattern) != nil
    }

    private static func looksLikeCodeSnippet(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("\n") else { return false }
        let codeIndicators = ["func ", "let ", "var ", "const ", "import ", "class ", "struct ", "def ", "return ", "{", "}", "=>", "->"]
        return codeIndicators.contains { trimmed.contains($0) }
    }
}

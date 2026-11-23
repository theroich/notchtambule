//
//  VisionOCRService.swift
//  NotchTubeAudio
//
//  Created by NotchTubeAudio.
//

import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Local, offline OCR service backed by Apple's Vision framework (`VNRecognizeTextRequest`).
struct VisionOCRService: OCRServicing {
    /// Curated fallback list of common BCP-47 language tags supported by Vision.
    static let defaultSupportedLanguages: [String] = [
        "es-ES",
        "en-US",
        "fr-FR",
        "de-DE",
        "it-IT",
        "pt-BR",
        "ca-ES",
        "ja-JP",
        "zh-Hans"
    ]

    init() {}

    /// Returns the recognition languages supported by Vision on the current macOS version.
    static func supportedLanguages(for level: OCRRecognitionLevel = .accurate) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level == .accurate ? .accurate : .fast
        if let languages = try? request.supportedRecognitionLanguages(), !languages.isEmpty {
            return languages
        }
        return defaultSupportedLanguages
    }

    func recognizeText(
        in imageData: Data,
        options: OCROptions
    ) async throws -> OCRResult {
        guard !imageData.isEmpty else {
            throw OCRError.emptyImageData
        }

        try Task.checkCancellation()

        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try Self.performRecognition(in: imageData, options: options)
        }.value
    }

    // MARK: - Synchronous Vision Execution (Off Main Actor)

    private static func performRecognition(
        in imageData: Data,
        options: OCROptions
    ) throws -> OCRResult {
        let decoded = try decodeCGImage(from: imageData)
        try Task.checkCancellation()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = options.recognitionLevel == .accurate ? .accurate : .fast
        request.usesLanguageCorrection = options.usesLanguageCorrection
        if !options.languages.isEmpty {
            request.recognitionLanguages = options.languages
        }

        let handler = VNImageRequestHandler(
            cgImage: decoded.cgImage,
            orientation: decoded.orientation,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OCRError.recognitionFailed(error.localizedDescription)
        }

        try Task.checkCancellation()

        let observations = request.results ?? []
        let rawBlocks: [OCRTextBlock] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            guard candidate.confidence >= options.minimumConfidence else { return nil }
            return OCRTextBlock(
                text: text,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            )
        }

        guard !rawBlocks.isEmpty else {
            return OCRResult(
                fullText: "",
                blocks: [],
                averageConfidence: 0,
                detectedLanguages: options.languages
            )
        }

        let sortedBlocks = sortBlocksInReadingOrder(rawBlocks)
        let fullText = joinBlocks(sortedBlocks, preserveLineBreaks: options.preserveLineBreaks)
        let avgConfidence = sortedBlocks.reduce(Float(0)) { $0 + $1.confidence } / Float(sortedBlocks.count)

        return OCRResult(
            fullText: fullText,
            blocks: sortedBlocks,
            averageConfidence: avgConfidence,
            detectedLanguages: options.languages
        )
    }

    private struct DecodedImage {
        let cgImage: CGImage
        let orientation: CGImagePropertyOrientation
    }

    private static func decodeCGImage(from data: Data) throws -> DecodedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRError.invalidImageData
        }

        var orientation: CGImagePropertyOrientation = .up
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let rawOrientation = properties[kCGImagePropertyOrientation] as? UInt32,
           let parsed = CGImagePropertyOrientation(rawValue: rawOrientation) {
            orientation = parsed
        }

        return DecodedImage(cgImage: cgImage, orientation: orientation)
    }

    /// Sorts Vision observations top-to-bottom and left-to-right.
    ///
    /// Vision's normalized `boundingBox` uses bottom-left origin (`y = 0` at bottom, `y = 1` at top).
    /// Blocks whose vertical centers fall within half the smaller block's height are treated as
    /// sharing the same visual line and ordered left-to-right.
    static func sortBlocksInReadingOrder(_ blocks: [OCRTextBlock]) -> [OCRTextBlock] {
        // Group into visual lines from top to bottom so transitivity is preserved.
        let topToBottom = blocks.sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.0001 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var lines: [[OCRTextBlock]] = []
        for block in topToBottom {
            if let lastIndex = lines.indices.last,
               let anchor = lines[lastIndex].first,
               areOnSameVisualLine(anchor.boundingBox, block.boundingBox) {
                lines[lastIndex].append(block)
            } else {
                lines.append([block])
            }
        }

        return lines.flatMap { line in
            line.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        }
    }

    private static func areOnSameVisualLine(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance = max(0.01, min(lhs.height, rhs.height) * 0.5)
        return abs(lhs.midY - rhs.midY) <= tolerance
    }

    private static func joinBlocks(_ blocks: [OCRTextBlock], preserveLineBreaks: Bool) -> String {
        guard preserveLineBreaks else {
            return blocks.map(\.text).joined(separator: " ")
        }

        var lines: [[OCRTextBlock]] = []
        for block in blocks {
            if let lastIndex = lines.indices.last,
               let anchor = lines[lastIndex].first,
               areOnSameVisualLine(anchor.boundingBox, block.boundingBox) {
                lines[lastIndex].append(block)
            } else {
                lines.append([block])
            }
        }

        return lines
            .map { line in line.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}

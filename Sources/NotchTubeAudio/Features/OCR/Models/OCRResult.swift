//
//  OCRResult.swift
//  NotchTubeAudio
//
//  Created by NotchTubeAudio.
//

import CoreGraphics
import Foundation

/// Recognition accuracy level for local Vision OCR.
enum OCRRecognitionLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case accurate
    case fast

    var id: String { rawValue }
}

/// Configuration options passed to an ``OCRServicing`` implementation.
struct OCROptions: Equatable, Sendable {
    var languages: [String]
    var recognitionLevel: OCRRecognitionLevel
    var usesLanguageCorrection: Bool
    var preserveLineBreaks: Bool
    var minimumConfidence: Float

    init(
        languages: [String] = ["es-ES", "en-US"],
        recognitionLevel: OCRRecognitionLevel = .accurate,
        usesLanguageCorrection: Bool = true,
        preserveLineBreaks: Bool = true,
        minimumConfidence: Float = 0.0
    ) {
        self.languages = languages
        self.recognitionLevel = recognitionLevel
        self.usesLanguageCorrection = usesLanguageCorrection
        self.preserveLineBreaks = preserveLineBreaks
        self.minimumConfidence = minimumConfidence
    }
}

/// A single recognized text observation in normalized Vision coordinates.
struct OCRTextBlock: Equatable, Sendable, Identifiable {
    let id: UUID
    let text: String
    let confidence: Float
    let boundingBox: CGRect

    init(
        id: UUID = UUID(),
        text: String,
        confidence: Float,
        boundingBox: CGRect = .zero
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

/// Output of a local OCR pass over an image.
struct OCRResult: Equatable, Sendable {
    let fullText: String
    let blocks: [OCRTextBlock]
    let averageConfidence: Float
    let detectedLanguages: [String]

    var isEmpty: Bool {
        fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let empty = OCRResult(
        fullText: "",
        blocks: [],
        averageConfidence: 0,
        detectedLanguages: []
    )

    init(
        fullText: String,
        blocks: [OCRTextBlock] = [],
        averageConfidence: Float = 1.0,
        detectedLanguages: [String] = []
    ) {
        self.fullText = fullText
        self.blocks = blocks
        self.averageConfidence = averageConfidence
        self.detectedLanguages = detectedLanguages
    }
}

/// Errors produced during local image decoding or Vision text recognition.
enum OCRError: LocalizedError, Equatable, Sendable {
    case emptyImageData
    case invalidImageData
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyImageData:
            return L10n.string("plugin.ocr.error.empty_image")
        case .invalidImageData:
            return L10n.string("plugin.ocr.error.invalid_image")
        case .recognitionFailed(let reason):
            return reason.isEmpty ? L10n.string("plugin.ocr.prompt.error") : reason
        }
    }
}

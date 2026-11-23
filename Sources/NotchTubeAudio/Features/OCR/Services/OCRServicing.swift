//
//  OCRServicing.swift
//  NotchTubeAudio
//
//  Created by NotchTubeAudio.
//

import Foundation

/// Injectable contract for local OCR text extraction from image data.
protocol OCRServicing: Sendable {
    func recognizeText(
        in imageData: Data,
        options: OCROptions
    ) async throws -> OCRResult
}

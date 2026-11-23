//
//  PercentEncodingDecoder.swift
//  NotchTubeAudio
//

import Foundation

/// Utilidad local para detectar y decodificar texto con percent-encoding (`%XX`).
/// No interpreta `+` como espacio para respetar el percent-encoding estándar (RFC 3986).
enum PercentEncodingDecoder {
    static let maxInputByteCount = 131_072
    nonisolated(unsafe) private static let percentPairPattern = #/%[0-9A-Fa-f]{2}/#

    /// Devuelve `true` solo si hay al menos una secuencia `%XX` válida y la decodificación
    /// produce un texto UTF-8 distinto del original.
    static func looksPercentEncoded(_ rawText: String) -> Bool {
        if case .decoded = decode(rawText) {
            return true
        }
        return false
    }

    /// Decodifica secuencias `%XX` manteniendo intactos `+`, parámetros y fragmentos.
    static func decode(_ rawText: String) -> PercentDecodeResult {
        guard !rawText.isEmpty,
              rawText.utf8.count <= maxInputByteCount else {
            return .invalid
        }

        guard rawText.firstMatch(of: percentPairPattern) != nil else {
            return .unchanged
        }

        guard let decoded = rawText.removingPercentEncoding else {
            return .invalid
        }

        if decoded == rawText {
            return .unchanged
        }

        return .decoded(decoded)
    }
}

//
//  Base64Decoder.swift
//  NotchTubeAudio
//

import Foundation

/// Utilidad local y determinista para validar y decodificar Base64 estándar y Base64URL.
enum Base64Decoder {
    /// Longitud mínima tras eliminar espacios para evitar falsos positivos con palabras cortas.
    static let minimumEncodedLength = 8
    /// Límite de tamaño de entrada (128 KB) para no bloquear el hilo principal.
    static let maxInputByteCount = 131_072

    /// Indica si el texto parece Base64/Base64URL válido y decodificable a texto UTF-8 legible.
    static func looksLikeDecodableBase64(_ rawText: String) -> Bool {
        if case .text = decode(rawText) {
            return true
        }
        return false
    }

    /// Decodifica Base64 estándar (`+`, `/`) o Base64URL (`-`, `_`), ignorando espacios y saltos de línea.
    static func decode(_ rawText: String) -> Base64DecodeResult {
        guard rawText.utf8.count <= maxInputByteCount else {
            return .invalid
        }

        let compact = rawText
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard compact.count >= minimumEncodedLength else {
            return .invalid
        }

        guard let normalized = normalizeToStandardBase64(compact),
              let data = Data(base64Encoded: normalized),
              !data.isEmpty else {
            return .invalid
        }

        guard let decoded = String(data: data, encoding: .utf8),
              isLegibleText(decoded) else {
            return .binary(byteCount: data.count)
        }

        return .text(decoded)
    }

    /// Normaliza Base64 o Base64URL a Base64 estándar con padding `=`.
    /// Devuelve `nil` si contiene caracteres inválidos, mezcla alfabetos o tiene longitud imposible.
    static func normalizeToStandardBase64(_ compact: String) -> String? {
        guard !compact.isEmpty else { return nil }

        let usesStandardChars = compact.contains("+") || compact.contains("/")
        let usesURLSafeChars = compact.contains("-") || compact.contains("_")
        if usesStandardChars && usesURLSafeChars {
            return nil
        }

        var paddingCount = 0
        var sawPadding = false

        for scalar in compact.unicodeScalars {
            if scalar == "=" {
                sawPadding = true
                paddingCount += 1
                if paddingCount > 2 {
                    return nil
                }
                continue
            }

            if sawPadding {
                return nil
            }

            let isBase64Char =
                (scalar.value >= 65 && scalar.value <= 90) ||  // A-Z
                (scalar.value >= 97 && scalar.value <= 122) || // a-z
                (scalar.value >= 48 && scalar.value <= 57) ||  // 0-9
                scalar == "+" || scalar == "/" ||
                scalar == "-" || scalar == "_"

            if !isBase64Char {
                return nil
            }
        }

        let unpaddedCount = compact.count - paddingCount
        guard unpaddedCount > 0, unpaddedCount % 4 != 1 else {
            return nil
        }

        if sawPadding && compact.count % 4 != 0 {
            return nil
        }

        var standard = compact
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = standard.count % 4
        if remainder != 0 {
            standard.append(String(repeating: "=", count: 4 - remainder))
        }

        return standard
    }

    /// Decodifica directamente un segmento Base64URL (como los de un JWT) a `Data`,
    /// sin exigir longitud mínima de 8 caracteres.
    static func decodeBase64URLSegment(_ segment: String) -> Data? {
        guard !segment.isEmpty,
              segment.utf8.count <= maxInputByteCount,
              !segment.contains("+"),
              !segment.contains("/"),
              let normalized = normalizeToStandardBase64(segment) else {
            return nil
        }
        return Data(base64Encoded: normalized)
    }

    private static func isLegibleText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }

        var controlCount = 0
        var totalScalars = 0

        for scalar in text.unicodeScalars {
            totalScalars += 1
            if scalar == "\u{FFFD}" || scalar.value == 0x7F {
                return false
            }
            if scalar.value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t" {
                controlCount += 1
            }
        }

        guard totalScalars > 0 else { return false }
        return controlCount == 0
    }
}

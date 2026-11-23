//
//  DeveloperToolkitResult.swift
//  NotchTubeAudio
//

import Foundation

/// Resultado de decodificar una cadena Base64 o Base64URL.
enum Base64DecodeResult: Equatable, Sendable {
    case text(String)
    case binary(byteCount: Int)
    case invalid
}

/// Resultado de decodificar una cadena con percent-encoding.
enum PercentDecodeResult: Equatable, Sendable {
    case decoded(String)
    case unchanged
    case invalid
}

/// Tipo de contenido técnico detectado por ``DeveloperToolkitFeaturePlugin``.
enum DeveloperToolkitDetectedKind: Equatable, Sendable {
    case jwt(DecodedJWT)
    case base64(String)
    case percentEncoded(String)
}

/// Representación decodificada de un JSON Web Token (JWT) sin verificación de firma.
struct DecodedJWT: Equatable, Sendable {
    let formattedHeader: String
    let formattedPayload: String
    let algorithm: String?
    let type: String?
    let issuer: String?
    let subject: String?
    let audience: String?
    let issuedAt: Date?
    let notBefore: Date?
    let expiresAt: Date?
    let hasEmptySignature: Bool

    func isExpired(at referenceDate: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt < referenceDate
    }

    var formattedCombinedJSON: String {
        """
        // Header
        \(formattedHeader)

        // Payload
        \(formattedPayload)
        """
    }
}

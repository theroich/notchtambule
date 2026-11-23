//
//  JWTParser.swift
//  NotchTubeAudio
//

import Foundation

/// Parseador estructural local de JSON Web Tokens (JWT).
///
/// Decodifica únicamente el header y el payload para inspección; nunca verifica firmas
/// criptográficas ni envía tokens a la red.
enum JWTParser {
    static let maxInputByteCount = 131_072

    /// Indica si el texto tiene estructura válida de JWT decodificable (3 segmentos,
    /// header y payload JSON válidos, y `alg` o `typ` en el header).
    static func isStructurallyValidJWT(_ rawText: String) -> Bool {
        parse(rawText) != nil
    }

    /// Parsea un JWT y devuelve su header y payload formateados junto con sus metadatos informativos.
    static func parse(_ rawText: String) -> DecodedJWT? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= maxInputByteCount,
              !trimmed.contains(where: \.isWhitespace) else {
            return nil
        }

        let segments = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else {
            return nil
        }

        let headerSegment = String(segments[0])
        let payloadSegment = String(segments[1])
        let signatureSegment = String(segments[2])

        guard let headerData = Base64Decoder.decodeBase64URLSegment(headerSegment),
              let payloadData = Base64Decoder.decodeBase64URLSegment(payloadSegment) else {
            return nil
        }

        guard let headerObject = try? JSONSerialization.jsonObject(with: headerData, options: []),
              let headerDict = headerObject as? [String: Any],
              let payloadObject = try? JSONSerialization.jsonObject(with: payloadData, options: []),
              let payloadDict = payloadObject as? [String: Any] else {
            return nil
        }

        let alg = headerDict["alg"] as? String
        let typ = headerDict["typ"] as? String
        guard (alg != nil && !(alg?.isEmpty ?? true)) || (typ != nil && !(typ?.isEmpty ?? true)) else {
            return nil
        }

        guard let formattedHeader = prettyPrintJSONDictionary(headerDict),
              let formattedPayload = prettyPrintJSONDictionary(payloadDict) else {
            return nil
        }

        return DecodedJWT(
            formattedHeader: formattedHeader,
            formattedPayload: formattedPayload,
            algorithm: alg,
            type: typ,
            issuer: payloadDict["iss"] as? String,
            subject: payloadDict["sub"] as? String,
            audience: extractAudience(from: payloadDict["aud"]),
            issuedAt: extractUnixDate(from: payloadDict["iat"]),
            notBefore: extractUnixDate(from: payloadDict["nbf"]),
            expiresAt: extractUnixDate(from: payloadDict["exp"]),
            hasEmptySignature: signatureSegment.isEmpty
        )
    }

    private static func extractAudience(from value: Any?) -> String? {
        if let single = value as? String, !single.isEmpty {
            return single
        }
        if let list = value as? [String], !list.isEmpty {
            return list.joined(separator: ", ")
        }
        return nil
    }

    private static func extractUnixDate(from value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        return nil
    }

    private static func prettyPrintJSONDictionary(_ dict: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(
                  withJSONObject: dict,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return normalizeIndentationToTwoSpaces(json)
    }

    private static func normalizeIndentationToTwoSpaces(_ json: String) -> String {
        let lines = json.components(separatedBy: "\n")
        let leadingCounts = lines.compactMap { line -> Int? in
            let count = line.prefix(while: { $0 == " " }).count
            return count > 0 ? count : nil
        }
        guard let minIndent = leadingCounts.min(), minIndent == 4 else {
            return json
        }

        return lines.map { line in
            let spaceCount = line.prefix(while: { $0 == " " }).count
            guard spaceCount > 0 else { return line }
            let normalizedSpaces = String(repeating: " ", count: (spaceCount / 4) * 2 + (spaceCount % 4))
            return normalizedSpaces + line.dropFirst(spaceCount)
        }.joined(separator: "\n")
    }
}

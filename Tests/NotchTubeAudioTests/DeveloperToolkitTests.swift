//
//  DeveloperToolkitTests.swift
//  NotchTubeAudioTests
//

import Foundation
import Testing
@testable import NotchTubeAudio

@MainActor
struct DeveloperToolkitTests {
    private func makeTextItem(_ text: String) -> ClipboardItem {
        ClipboardItem(changeCount: 1, payload: .text(text))
    }

    private func makeURLItem(_ urlString: String) throws -> ClipboardItem {
        let url = try #require(URL(string: urlString))
        return ClipboardItem(changeCount: 1, payload: .url(url, rawText: urlString))
    }

    private func base64URLEncode(_ string: String) -> String {
        Data(string.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - 1. Base64Decoder

    @Test func base64DecoderHandlesStandardAndURLSafeWithOptionalPaddingAndWhitespace() {
        #expect(Base64Decoder.decode("SG9sYSBtdW5kbw==") == .text("Hola mundo"))
        #expect(Base64Decoder.decode("SG9sYSBtdW5kbw") == .text("Hola mundo"))
        #expect(Base64Decoder.decode("  SG9s\nYSBtdW5kbw== ") == .text("Hola mundo"))

        let urlSafe = base64URLEncode("https://example.com/a?b=1&c=2~_+")
        #expect(Base64Decoder.decode(urlSafe) == .text("https://example.com/a?b=1&c=2~_+"))
        #expect(Base64Decoder.looksLikeDecodableBase64("SG9sYSBtdW5kbw==") == true)
    }

    @Test func base64DecoderRejectsInvalidLengthsBinaryAndNormalWords() {
        // Short strings & impossible lengths (len % 4 == 1)
        #expect(Base64Decoder.decode("SG9s") == .invalid)
        #expect(Base64Decoder.decode("SG9sYSBtd") == .invalid) // 9 chars -> % 4 == 1
        #expect(Base64Decoder.decode("========") == .invalid)

        // Mixed standard & URL-safe characters
        #expect(Base64Decoder.decode("abc+def_ghi=") == .invalid)

        // Binary payload (PNG header bytes)
        let binaryBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xFF, 0xFE])
        let binaryBase64 = binaryBytes.base64EncodedString()
        #expect(Base64Decoder.decode(binaryBase64) == .binary(byteCount: binaryBytes.count))
        #expect(Base64Decoder.looksLikeDecodableBase64(binaryBase64) == false)

        // Normal words should not be detected as Base64
        #expect(Base64Decoder.looksLikeDecodableBase64("password") == false)
        #expect(Base64Decoder.looksLikeDecodableBase64("notchtambule") == false)
        #expect(Base64Decoder.looksLikeDecodableBase64("Hola mundo") == false)
    }

    // MARK: - 2. PercentEncodingDecoder

    @Test func percentEncodingDecoderDecodesWithoutTreatingPlusAsSpace() {
        #expect(
            PercentEncodingDecoder.decode("Hola%20mundo%21") == .decoded("Hola mundo!")
        )
        #expect(
            PercentEncodingDecoder.decode("a+b%20c%2Fd") == .decoded("a+b c/d")
        )
        #expect(
            PercentEncodingDecoder.decode("https://example.com/search?q=hola%20mundo&tag=swift%2B6#sec%201")
                == .decoded("https://example.com/search?q=hola mundo&tag=swift+6#sec 1")
        )
        #expect(PercentEncodingDecoder.looksPercentEncoded("https://example.com/?q=a%20b") == true)
    }

    @Test func percentEncodingDecoderRejectsUnchangedAndMalformedInputs() {
        #expect(PercentEncodingDecoder.decode("plain text") == .unchanged)
        #expect(PercentEncodingDecoder.decode("100% seguro") == .unchanged)
        #expect(PercentEncodingDecoder.decode("%ZZ") == .unchanged)
        #expect(PercentEncodingDecoder.decode("%FF%FE") == .invalid)
        #expect(PercentEncodingDecoder.looksPercentEncoded("100% seguro") == false)
        #expect(PercentEncodingDecoder.looksPercentEncoded("a+b") == false)
    }

    // MARK: - 3. JWTParser

    @Test func jwtParserDecodesHeaderPayloadAndMetadataWithoutVerifyingSignature() throws {
        let header = base64URLEncode(#"{"alg":"HS256","typ":"JWT"}"#)
        let payload = base64URLEncode(#"{"sub":"1234567890","iss":"auth.example","aud":["api","web"],"iat":1700000000,"exp":1700003600}"#)
        let tokenWithFakeSig = "\(header).\(payload).not-a-real-signature"
        let tokenWithEmptySig = "\(header).\(payload)."

        let parsed = try #require(JWTParser.parse(tokenWithFakeSig))
        #expect(parsed.algorithm == "HS256")
        #expect(parsed.type == "JWT")
        #expect(parsed.issuer == "auth.example")
        #expect(parsed.subject == "1234567890")
        #expect(parsed.audience == "api, web")
        #expect(parsed.issuedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(parsed.expiresAt == Date(timeIntervalSince1970: 1_700_003_600))
        #expect(parsed.isExpired(at: Date(timeIntervalSince1970: 1_700_005_000)) == true)
        #expect(parsed.isExpired(at: Date(timeIntervalSince1970: 1_700_001_000)) == false)
        #expect(parsed.hasEmptySignature == false)
        #expect(parsed.formattedHeader.contains("\"alg\" : \"HS256\""))
        #expect(parsed.formattedPayload.contains("\"sub\" : \"1234567890\""))

        let parsedEmptySig = try #require(JWTParser.parse(tokenWithEmptySig))
        #expect(parsedEmptySig.hasEmptySignature == true)
    }

    @Test func jwtParserRejectsMalformedTokens() {
        let validHeader = base64URLEncode(#"{"alg":"HS256"}"#)
        let validPayload = base64URLEncode(#"{"sub":"42"}"#)
        let nonJSON = base64URLEncode("not json at all")
        let headerWithoutAlgOrTyp = base64URLEncode(#"{"kid":"1"}"#)

        #expect(JWTParser.parse("only.two") == nil)
        #expect(JWTParser.parse("\(validHeader).\(nonJSON).sig") == nil)
        #expect(JWTParser.parse("\(headerWithoutAlgOrTyp).\(validPayload).sig") == nil)
        #expect(JWTParser.parse("\(validHeader).\(validPayload).sig.extra") == nil)
    }

    // MARK: - 4. DeveloperToolkitFeaturePlugin

    @Test func pluginIdentityDetectionAndPriority() throws {
        let plugin = DeveloperToolkitFeaturePlugin()

        #expect(plugin.id == "com.notchclip.plugin.developer-toolkit")
        #expect(plugin.iconSystemName == "chevron.left.forwardslash.chevron.right")
        #expect(plugin.priority == .normal)
        #expect(plugin.defaultTriggerBehavior == .historyActionOnly)

        let jwt = "\(base64URLEncode(#"{"alg":"HS256","typ":"JWT"}"#)).\(base64URLEncode(#"{"sub":"1"}"#)).sig"
        let jwtItem = makeTextItem(jwt)
        let base64Item = makeTextItem("SG9sYSBtdW5kbw==")
        let urlItem = try makeURLItem("https://example.com/path?q=hola%20mundo")
        let plainItem = makeTextItem("Texto normal sin codificar")

        #expect(plugin.canHandle(jwtItem) == true)
        #expect(plugin.canHandle(base64Item) == true)
        #expect(plugin.canHandle(urlItem) == true)
        #expect(plugin.canHandle(plainItem) == false)

        // Prioritizes JWT over Base64 and returns a single specific action
        let jwtActions = plugin.quickActions(for: jwtItem, context: .noop)
        #expect(jwtActions.count == 1)
        #expect(jwtActions.first?.id.contains("decode-jwt") == true)
    }

    @Test func pluginQuickActionsAndPromptBehavior() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let plugin = DeveloperToolkitFeaturePlugin()

        // 1. JWT opens prompt and does not write to clipboard automatically
        let jwt = "\(base64URLEncode(#"{"alg":"HS256","typ":"JWT"}"#)).\(base64URLEncode(#"{"sub":"1"}"#)).sig"
        let jwtItem = makeTextItem(jwt)
        let jwtContext = FeatureActionContext.noop
        let jwtAction = try #require(plugin.quickActions(for: jwtItem, context: jwtContext).first)
        #expect(jwtAction.title == "Decodificar JWT")
        jwtAction.handler()
        #expect(jwtContext.writtenPayloads.isEmpty)
        #expect(jwtContext.lastPresentedPrompt?.pluginID == plugin.id)
        #expect(jwtContext.lastPresentedPrompt?.item.id == jwtItem.id)
        #expect(plugin.makePromptView(for: jwtItem, context: jwtContext, onComplete: {}, onDismiss: {}) != nil)

        // 2. Base64 writes decoded text to clipboard and notifies
        let b64Item = makeTextItem("SG9sYSBtdW5kbw==")
        let b64Context = FeatureActionContext.noop
        let b64Action = try #require(plugin.quickActions(for: b64Item, context: b64Context).first)
        #expect(b64Action.title == "Decodificar Base64")
        b64Action.handler()
        #expect(b64Context.writtenPayloads == [.text("Hola mundo")])
        #expect(b64Context.lastNotification?.message == "Base64 decodificado copiado")
        #expect(plugin.makePromptView(for: b64Item, context: b64Context, onComplete: {}, onDismiss: {}) == nil)

        // 3. Percent-encoded URL writes decoded text to clipboard and notifies
        let urlItem = makeTextItem("https://example.com/a%20b?x=1%262")
        let urlContext = FeatureActionContext.noop
        let urlAction = try #require(plugin.quickActions(for: urlItem, context: urlContext).first)
        #expect(urlAction.title == "Decodificar URL")
        urlAction.handler()
        #expect(urlContext.writtenPayloads == [.text("https://example.com/a b?x=1&2")])
        #expect(urlContext.lastNotification?.message == "URL decodificada copiada")
        #expect(plugin.makePromptView(for: urlItem, context: urlContext, onComplete: {}, onDismiss: {}) == nil)
    }
}

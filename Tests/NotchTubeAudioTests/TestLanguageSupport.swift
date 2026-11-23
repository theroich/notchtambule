import Foundation
@testable import NotchTubeAudio

/// Sets the process-wide language to Spanish and returns the previous value.
///
/// Use it only from synchronous, main-actor sections of a test (or after the last
/// `await` of an async test) so the language cannot change while another test is
/// suspended:
///
/// ```swift
/// let previousLanguage = forceSpanishLanguage()
/// defer { L10n.currentLanguage = previousLanguage }
/// ```
@MainActor
func forceSpanishLanguage() -> AppLanguage {
    let previous = L10n.currentLanguage
    L10n.currentLanguage = .spanish
    return previous
}

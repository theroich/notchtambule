//
//  LocalizationTests.swift
//  NotchTubeAudioTests
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NotchTubeAudio

@MainActor
struct LocalizationTests {
    // MARK: - 1. String Catalog Completeness (es & en)

    @Test func stringCatalogContainsAllKeysTranslatedInSpanishAndEnglish() throws {
        let catalog = try L10n.loadCatalogDocument()
        #expect(catalog.sourceLanguage == "es")
        #expect(catalog.version == "1.0")
        #expect(catalog.strings.count >= 80)

        for (key, entry) in catalog.strings.sorted(by: { $0.key < $1.key }) {
            let localizations = try #require(
                entry.localizations,
                "Missing localizations dictionary for key '\(key)'"
            )

            for languageCode in L10n.supportedLanguageCodes {
                let unit = try #require(
                    localizations[languageCode]?.stringUnit,
                    "Missing '\(languageCode)' translation for key '\(key)'"
                )
                let trimmed = unit.value.trimmingCharacters(in: .whitespacesAndNewlines)
                #expect(!trimmed.isEmpty, "Empty '\(languageCode)' translation for key '\(key)'")
                #expect(unit.state == "translated", "Untranslated state for key '\(key)' in '\(languageCode)'")
            }
        }
    }

    // MARK: - 2. System Language & Override Resolution

    @Test func systemLanguageResolutionSelectsEnglishForEnAndSpanishForEsOrOtherLanguages() {
        // Criterion 1: System in English -> UI in English
        #expect(AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["en-US", "es-ES"]) == "en")
        #expect(AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["en-GB"]) == "en")
        #expect(AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["en"]) == "en")

        // Criterion 2: System in Spanish (or any other language) -> UI in Spanish
        #expect(AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["es-ES", "en-US"]) == "es")
        #expect(AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["es-MX"]) == "es")
        #expect(AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["fr-FR", "en-US"]) == "es")
        #expect(AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["de-DE"]) == "es")
        #expect(AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["ja-JP"]) == "es")
        #expect(AppLanguage.system.resolvedLanguageCode(preferredLanguages: []) == "es")

        // Criterion 3: Explicit es / en overrides ignore system language
        #expect(AppLanguage.spanish.resolvedLanguageCode(preferredLanguages: ["en-US"]) == "es")
        #expect(AppLanguage.english.resolvedLanguageCode(preferredLanguages: ["es-ES"]) == "en")
    }

    @Test func persistsAppLanguageSelectionAndAppliesAppleLanguagesOverride() throws {
        let suiteName = "notchtube.localization.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            L10n.currentLanguage = .system
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = SettingsManager(defaults: defaults)
        #expect(settings.appLanguage == .system)
        #expect(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] == nil)

        // Force English
        settings.appLanguage = .english
        #expect(settings.resolvedLanguageCode == "en")
        #expect(defaults.string(forKey: "notchtube.appLanguage") == "en")
        #expect(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] as? [String] == ["en"])

        let reloadedEN = SettingsManager(defaults: defaults)
        #expect(reloadedEN.appLanguage == .english)
        #expect(reloadedEN.resolvedLanguageCode == "en")

        // Force Spanish
        reloadedEN.appLanguage = .spanish
        #expect(reloadedEN.resolvedLanguageCode == "es")
        #expect(defaults.string(forKey: "notchtube.appLanguage") == "es")
        #expect(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] as? [String] == ["es"])

        let reloadedES = SettingsManager(defaults: defaults)
        #expect(reloadedES.appLanguage == .spanish)
        #expect(reloadedES.resolvedLanguageCode == "es")

        // Reset to System
        reloadedES.appLanguage = .system
        #expect(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] == nil)
    }

    // MARK: - 3. Full UI String Verification in English and Spanish

    @Test func allCoreAndPluginStringsLocalizeCorrectlyInEnglishAndSpanish() throws {
        let suiteName = "notchtube.localization.full.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            L10n.currentLanguage = .system
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = SettingsManager(defaults: defaults)
        settings.persistClipboardHistory = false

        let youtubePlugin = YouTubeAudioFeaturePlugin(settings: settings)
        let urlCleanerPlugin = URLCleanerFeaturePlugin()
        let jsonFormatterPlugin = JSONFormatterFeaturePlugin()
        let colorConverterPlugin = ColorConverterFeaturePlugin()

        let fileA = URL(fileURLWithPath: "/tmp/song.mp3")
        let fileB = URL(fileURLWithPath: "/tmp/cover.png")
        let filesItem = ClipboardItem(
            changeCount: 1,
            payload: .files([fileA, fileB]),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.apple.finder", localizedName: "Finder")
        )
        let textItem = ClipboardItem(
            changeCount: 2,
            payload: .text("Hello world"),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.apple.Notes", localizedName: "Notes")
        )
        let trackedURL = try #require(URL(string: "https://example.com/item?utm_source=test&fbclid=123"))
        let urlItem = ClipboardItem(
            changeCount: 3,
            payload: .url(trackedURL, rawText: trackedURL.absoluteString)
        )
        let ytURL = try #require(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let ytItem = ClipboardItem(
            changeCount: 4,
            payload: .url(ytURL, rawText: ytURL.absoluteString)
        )
        let colorItem = ClipboardItem(changeCount: 5, payload: .text("#FF5733"))

        let downloadItem = DownloadItem(
            url: ytURL,
            canonicalURLString: ytURL.absoluteString,
            videoID: "dQw4w9WgXcQ",
            title: "Test Track",
            authorName: "Artist",
            thumbnailURL: nil,
            format: .mp3
        )

        // Verify English when system is in English (.system + ["en-US"])
        L10n.withLanguage(.system, systemPreferredLanguages: ["en-US"]) {
            #expect(L10n.effectiveLanguageCode == "en")

            // Filters
            #expect(ClipboardContentFilter.all.displayTitle == "All")
            #expect(ClipboardContentFilter.text.displayTitle == "Text")
            #expect(ClipboardContentFilter.links.displayTitle == "Links")
            #expect(ClipboardContentFilter.images.displayTitle == "Images")
            #expect(ClipboardContentFilter.files.displayTitle == "Files")
            #expect(ClipboardContentFilter.pinned.displayTitle == "Pinned")

            // Language options
            #expect(AppLanguage.system.displayTitle == "System")
            #expect(AppLanguage.spanish.displayTitle == "Español")
            #expect(AppLanguage.english.displayTitle == "English")

            // Clipboard item previews
            #expect(filesItem.previewTitle == "song.mp3 and 1 more")
            #expect(filesItem.previewSubtitle == "Finder · 2 files")
            #expect(textItem.previewSubtitle == "Notes · 11 characters")

            // Plugins & quick actions
            #expect(youtubePlugin.displayName == "YouTube Audio")
            #expect(youtubePlugin.activityPanelTitle == "Downloads")
            let ytActions = youtubePlugin.quickActions(for: ytItem, context: .noop)
            #expect(ytActions.map(\.title) == ["Download MP3", "Download WAV"])

            #expect(urlCleanerPlugin.displayName == "URL Cleaner")
            let cleanContext = FeatureActionContext.noop
            let cleanActions = urlCleanerPlugin.quickActions(for: urlItem, context: cleanContext)
            #expect(cleanActions.first?.title == "Clean URL (remove tracking)")
            cleanActions.first?.handler()
            #expect(cleanContext.lastNotification?.message == "Clean URL copied (2 parameters removed)")

            #expect(jsonFormatterPlugin.displayName == "JSON Formatter")
            #expect(colorConverterPlugin.displayName == "Color Converter")
            let colorActions = colorConverterPlugin.quickActions(for: colorItem, context: .noop)
            #expect(colorActions.map(\.title) == [
                "Copy as RGB",
                "Copy as HEX",
                "Copy as SwiftUI Color"
            ])

            // Download statuses
            downloadItem.status = .queued
            #expect(downloadItem.statusText == "Queued")
            downloadItem.status = .downloading
            downloadItem.progress = 0.42
            #expect(downloadItem.statusText == "Downloading 42%")
            downloadItem.status = .converting
            #expect(downloadItem.statusText == "Converting…")
            downloadItem.status = .completed
            #expect(downloadItem.statusText == "Completed")
            downloadItem.status = .failed
            #expect(downloadItem.statusText == "Failed")
            downloadItem.status = .cancelled
            #expect(downloadItem.statusText == "Cancelled")

            // Feedback badges & AutoPaste messages
            #expect(ClipboardItemClickFeedback.copied.badgeTitle == "Copied")
            #expect(ClipboardItemClickFeedback.pasted.badgeTitle == "Pasted")
            #expect(AutoPasteSkipReason.accessibilityPermissionMissing.userFacingMessage?.contains("Enable Accessibility") == true)
        }

        // Verify Spanish when system is in Spanish or another language (.system + ["fr-FR"])
        L10n.withLanguage(.system, systemPreferredLanguages: ["fr-FR"]) {
            #expect(L10n.effectiveLanguageCode == "es")

            #expect(ClipboardContentFilter.all.displayTitle == "Todo")
            #expect(ClipboardContentFilter.text.displayTitle == "Texto")
            #expect(ClipboardContentFilter.links.displayTitle == "Enlaces")
            #expect(ClipboardContentFilter.images.displayTitle == "Imágenes")
            #expect(ClipboardContentFilter.files.displayTitle == "Archivos")
            #expect(ClipboardContentFilter.pinned.displayTitle == "Fijados")

            #expect(AppLanguage.system.displayTitle == "Sistema")
            #expect(filesItem.previewTitle == "song.mp3 y 1 más")
            #expect(filesItem.previewSubtitle == "Finder · 2 archivos")
            #expect(textItem.previewSubtitle == "Notes · 11 caracteres")

            #expect(youtubePlugin.activityPanelTitle == "Descargas")
            #expect(urlCleanerPlugin.displayName == "Limpiador de URLs")
            #expect(jsonFormatterPlugin.displayName == "Formateador JSON")
            #expect(colorConverterPlugin.displayName == "Conversor de Color")

            downloadItem.status = .queued
            #expect(downloadItem.statusText == "En cola")
            downloadItem.status = .downloading
            downloadItem.progress = 0.42
            #expect(downloadItem.statusText == "Descargando 42%")
        }
    }

    // MARK: - 4. Regional Dates & Byte Sizes

    @Test func relativeTimestampsAndByteCountsRespectActiveLocale() {
        let now = Date()
        let twoMinutesAgo = now.addingTimeInterval(-120)

        let esLocale = Locale(identifier: "es")
        let enLocale = Locale(identifier: "en")

        #expect(ClipboardItemRowView.formatRelativeTimestamp(now, relativeTo: now, locale: esLocale) == "ahora")
        #expect(ClipboardItemRowView.formatRelativeTimestamp(now, relativeTo: now, locale: enLocale) == "now")

        let esRelative = ClipboardItemRowView.formatRelativeTimestamp(twoMinutesAgo, relativeTo: now, locale: esLocale)
        let enRelative = ClipboardItemRowView.formatRelativeTimestamp(twoMinutesAgo, relativeTo: now, locale: enLocale)
        #expect(esRelative != enRelative)
        #expect(!esRelative.isEmpty)
        #expect(!enRelative.isEmpty)

        let formattedES = L10n.formatByteCount(2048, locale: esLocale)
        let formattedEN = L10n.formatByteCount(2048, locale: enLocale)
        #expect(formattedES.uppercased().contains("KB"))
        #expect(formattedEN.uppercased().contains("KB"))
    }

    // MARK: - 5. Source Code Audit & Pseudolocalization Layout Check

    @Test func everyReferencedLocalizationKeyInSourcesExistsInCatalogAndNoHardcodedSpanishRemains() throws {
        let catalog = try L10n.loadCatalogDocument()
        let catalogKeys = Set(catalog.strings.keys)

        let sourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NotchTubeAudio", isDirectory: true)

        let enumerator = try #require(
            FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil)
        )

        let keyCallPattern = #/L10n\.(?:string|format)\(\s*"([^"]+)"/#
        let forbiddenSpanishLiterals = [
            "\"Portapapeles\"",
            "\"Descargas\"",
            "\"Buscar en el portapapeles…\"",
            "\"Historial del portapapeles vacío\"",
            "\"Monitorización del Portapapeles\"",
            "\"Comportamiento del Notch\"",
            "\"Guardar audio\"",
            "\"Sin descargas\"",
            "\"Limpiar URL (quitar tracking)\"",
            "\"Conversor de Color\"",
            "\"Formateador JSON\"",
            "\"Mostrar portapapeles en el notch\"",
            "\"Ocultar portapapeles en el notch\""
        ]

        var swiftFileCount = 0
        var referencedKeys: Set<String> = []

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            swiftFileCount += 1
            let content = try String(contentsOf: fileURL, encoding: .utf8)

            for match in content.matches(of: keyCallPattern) {
                let key = String(match.1)
                referencedKeys.insert(key)
                #expect(
                    catalogKeys.contains(key),
                    "Key '\(key)' used in \(fileURL.lastPathComponent) is missing from Localizable.xcstrings"
                )
            }

            for forbidden in forbiddenSpanishLiterals {
                #expect(
                    !content.contains(forbidden),
                    "Hardcoded Spanish literal \(forbidden) found in \(fileURL.lastPathComponent)"
                )
            }
        }

        #expect(swiftFileCount > 20)
        #expect(referencedKeys.count >= 80)
    }

    @Test func notchAndSettingsViewsRenderWithoutOverflowInSpanishEnglishAndPseudolocalization() async throws {
        let suiteName = "notchtube.localization.layout.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            L10n.currentLanguage = .system
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = SettingsManager(defaults: defaults)
        settings.persistClipboardHistory = false

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTubeL10nLayout-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = ClipboardStorage(baseDirectory: tempDir, debounceInterval: 0)
        let pasteboard = MockPasteboard()
        let historyStore = ClipboardHistoryStore(
            settings: settings,
            storage: storage,
            pasteboard: pasteboard
        )
        let youtubePlugin = YouTubeAudioFeaturePlugin(settings: settings)
        let urlCleanerPlugin = URLCleanerFeaturePlugin()
        let featureRegistry = FeatureRegistry(
            settings: settings,
            plugins: [youtubePlugin, urlCleanerPlugin]
        )
        let appState = AppState(
            settings: settings,
            historyStore: historyStore,
            featureRegistry: featureRegistry
        )

        historyStore.record(ClipboardItem(changeCount: 1, payload: .text("Sample clipboard entry")))
        appState.showPanelFromHover()

        let modes: [(AppLanguage, Bool)] = [
            (.spanish, false),
            (.english, false),
            (.english, true)
        ]

        for (language, pseudo) in modes {
            await Task.yield()
            L10n.withLanguage(language, pseudolocalized: pseudo) {
                let rootHosting = NSHostingView(rootView: NotchRootView(appState: appState))
                rootHosting.frame = NSRect(x: 0, y: 0, width: NotchMetrics.contentWidth, height: 360)
                rootHosting.layoutSubtreeIfNeeded()
                #expect(rootHosting.fittingSize.width == NotchMetrics.contentWidth)

                let pillsHosting = NSHostingView(
                    rootView: ClipboardFilterPillsView(selection: .all, onSelect: { _ in })
                        .frame(width: NotchMetrics.contentWidth)
                )
                pillsHosting.layoutSubtreeIfNeeded()
                #expect(pillsHosting.fittingSize.height > 0)
                #expect(pillsHosting.fittingSize.height <= 40)
            }
            await Task.yield()
            L10n.withLanguage(language, pseudolocalized: pseudo) {
                let settingsHosting = NSHostingView(
                    rootView: SettingsView(
                        settings: settings,
                        featureRegistry: featureRegistry,
                        historyStore: historyStore
                    )
                )
                settingsHosting.frame = NSRect(x: 0, y: 0, width: 600, height: 520)
                settingsHosting.layoutSubtreeIfNeeded()
                #expect(settingsHosting.fittingSize.width == 600)
            }
        }
    }
}

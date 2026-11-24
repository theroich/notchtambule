//
//  ClipboardNotchUITests.swift
//  NotchTubeAudioTests
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NotchTubeAudio

@MainActor
private final class UITestPlugin: ClipboardFeaturePlugin {
    let id: String
    let displayName: String
    let summary: String
    let iconSystemName: String
    let priority: FeaturePriority
    let defaultTriggerBehavior: FeatureTriggerBehavior
    let hasActivityPanel: Bool
    var activeTasksCount: Int
    var canHandlePredicate: (ClipboardItem) -> Bool
    var quickActionTitle: String

    private(set) var executedItemIDs: [UUID] = []

    init(
        id: String,
        displayName: String = "Descargas",
        summary: String = "Plugin de prueba",
        iconSystemName: String = "waveform",
        priority: FeaturePriority = .high,
        defaultTriggerBehavior: FeatureTriggerBehavior = .historyActionOnly,
        hasActivityPanel: Bool = true,
        activeTasksCount: Int = 0,
        quickActionTitle: String = "Descargar audio",
        canHandlePredicate: @escaping (ClipboardItem) -> Bool = { $0.contentType == .url }
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.iconSystemName = iconSystemName
        self.priority = priority
        self.defaultTriggerBehavior = defaultTriggerBehavior
        self.hasActivityPanel = hasActivityPanel
        self.activeTasksCount = activeTasksCount
        self.quickActionTitle = quickActionTitle
        self.canHandlePredicate = canHandlePredicate
    }

    func canHandle(_ item: ClipboardItem) -> Bool {
        canHandlePredicate(item)
    }

    func quickActions(for item: ClipboardItem, context: FeatureActionContext) -> [FeatureQuickAction] {
        guard canHandle(item) else { return [] }
        return [
            FeatureQuickAction(
                id: "\(id).quick.\(item.id.uuidString)",
                pluginID: id,
                title: quickActionTitle,
                iconSystemName: iconSystemName
            ) { [weak self] in
                self?.executedItemIDs.append(item.id)
                context.notifyUser(message: "Acción ejecutada", icon: "checkmark.circle.fill")
            }
        ]
    }

    func makeActivityPanelView(context: FeatureActionContext) -> AnyView? {
        guard hasActivityPanel else { return nil }
        return AnyView(Text("Actividad de \(displayName)"))
    }
}

@MainActor
struct ClipboardNotchUITests {
    private struct Harness {
        let appState: AppState
        let controller: NotchController
        let historyStore: ClipboardHistoryStore
        let featureRegistry: FeatureRegistry
        let pasteboard: MockPasteboard
        let settings: SettingsManager
        let defaults: UserDefaults
        let suiteName: String
        let tempDir: URL

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeHarness(plugins: [any ClipboardFeaturePlugin] = []) throws -> Harness {
        let suiteName = "notchtube.clipboard.ui.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsManager(defaults: defaults)
        settings.persistClipboardHistory = false

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTubeClipboardUITests-\(UUID().uuidString)", isDirectory: true)
        let storage = ClipboardStorage(baseDirectory: tempDir, debounceInterval: 0)
        let pasteboard = MockPasteboard()
        let historyStore = ClipboardHistoryStore(
            settings: settings,
            storage: storage,
            pasteboard: pasteboard
        )
        let featureRegistry = FeatureRegistry(settings: settings, plugins: plugins)
        let appState = AppState(
            settings: settings,
            historyStore: historyStore,
            featureRegistry: featureRegistry
        )
        let controller = NotchController(appState: appState, settings: settings)

        return Harness(
            appState: appState,
            controller: controller,
            historyStore: historyStore,
            featureRegistry: featureRegistry,
            pasteboard: pasteboard,
            settings: settings,
            defaults: defaults,
            suiteName: suiteName,
            tempDir: tempDir
        )
    }

    @Test func notchMetricsAndGeometryAdaptToClipboardHistoryAndTabs() throws {
        let plugin = UITestPlugin(
            id: "com.notchclip.plugin.youtube-audio",
            hasActivityPanel: true,
            activeTasksCount: 2
        )
        let harness = try makeHarness(plugins: [plugin])
        defer { harness.cleanup() }

        #expect(NotchMetrics.contentWidth >= 430)
        #expect(NotchMetrics.contentWidth <= 450)
        #expect(NotchMetrics.queueListMaxHeight >= 260)
        #expect(NotchMetrics.queueListMaxHeight <= 300)

        // Open panel in clipboardHistory tab with 0 items (uses minimum 1 row height for empty state)
        harness.appState.showPanelFromHover()
        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))
        let emptySize = harness.controller.currentContentSize
        #expect(emptySize.width == NotchMetrics.contentWidth)

        // Add 3 items and verify content height grows adaptively
        for index in 1...3 {
            harness.historyStore.record(
                ClipboardItem(
                    changeCount: index,
                    payload: .text("Elemento \(index)")
                )
            )
        }
        let threeItemsSize = harness.controller.currentContentSize
        #expect(threeItemsSize.height > emptySize.height)
        let expectedThreeHeight: CGFloat = 34 + NotchMetrics.clipboardControlsHeight + 16 + (3 * NotchMetrics.clipboardRowHeight)
        #expect(threeItemsSize.height == expectedThreeHeight)

        // Add 10 items and verify height is capped by NotchMetrics.queueListMaxHeight
        for index in 4...10 {
            harness.historyStore.record(
                ClipboardItem(
                    changeCount: index,
                    payload: .text("Elemento \(index)")
                )
            )
        }
        let cappedSize = harness.controller.currentContentSize
        let expectedMaxHeight: CGFloat = 34 + NotchMetrics.clipboardControlsHeight + 16 + NotchMetrics.queueListMaxHeight
        #expect(cappedSize.height == expectedMaxHeight)

        // Switching to pluginActivity tab preserves width and generous retention height
        harness.appState.selectTab(.pluginActivity(pluginID: plugin.id))
        let activitySize = harness.controller.currentContentSize
        #expect(activitySize.width == NotchMetrics.contentWidth)
        #expect(activitySize.height == 34 + NotchMetrics.queueHeaderHeight + 16 + NotchMetrics.queueListMaxHeight)
    }

    @Test func clipboardItemRowFormatsMetadataRelativeTimeAndHexColors() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let now = Date()
        let twoMinutesAgo = now.addingTimeInterval(-120)

        #expect(ClipboardItemRowView.formatRelativeTimestamp(now, relativeTo: now) == "ahora")
        let relativeTwoMin = ClipboardItemRowView.formatRelativeTimestamp(twoMinutesAgo, relativeTo: now)
        #expect(!relativeTwoMin.isEmpty)

        #expect(ClipboardItemRowView.parseHexColor("#FF5733") != nil)
        #expect(ClipboardItemRowView.parseHexColor("#0F8") != nil)
        #expect(ClipboardItemRowView.parseHexColor("#112233FF") != nil)
        #expect(ClipboardItemRowView.parseHexColor("not-a-color") == nil)

        let item = ClipboardItem(
            capturedAt: now,
            changeCount: 1,
            payload: .text("Hola mundo"),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
        )
        let row = ClipboardItemRowView(
            item: item,
            quickActions: [],
            matchedPlugins: [],
            isCopiedFeedbackActive: false,
            onCopy: {},
            onTogglePin: {},
            onRemove: {}
        )
        #expect(row.formattedMetadataLine.contains("Safari"))
        #expect(row.formattedMetadataLine.contains("10 caracteres"))
    }

    @Test func viewsInstantiateAndExposePluginQuickActionsAndTabSwitching() throws {
        let youtubePlugin = UITestPlugin(
            id: "com.notchclip.plugin.youtube-audio",
            displayName: "Descargas",
            iconSystemName: "waveform",
            hasActivityPanel: true,
            activeTasksCount: 1
        )
        let harness = try makeHarness(plugins: [youtubePlugin])
        defer { harness.cleanup() }

        let url = try #require(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let urlItem = ClipboardItem(
            changeCount: 1,
            payload: .url(url, rawText: url.absoluteString),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
        )
        let textItem = ClipboardItem(
            changeCount: 2,
            payload: .text("Texto de prueba"),
            sourceApp: ClipboardSourceApp(bundleIdentifier: "com.apple.dt.Xcode", localizedName: "Xcode")
        )

        harness.appState.handleCapturedItem(urlItem)
        harness.appState.handleCapturedItem(textItem)

        // Newest item is first
        #expect(harness.historyStore.filteredItems.map(\.payload) == [textItem.payload, urlItem.payload])

        // Quick actions are dynamically injected only for compatible items
        let urlActions = harness.featureRegistry.quickActions(for: urlItem, context: harness.appState.actionContext)
        let textActions = harness.featureRegistry.quickActions(for: textItem, context: harness.appState.actionContext)
        #expect(urlActions.count == 1)
        #expect(urlActions.first?.title == "Descargar audio")
        #expect(textActions.isEmpty)

        // Execute the quick action handler
        urlActions.first?.handler()
        #expect(youtubePlugin.executedItemIDs == [urlItem.id])
        #expect(harness.appState.activeNotification?.message == "Acción ejecutada")

        // Render SwiftUI view hierarchy via NSHostingView to verify layout and body evaluation
        harness.appState.showPanelFromHover()
        let rootView = NotchRootView(appState: harness.appState)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: NotchMetrics.contentWidth, height: 360)
        hostingView.layoutSubtreeIfNeeded()
        #expect(hostingView.fittingSize.width == NotchMetrics.contentWidth)

        // Filter pills and search bar filter items immediately
        let pillsView = ClipboardFilterPillsView(selection: .links) { selected in
            harness.historyStore.selectedFilter = selected
        }
        let pillsHosting = NSHostingView(rootView: pillsView)
        pillsHosting.layoutSubtreeIfNeeded()

        harness.historyStore.selectedFilter = .links
        #expect(harness.historyStore.filteredItems.count == 1)
        #expect(harness.historyStore.filteredItems.first?.contentType == .url)

        // Switch tabs via NotchHeaderTabsView callback without closing the panel
        let tabsView = NotchHeaderTabsView(
            selectedTab: harness.appState.activeTab,
            clipboardItemCount: harness.historyStore.items.count,
            activityPlugins: harness.featureRegistry.activityPanelPlugins,
            onSelectTab: { tab in
                harness.appState.selectTab(tab)
            }
        )
        let tabsHosting = NSHostingView(rootView: tabsView)
        tabsHosting.layoutSubtreeIfNeeded()

        harness.appState.selectTab(.pluginActivity(pluginID: youtubePlugin.id))
        #expect(harness.appState.activeTab == .pluginActivity(pluginID: youtubePlugin.id))
        #expect(harness.appState.notchMode == .showingPanel(tab: .pluginActivity(pluginID: youtubePlugin.id)))
        hostingView.rootView = NotchRootView(appState: harness.appState)
        hostingView.layoutSubtreeIfNeeded()

        harness.appState.selectTab(.clipboardHistory)
        #expect(harness.appState.activeTab == .clipboardHistory)
        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))
    }

    @Test func clickingNotchHeaderTabsSwitchesBetweenDownloadsAndClipboardHistory() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        let suiteName = "notchtube.clipboard.ui.real.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        settings.persistClipboardHistory = false

        let downloadManager = DownloadManager(settings: settings)
        let youtubePlugin = YouTubeAudioFeaturePlugin(
            settings: settings,
            downloadManager: downloadManager
        )
        let harness = try makeHarness(plugins: [youtubePlugin])
        defer { harness.cleanup() }

        #expect(youtubePlugin.activityPanelTitle == "Descargas")
        #expect(youtubePlugin.hasActivityPanel == true)
        #expect(harness.featureRegistry.isPluginEnabled(youtubePlugin.id) == true)

        for idx in 1...3 {
            harness.historyStore.record(
                ClipboardItem(changeCount: idx, payload: .text("Ítem \(idx)"))
            )
        }

        // Open notch panel in clipboardHistory tab
        harness.appState.showPanelFromHover()
        #expect(harness.appState.activeTab == .clipboardHistory)
        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))

        let downloadsTab = NotchPanelTab.pluginActivity(pluginID: youtubePlugin.id)

        // Verify actual mouse click hit-testing inside NSHostingView on the 'Descargas' and 'Portapapeles' tab pills
        let headerView = NotchHeaderTabsView(
            selectedTab: harness.appState.activeTab,
            clipboardItemCount: harness.historyStore.items.count,
            activityPlugins: harness.featureRegistry.activityPanelPlugins,
            onSelectTab: { selected in
                harness.appState.selectTab(selected)
            }
        )
        let headerHosting = NSHostingView(rootView: headerView)
        let headerSize = headerHosting.fittingSize
        headerHosting.frame = NSRect(origin: .zero, size: headerSize)
        let headerWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: headerSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        headerWindow.contentView = headerHosting
        headerHosting.layoutSubtreeIfNeeded()

        // Click on the right side ('Descargas' pill) of NotchHeaderTabsView
        let descargasPoint = NSPoint(x: headerSize.width - 45, y: headerSize.height / 2)
        let descargasHit = try #require(headerHosting.hitTest(descargasPoint))
        // Ensure it does NOT hit an NSClipView (which would eat clicks without forwarding to the SwiftUI Button)
        #expect(!String(describing: type(of: descargasHit)).contains("NSClipView"))
        if let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: descargasPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: headerWindow.windowNumber,
            context: nil,
            eventNumber: 100,
            clickCount: 1,
            pressure: 1.0
        ), let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: descargasPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.01,
            windowNumber: headerWindow.windowNumber,
            context: nil,
            eventNumber: 101,
            clickCount: 1,
            pressure: 0.0
        ) {
            descargasHit.mouseDown(with: down)
            descargasHit.mouseUp(with: up)
        }
        #expect(harness.appState.activeTab == downloadsTab)
        #expect(harness.appState.notchMode == .showingPanel(tab: downloadsTab))

        // Verify NotchRootView reflects the new tab content height
        let historyRootHosting = NSHostingView(rootView: NotchRootView(appState: harness.appState))
        historyRootHosting.frame = NSRect(x: 0, y: 0, width: NotchMetrics.contentWidth, height: 360)
        historyRootHosting.layoutSubtreeIfNeeded()
        let downloadsFittingHeight = historyRootHosting.fittingSize.height
        #expect(historyRootHosting.fittingSize.width == NotchMetrics.contentWidth)

        // Update headerView with the new selectedTab and click on the left side ('Portapapeles' pill)
        headerHosting.rootView = NotchHeaderTabsView(
            selectedTab: harness.appState.activeTab,
            clipboardItemCount: harness.historyStore.items.count,
            activityPlugins: harness.featureRegistry.activityPanelPlugins,
            onSelectTab: { selected in
                harness.appState.selectTab(selected)
            }
        )
        headerHosting.layoutSubtreeIfNeeded()

        let portapapelesPoint = NSPoint(x: 45, y: headerSize.height / 2)
        let portapapelesHit = try #require(headerHosting.hitTest(portapapelesPoint))
        #expect(!String(describing: type(of: portapapelesHit)).contains("NSClipView"))
        if let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: portapapelesPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.05,
            windowNumber: headerWindow.windowNumber,
            context: nil,
            eventNumber: 102,
            clickCount: 1,
            pressure: 1.0
        ), let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: portapapelesPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.06,
            windowNumber: headerWindow.windowNumber,
            context: nil,
            eventNumber: 103,
            clickCount: 1,
            pressure: 0.0
        ) {
            portapapelesHit.mouseDown(with: down)
            portapapelesHit.mouseUp(with: up)
        }
        #expect(harness.appState.activeTab == .clipboardHistory)
        #expect(harness.appState.notchMode == .showingPanel(tab: .clipboardHistory))

        historyRootHosting.rootView = NotchRootView(appState: harness.appState)
        historyRootHosting.layoutSubtreeIfNeeded()
        let historyFittingHeight = historyRootHosting.fittingSize.height
        #expect(historyFittingHeight > downloadsFittingHeight)
    }

    @Test func filterPillsStayOnSingleLineInsideHorizontalScrollWithFixedHeight() throws {
        let previousLanguage = forceSpanishLanguage()
        defer { L10n.currentLanguage = previousLanguage }

        var selectedFilter: ClipboardContentFilter = .all
        let pillsView = ClipboardFilterPillsView(selection: selectedFilter) { filter in
            selectedFilter = filter
        }

        // Measure the natural single-line height of a standalone pill label
        let singleLineReference = NSHostingView(
            rootView: HStack(spacing: 4) {
                Image(systemName: "photo")
                    .font(.system(size: 9.5, weight: .semibold))
                Text("Imágenes")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .padding(.vertical, 1)
        )
        singleLineReference.layoutSubtreeIfNeeded()
        let expectedSingleLineHeight = singleLineReference.fittingSize.height

        // Host ClipboardFilterPillsView constrained to the notch width (440 pt) and even narrower (280 pt)
        let constrainedHosting = NSHostingView(
            rootView: pillsView.frame(width: NotchMetrics.contentWidth)
        )
        constrainedHosting.frame = NSRect(x: 0, y: 0, width: NotchMetrics.contentWidth, height: 100)
        constrainedHosting.layoutSubtreeIfNeeded()
        let notchFittingSize = constrainedHosting.fittingSize

        let narrowHosting = NSHostingView(
            rootView: pillsView.frame(width: 280)
        )
        narrowHosting.frame = NSRect(x: 0, y: 0, width: 280, height: 100)
        narrowHosting.layoutSubtreeIfNeeded()
        let narrowFittingSize = narrowHosting.fittingSize

        // 1. Height must match a single-line pill row (no multi-line wrapping of 'Imágenes', 'Archivos', or 'Fijados')
        #expect(abs(notchFittingSize.height - expectedSingleLineHeight) <= 2.0)
        #expect(notchFittingSize.height <= 28.0)

        // 2. Narrower container does not cause wrapping or change the bar's fixed vertical height
        #expect(abs(notchFittingSize.height - narrowFittingSize.height) <= 0.5)

        // 3. Height stays identical regardless of which filter is selected
        for filter in ClipboardContentFilter.allCases {
            let filterHosting = NSHostingView(
                rootView: ClipboardFilterPillsView(selection: filter, onSelect: { _ in })
                    .frame(width: NotchMetrics.contentWidth)
            )
            filterHosting.frame = NSRect(x: 0, y: 0, width: NotchMetrics.contentWidth, height: 100)
            filterHosting.layoutSubtreeIfNeeded()
            #expect(abs(filterHosting.fittingSize.height - notchFittingSize.height) <= 0.5)
        }

        // 4. Verify the view hierarchy contains an NSScrollView configured for horizontal scrolling without visible scrollers
        func findScrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView {
                return scroll
            }
            for subview in view.subviews {
                if let found = findScrollView(in: subview) {
                    return found
                }
            }
            return nil
        }

        let scrollView = try #require(findScrollView(in: constrainedHosting))
        #expect(scrollView.hasHorizontalScroller == false)
        #expect(scrollView.hasVerticalScroller == false)

        // 5. Verify pill titles match expected single-line strings and callback selection works
        #expect(pillsView.pillTitle(for: .images) == "Imágenes")
        #expect(pillsView.pillTitle(for: .pinned) == "Fijados")
        pillsView.onSelect(.images)
        #expect(selectedFilter == .images)
    }
}

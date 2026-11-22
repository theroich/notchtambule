//
//  NotchGeometry.swift
//  NotchTubeAudio
//

import AppKit

/// Shared sizing constants for the notch content.
enum NotchMetrics {
    /// Inner content width. DynamicNotchKit adds 15 pt of horizontal insets.
    static let contentWidth: CGFloat = 440
    static let queueRowHeight: CGFloat = 62
    static let clipboardRowHeight: CGFloat = 56
    static let queueListMaxHeight: CGFloat = 276
    static let queueHeaderHeight: CGFloat = 30
    static let clipboardControlsHeight: CGFloat = 64

    /// Extra distance around the notch that counts as "near the notch".
    static let triggerMargin: CGFloat = 15
    /// Extra distance around the expanded notch that keeps it open.
    static let retentionMargin: CGFloat = 25

    /// Fallback notch used on Macs without a camera housing.
    static let notchlessSize = CGSize(width: 220, height: 36)
}

/// Screen-space rectangles used by the global mouse monitor.
struct NotchGeometry {
    let screen: NSScreen
    let notchRect: CGRect
    let triggerRect: CGRect
    let retentionRect: CGRect

    static func make(for screen: NSScreen, contentSize: CGSize) -> NotchGeometry {
        let notchRect = Self.notchRect(for: screen)

        let triggerRect = notchRect.insetBy(
            dx: -NotchMetrics.triggerMargin,
            dy: -NotchMetrics.triggerMargin
        )

        // DynamicNotchKit adds 15 pt on the leading/trailing/bottom edges and
        // the physical notch height at the top.
        let expandedWidth = max(contentSize.width + 30, notchRect.width + 30)
        let expandedHeight = notchRect.height + max(contentSize.height, 60) + 30

        let expandedRect = CGRect(
            x: screen.frame.midX - expandedWidth / 2,
            y: screen.frame.maxY - expandedHeight,
            width: expandedWidth,
            height: expandedHeight
        )

        let retentionRect = expandedRect.insetBy(
            dx: -NotchMetrics.retentionMargin,
            dy: -NotchMetrics.retentionMargin
        )

        return NotchGeometry(
            screen: screen,
            notchRect: notchRect,
            triggerRect: triggerRect,
            retentionRect: retentionRect
        )
    }

    static func notchRect(for screen: NSScreen) -> CGRect {
        if
            let leftArea = screen.auxiliaryTopLeftArea,
            let rightArea = screen.auxiliaryTopRightArea
        {
            let computedWidth = screen.frame.width - leftArea.width - rightArea.width
            let height = max(screen.safeAreaInsets.top, 24)

            if computedWidth >= 80, computedWidth <= screen.frame.width {
                return CGRect(
                    x: screen.frame.midX - computedWidth / 2,
                    y: screen.frame.maxY - height,
                    width: computedWidth,
                    height: height
                )
            }
        }

        let fallback = NotchMetrics.notchlessSize
        return CGRect(
            x: screen.frame.midX - fallback.width / 2,
            y: screen.frame.maxY - fallback.height,
            width: fallback.width,
            height: fallback.height
        )
    }
}

extension NSScreen {
    /// `true` when the display has a camera housing.
    var nt_hasNotch: Bool {
        auxiliaryTopLeftArea != nil && auxiliaryTopRightArea != nil
    }
}

// OverlayWindow.swift
// Custom NSWindow subclass: transparent, borderless, always-on-top overlay.
//
// Transparency architecture:
//   The correct pattern for a "glass card" overlay on macOS is:
//     1. NSWindow with backgroundColor = .clear + isOpaque = false
//        → window backing store has an alpha channel
//     2. NSVisualEffectView as the root contentView
//        → provides real frosted-glass blending against the desktop
//        → rounded corners via layer.cornerRadius + masksToBounds
//     3. NSHostingView added as a subview of the visual effect view
//        → SwiftUI content draws on top of the glass background
//        → SwiftUI views should have .background(.clear) so they don't
//          paint over the visual effect
//
//   Using NSHostingView directly as contentView (without a visual effect view
//   beneath it) renders SwiftUI materials (.ultraThinMaterial etc.) as
//   transparent in non-bundle SwiftPM builds — the desktop doesn't show through
//   and nothing is visible. NSVisualEffectView is the reliable AppKit solution.

import AppKit
import SwiftUI

final class OverlayWindow: NSWindow {

    // Compact: single row/column of 5 icons.
    static let horizontalCompactSize = NSSize(width: 400, height: 100)
    static let verticalCompactSize   = NSSize(width: 100, height: 560)
    // Expanded: one large selected icon + four smaller grayed.
    static let horizontalExpandedSize = NSSize(width: 420, height: 220)
    static let verticalExpandedSize  = NSSize(width: 220, height: 450)

    static func size(for edge: DockSnapEdge, expanded: Bool = false) -> NSSize {
        if edge.isVertical {
            return expanded ? verticalExpandedSize : verticalCompactSize
        }
        return expanded ? horizontalExpandedSize : horizontalCompactSize
    }

    private weak var manager: OverlayWindowManager?

    // MARK: - Initialization

    init(manager: OverlayWindowManager) {
        self.manager = manager
        let initialSize = OverlayWindow.size(for: .bottom, expanded: false)
        let contentRect = NSRect(origin: .zero, size: initialSize)

        super.init(
            contentRect: contentRect,
            styleMask:   .borderless,
            backing:     .buffered,
            defer:       false
        )

        configureAppearance()
        configureWindowBehaviour()
        embedContent(manager: manager)
    }

    // MARK: - Appearance

    private func configureAppearance() {
        // Clear backing store — NSVisualEffectView will fill with frosted glass.
        backgroundColor = .clear
        isOpaque        = false
        hasShadow       = false
        alphaValue      = 1.0
    }

    // MARK: - Behaviour

    private func configureWindowBehaviour() {
        level = .floating

        collectionBehavior = [
            .canJoinAllSpaces,
            .transient,
            .ignoresCycle
        ]

        // CRITICAL: prevents deallocation when orderOut() is called.
        isReleasedWhenClosed = false

        // The whole overlay IS the shelf — drag anywhere to reposition.
        // SwiftUI tap gestures on the avatar icons still fire correctly
        // because interactive views take priority over window-background drag.
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents     = true
    }

    // MARK: - Content embedding

    private func embedContent(manager: OverlayWindowManager) {
        let size = OverlayWindow.size(for: .bottom, expanded: false)

        let vfv = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        vfv.material          = .hudWindow
        vfv.blendingMode      = .behindWindow
        vfv.state             = .active
        vfv.wantsLayer        = true
        vfv.layer?.cornerRadius  = 20
        vfv.layer?.masksToBounds = true
        vfv.layer?.borderWidth   = 0.0
        vfv.layer?.borderColor   = CGColor.clear
        vfv.autoresizingMask     = [.width, .height]

        let hostingView = NSHostingView(rootView: OverlayContentView(manager: manager))
        hostingView.frame            = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer       = true
        hostingView.layer?.backgroundColor = .clear

        vfv.addSubview(hostingView)
        contentView = vfv
    }

    // MARK: - NSWindow overrides

    override var canBecomeKey: Bool  { true  }
    override var canBecomeMain: Bool { false }
}

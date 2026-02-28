// OverlayWindowManager.swift
// Observable state controller for the overlay window's lifecycle and visibility.
// Handles snap-to-edge: when the user drags the dock near top/bottom/left/right,
// it snaps into place and (for left/right) switches to vertical icon layout.

import AppKit
import Observation

// MARK: - Snap edge

enum DockSnapEdge: Equatable {
    case bottom  // horizontal bar at bottom
    case top     // horizontal bar at top
    case left    // vertical stack on left
    case right   // vertical stack on right

    var isVertical: Bool {
        switch self {
        case .left, .right: return true
        case .bottom, .top: return false
        }
    }
}

// MARK: - Manager

@Observable
final class OverlayWindowManager {

    // MARK: - Observed state

    /// Whether the overlay window is currently shown on screen.
    private(set) var isVisible: Bool = false

    /// Current snap edge; determines dock layout (horizontal vs vertical) and position.
    private(set) var currentSnapEdge: DockSnapEdge = .bottom

    // MARK: - Private state

    private var overlayWindow: OverlayWindow?
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var isDragging = false

    /// Distance from screen edge (pt) within which we snap.
    private let snapThreshold: CGFloat = 80
    private let margin: CGFloat = 16

    // MARK: - Public API

    func createAndShowOverlay() {
        let window = OverlayWindow(manager: self)
        self.overlayWindow = window

        positionAtBottomCenter(window)
        window.makeKeyAndOrderFront(nil)
        isVisible = true

        setupDragMonitors()
    }

    func setVisible(_ visible: Bool) {
        guard let window = overlayWindow else { return }
        if visible {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderOut(nil)
        }
        isVisible = visible
    }

    func toggleVisibility() {
        setVisible(!isVisible)
    }

    /// Called when user releases mouse after dragging. Only snaps if the window
    /// is within snapThreshold of an edge; otherwise leaves it where the user dropped it.
    func snapIfNeeded() {
        guard isDragging, let window = overlayWindow else { return }
        isDragging = false

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let frame = window.frame

        let distLeft   = frame.minX - screenFrame.minX
        let distRight  = screenFrame.maxX - frame.maxX
        let distBottom = frame.minY - screenFrame.minY
        let distTop    = screenFrame.maxY - frame.maxY

        let nearLeft   = distLeft   < snapThreshold
        let nearRight  = distRight  < snapThreshold
        let nearBottom = distBottom < snapThreshold
        let nearTop    = distTop    < snapThreshold

        // Only snap when actually near at least one edge; otherwise leave window where it is.
        if !nearLeft && !nearRight && !nearBottom && !nearTop {
            currentSnapEdge = .bottom
            // If we were in vertical layout, resize back to horizontal and keep center.
            let horizontalSize = OverlayWindow.size(for: .bottom)
            if abs(window.frame.width - horizontalSize.width) > 1 {
                let centerX = frame.midX
                let centerY = frame.midY
                let newFrame = NSRect(
                    x: centerX - horizontalSize.width / 2,
                    y: centerY - horizontalSize.height / 2,
                    width: horizontalSize.width,
                    height: horizontalSize.height
                )
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(newFrame, display: true)
                }
            }
            return
        }

        let newEdge: DockSnapEdge
        let newFrame: NSRect

        if nearLeft && (distLeft <= distRight && distLeft <= distBottom && distLeft <= distTop) {
            newEdge = .left
            newFrame = frameFor(snapEdge: .left, screenFrame: screenFrame)
        } else if nearRight && (distRight <= distLeft && distRight <= distBottom && distRight <= distTop) {
            newEdge = .right
            newFrame = frameFor(snapEdge: .right, screenFrame: screenFrame)
        } else if nearTop && (nearBottom ? distTop <= distBottom : true) {
            newEdge = .top
            newFrame = frameFor(snapEdge: .top, screenFrame: screenFrame)
        } else {
            newEdge = .bottom
            newFrame = frameFor(snapEdge: .bottom, screenFrame: screenFrame)
        }

        currentSnapEdge = newEdge
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    func setDragging(_ dragging: Bool) {
        isDragging = dragging
    }

    // MARK: - Positioning

    private func frameFor(snapEdge edge: DockSnapEdge, screenFrame: NSRect) -> NSRect {
        let size = OverlayWindow.size(for: edge)
        switch edge {
        case .bottom:
            return NSRect(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.minY + margin,
                width: size.width,
                height: size.height
            )
        case .top:
            return NSRect(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.maxY - margin - size.height,
                width: size.width,
                height: size.height
            )
        case .left:
            return NSRect(
                x: screenFrame.minX + margin,
                y: screenFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .right:
            return NSRect(
                x: screenFrame.maxX - margin - size.width,
                y: screenFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    private func positionAtBottomCenter(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        window.setFrame(frameFor(snapEdge: .bottom, screenFrame: screen.visibleFrame), display: true)
    }

    private func setupDragMonitors() {
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let window = self.overlayWindow else { return event }
            let screenLoc = NSEvent.mouseLocation
            let windowFrame = window.frame
            if windowFrame.contains(CGPoint(x: screenLoc.x, y: screenLoc.y)) {
                self.isDragging = true
            }
            return event
        }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.snapIfNeeded()
            return event
        }
    }

    deinit {
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m) }
        if let m = mouseUpMonitor { NSEvent.removeMonitor(m) }
    }
}

// OverlayWindowManager.swift
// Observable state controller for the overlay window's lifecycle and visibility.
//
// This class is the single source of truth for whether the overlay is shown.
// It owns the OverlayWindow instance so the window is never deallocated while
// the app is running — important because borderless NSWindows with
// isReleasedWhenClosed = false rely on a strong external owner.
//
// @Observable (Observation framework, macOS 14+) lets SwiftUI views observe
// `isVisible` changes without using @Published / ObservableObject boilerplate.

import AppKit
import Observation

@Observable
final class OverlayWindowManager {

    // MARK: - Observed state

    /// Whether the overlay window is currently shown on screen.
    private(set) var isVisible: Bool = false

    // MARK: - Private state

    /// The single overlay NSWindow instance. Created once; never recreated.
    private var overlayWindow: OverlayWindow?

    // MARK: - Public API

    /// Creates the overlay window and displays it for the first time.
    /// Call this once from AppDelegate.applicationDidFinishLaunching.
    func createAndShowOverlay() {
        let window = OverlayWindow()
        self.overlayWindow = window

        // Position centred at the bottom of the screen, above the Dock.
        positionAtBottomCenter(window)

        // Show the window and make it capable of receiving keyboard focus
        // (required for the TextField in the chat bar).
        window.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    /// Shows or hides the overlay.
    func setVisible(_ visible: Bool) {
        guard let window = overlayWindow else { return }
        if visible {
            window.makeKeyAndOrderFront(nil)
        } else {
            // orderOut removes the window from the screen without deallocating it
            // (because isReleasedWhenClosed = false on OverlayWindow).
            window.orderOut(nil)
        }
        isVisible = visible
    }

    /// Toggles overlay visibility.
    func toggleVisibility() {
        setVisible(!isVisible)
    }

    // MARK: - Positioning

    /// Places the shelf centred horizontally, just above the Dock.
    private func positionAtBottomCenter(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame   // excludes menu bar + Dock
        let windowSize  = window.frame.size
        let margin: CGFloat = 16

        let x = screenFrame.midX - windowSize.width  / 2
        let y = screenFrame.minY + margin

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

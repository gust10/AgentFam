// AgentPersonalizationWindow.swift
// Standard titled macOS window that hosts the agent personalisation screen.
//
// Uses a static `show()` entry point so callers never need to cast NSApp.delegate.
// Handles the accessory-app activation dance: temporarily switch to .regular so
// the window can become key, then revert to .accessory when it closes.

import AppKit
import SwiftUI

final class AgentPersonalizationWindow: NSWindow, NSWindowDelegate {

    // Retained singleton — created once, reused on every subsequent open.
    private static var instance: AgentPersonalizationWindow?

    // MARK: - Public API

    /// Shows the personalisation window, creating it on the first call.
    /// Safe to call from any SwiftUI button action on the main thread.
    static func show() {
        if instance == nil {
            instance = AgentPersonalizationWindow()
        }
        // Accessory apps need a momentary activation-policy switch to bring a
        // standard window to front and make it key.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        instance?.makeKeyAndOrderFront(nil)
        instance?.orderFrontRegardless()   // belt-and-suspenders
    }

    // MARK: - Init

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask:   [.titled, .closable, .resizable, .miniaturizable],
            backing:     .buffered,
            defer:       false
        )

        title                = "Personalize Agents"
        isReleasedWhenClosed = false          // keep alive for re-open
        minSize              = NSSize(width: 620, height: 440)
        contentView          = NSHostingView(rootView: AgentPersonalizationView())
        delegate             = self
        center()
    }

    // MARK: - NSWindowDelegate

    /// When the user closes the window, revert to accessory mode so the dock
    /// icon disappears again and the app behaves like a background agent.
    func windowWillClose(_ notification: Notification) {
        // Short delay so the window finishes closing before policy switches.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

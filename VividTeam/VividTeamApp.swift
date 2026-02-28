// VividTeamApp.swift
// The @main entry point for VividTeam.
//
// Design rationale:
//   - We use @NSApplicationDelegateAdaptor to hook into AppKit's application
//     lifecycle. All window creation, status item setup, and hotkey registration
//     happen in AppDelegate.
//   - The `body` returns `Settings { EmptyView() }` — the idiomatic no-op scene
//     for menu-bar-only / overlay apps. Using WindowGroup here would spawn an
//     unwanted standard window that we'd have to immediately close.
//   - LSUIElement = YES in Info.plist (and NSApp.setActivationPolicy(.accessory)
//     in AppDelegate) suppress the dock icon and standard menu bar.
//
// Minimum macOS 14.0 is required for the @Observable macro used in
// OverlayWindowManager.

import SwiftUI

@main
struct VividTeamApp: App {

    // AppKit delegate — owns the overlay window, status item, and hotkey monitor.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No WindowGroup — the overlay is created imperatively by AppDelegate.
        // Settings{} is the minimal valid Scene body; it produces no visible UI.
        Settings {
            EmptyView()
        }
    }
}

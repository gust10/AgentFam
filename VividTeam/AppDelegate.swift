// AppDelegate.swift
// Central coordinator for VividTeam's AppKit lifecycle.
//
// Responsibilities:
//   1. Suppresses dock icon at runtime (belt-and-suspenders with LSUIElement).
//   2. Creates and owns the OverlayWindowManager (which creates OverlayWindow).
//   3. Builds the NSStatusItem (tray icon) with a Show / Hide / Quit menu.
//   4. Installs global + local NSEvent monitors for the Cmd+Shift+A hotkey.
//
// Threading:
//   AppKit delegate callbacks arrive on the main thread. The global NSEvent
//   monitor closure fires on a background thread — we always dispatch back to
//   DispatchQueue.main before touching AppKit objects.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Owned objects

    /// Manages the overlay NSWindow lifecycle and visibility state.
    private var windowManager: OverlayWindowManager?

    /// The status bar (tray) item displayed in the macOS menu bar.
    private var statusItem: NSStatusItem?

    /// Token returned by addGlobalMonitorForEvents — must be removed on teardown.
    private var globalHotkeyMonitor: Any?

    /// Token for the local monitor (fires when VividTeam itself is frontmost).
    private var localHotkeyMonitor: Any?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Enforce accessory (agent) mode so no dock icon appears.
        //    LSUIElement = YES in Info.plist sets this statically; calling it here
        //    programmatically is belt-and-suspenders for SwiftUI's App wrapper.
        NSApp.setActivationPolicy(.accessory)

        // 2. Create the overlay window manager and show the overlay.
        let manager = OverlayWindowManager()
        self.windowManager = manager
        manager.createAndShowOverlay()

        // 3. Build the status bar item.
        setupStatusItem()

        // 4. Register global + local keyboard monitors for Cmd+Shift+A.
        setupHotkeyMonitors()

        // 5. Start the health-reminder scheduler (fires every 30 min).
        HealthReminderScheduler.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // NSEvent monitors are global resources — always clean up to avoid leaks.
        if let monitor = globalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        HealthReminderScheduler.shared.stop()
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // SF Symbol template image — renders correctly in both light and dark menubar.
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "person.crop.circle",
                                   accessibilityDescription: "VividTeam")
            button.image?.isTemplate = true   // allows macOS to tint the icon
            button.toolTip = "VividTeam"
        }

        // Build the dropdown menu.
        let menu = NSMenu(title: "VividTeam")

        let showItem = NSMenuItem(title: "Show Overlay",
                                  action: #selector(showOverlay),
                                  keyEquivalent: "")
        showItem.target = self

        let hideItem = NSMenuItem(title: "Hide Overlay",
                                  action: #selector(hideOverlay),
                                  keyEquivalent: "")
        hideItem.target = self

        menu.addItem(showItem)
        menu.addItem(hideItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit VividTeam",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q")
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
    }

    @objc private func showOverlay() {
        windowManager?.setVisible(true)
    }

    @objc private func hideOverlay() {
        windowManager?.setVisible(false)
    }

    // MARK: - Hotkey Monitors

    private func setupHotkeyMonitors() {
        // The virtual key code for the 'A' key (kVK_ANSI_A) is 0x00 = 0.
        // We check for Cmd + Shift modifiers (device-independent mask) only.
        let targetKeyCode: UInt16 = 0
        let targetModifiers: NSEvent.ModifierFlags = [.command, .shift]

        // -- Global monitor: fires when another app is frontmost.
        //    NOTE: Requires Accessibility permission granted in
        //    System Settings > Privacy & Security > Accessibility.
        //    The call returns nil (silently) if permission is not granted.
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == targetModifiers && event.keyCode == targetKeyCode {
                // Must dispatch to main — this closure runs on a background thread.
                DispatchQueue.main.async {
                    self?.windowManager?.toggleVisibility()
                }
            }
        }

        // -- Local monitor: fires when VividTeam itself is frontmost.
        //    Returns nil to consume the event so it doesn't propagate further.
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == targetModifiers && event.keyCode == targetKeyCode {
                self?.windowManager?.toggleVisibility()
                return nil   // consume: prevent the 'a' keystroke from typing
            }
            return event
        }
    }
}

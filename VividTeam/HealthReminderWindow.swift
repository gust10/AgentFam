// HealthReminderWindow.swift
// Floating glass-card popup for health nudges (stretch, water, eye rest, …).
//
// Architecture mirrors OverlayWindow:
//   NSWindow (borderless, clear) → NSVisualEffectView (glass) → NSHostingView (SwiftUI)
//
// The window auto-dismisses after a countdown driven by HealthReminderView.
// A new call to show() while one is already visible replaces it immediately.

import AppKit
import SwiftUI

// MARK: - Window

final class HealthReminderWindow: NSWindow {

    private static var current: HealthReminderWindow?

    // MARK: Public API

    static func show(reminder: HealthReminder) {
        // Replace any existing popup so we don't stack up.
        current?.orderOut(nil)

        let win = HealthReminderWindow(reminder: reminder)
        current = win

        // Position: top-right of the main screen, just below the menu bar.
        if let screen = NSScreen.main {
            let margin: CGFloat = 16
            let x = screen.visibleFrame.maxX - win.frame.width  - margin
            let y = screen.visibleFrame.maxY - win.frame.height - margin
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }

        win.orderFrontRegardless()
    }

    // MARK: Init

    private init(reminder: HealthReminder) {
        let size = NSSize(width: 350, height: 92)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask:   .borderless,
            backing:     .buffered,
            defer:       false
        )

        backgroundColor         = .clear
        isOpaque                = false
        hasShadow               = true
        level                   = .floating
        isReleasedWhenClosed    = false
        collectionBehavior      = [.canJoinAllSpaces, .transient, .ignoresCycle]

        // ── Glass background ─────────────────────────────────────────────────
        let vfv = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        vfv.material          = .hudWindow
        vfv.blendingMode      = .behindWindow
        vfv.state             = .active
        vfv.wantsLayer        = true
        vfv.layer?.cornerRadius   = 16
        vfv.layer?.masksToBounds  = true
        vfv.layer?.borderWidth    = 0
        vfv.layer?.borderColor    = CGColor.clear
        vfv.autoresizingMask      = [.width, .height]

        // ── SwiftUI content ──────────────────────────────────────────────────
        let dismiss: () -> Void = { [weak self] in self?.close() }
        let rootView = HealthReminderView(reminder: reminder, onDismiss: dismiss)

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame            = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer       = true
        hosting.layer?.backgroundColor = .clear

        vfv.addSubview(hosting)
        contentView = vfv
    }

    // Smooth fade-out on close
    override func close() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            self.animator().alphaValue = 0
        } completionHandler: {
            super.close()
            self.alphaValue = 1
        }
    }
}

// MARK: - SwiftUI Content

private struct HealthReminderView: View {

    let reminder:  HealthReminder
    let onDismiss: () -> Void

    // Countdown: 1.0 → 0.0 over `duration` seconds
    @State private var progress:  CGFloat = 1.0
    @State private var appeared:  Bool    = false

    private let duration: TimeInterval = 9.0

    var body: some View {
        VStack(spacing: 0) {
            // ── Main row ─────────────────────────────────────────────────────
            HStack(spacing: 14) {

                // Icon badge
                Image(systemName: reminder.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tintColor)
                    .frame(width: 44, height: 44)
                    .background(tintColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(reminder.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                // Dismiss ×
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.secondary.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // ── Countdown bar ─────────────────────────────────────────────────
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.12))
                    Capsule()
                        .fill(tintColor.opacity(0.55))
                        .frame(width: geo.size.width * progress)
                        .animation(.linear(duration: duration), value: progress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 0)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -12)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                appeared = true
            }
            // Start the countdown bar (needs a tiny delay so the animation fires)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                progress = 0
            }
            // Auto-dismiss when bar reaches zero
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                onDismiss()
            }
        }
    }

    /// Maps the tint string from HealthReminder to a SwiftUI Color.
    private var tintColor: Color {
        switch reminder.tint {
        case "green":  return .green
        case "blue":   return .blue
        case "purple": return .purple
        case "cyan":   return .cyan
        case "orange": return .orange
        case "yellow": return .yellow
        default:       return .accentColor
        }
    }
}

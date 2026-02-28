// AlertOverlayWindow.swift
// Large center-screen alert panel with a red urgent style.
// Use AlertOverlayWindow.show(title:message:) from anywhere.

import AppKit
import SwiftUI

// MARK: - Window

final class AlertOverlayWindow: NSWindow {

    private static var current: AlertOverlayWindow?

    // MARK: Public API

    /// Shows a full-center alert, replacing any existing one.
    static func show(title: String, message: String) {
        current?.orderOut(nil)
        current = nil

        let win = AlertOverlayWindow(title: title, message: message)
        current = win

        // Center on main screen
        if let screen = NSScreen.main {
            let sf = screen.frame
            let x  = sf.midX - win.frame.width  / 2
            let y  = sf.midY - win.frame.height / 2
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }

        win.orderFrontRegardless()
    }

    // MARK: Init

    private init(title: String, message: String) {
        let size = NSSize(width: 480, height: 300)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask:   .borderless,
            backing:     .buffered,
            defer:       false
        )

        backgroundColor      = .clear
        isOpaque             = false
        hasShadow            = true
        level                = .modalPanel      // above everything except system UI
        isReleasedWhenClosed = false
        collectionBehavior   = [.canJoinAllSpaces, .transient, .ignoresCycle]

        // ── Glass base ───────────────────────────────────────────────────────
        let vfv = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        vfv.material         = .hudWindow
        vfv.blendingMode     = .behindWindow
        vfv.state            = .active
        vfv.wantsLayer       = true
        vfv.layer?.cornerRadius  = 24
        vfv.layer?.masksToBounds = true
        vfv.layer?.borderWidth   = 0
        vfv.layer?.borderColor   = CGColor.clear
        vfv.autoresizingMask     = [.width, .height]

        // ── SwiftUI content ──────────────────────────────────────────────────
        let dismiss: () -> Void = { [weak self] in
            self?.animateClose()
        }
        let root = AlertOverlayView(title: title, message: message, onDismiss: dismiss)

        let hosting = NSHostingView(rootView: root)
        hosting.frame            = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer       = true
        hosting.layer?.backgroundColor = .clear

        vfv.addSubview(hosting)
        contentView = vfv

        // Slide-in from slight offset when the window first appears
        alphaValue = 0
    }

    // Called right after the window is ordered front
    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            self.animator().alphaValue = 1
        }
    }

    fileprivate func animateClose() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            self.animator().alphaValue = 0
        } completionHandler: {
            self.orderOut(nil)
            AlertOverlayWindow.current = nil
        }
    }
}

// MARK: - SwiftUI View

private struct AlertOverlayView: View {

    let title:     String
    let message:   String
    let onDismiss: () -> Void

    @State private var appeared  = false
    @State private var pulsing   = false

    var body: some View {
        ZStack {
            // Red tint wash over the glass
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.red.opacity(0.07))
                .ignoresSafeArea()

            // Thin red border
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.red.opacity(0.35), lineWidth: 1.5)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                Spacer()

                // ── Icon ─────────────────────────────────────────────────────
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(pulsing ? 0.18 : 0.10))
                        .frame(width: 90, height: 90)
                        .scaleEffect(pulsing ? 1.12 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                            value: pulsing
                        )

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(Color.red)
                        .symbolRenderingMode(.hierarchical)
                }
                .padding(.bottom, 18)

                // ── Title ─────────────────────────────────────────────────────
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // ── Message ───────────────────────────────────────────────────
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)

                Spacer()

                // ── Dismiss button ────────────────────────────────────────────
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 140, height: 38)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .keyboardShortcut(.return, modifiers: [])
                .padding(.bottom, 28)
            }
        }
        .scaleEffect(appeared ? 1 : 0.88)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) {
                appeared = true
            }
            pulsing = true
        }
    }
}

// ConvAIChatWindow.swift
// Floating glass chat panel that appears above the dock shelf during a conversation.
// Shows user speech (right, blue) and agent speech (left) as it arrives.

import AppKit
import SwiftUI

// MARK: - Mutable display state (separate from ConvAI so agentName/color can update)

@Observable
final class ChatDisplayState {
    var agentName:  String = "Agent"
    var agentColor: Color  = .cyan
}

// MARK: - Window

final class ConvAIChatWindow: NSPanel {

    private static var shared: ConvAIChatWindow?

    // Show or create the panel, updating the agent identity if it changed.
    static func show(convAI: ElevenLabsConvAI, agentName: String, agentColor: Color) {
        if let win = shared {
            win.displayState.agentName  = agentName
            win.displayState.agentColor = agentColor
            win.orderFront(nil)
        } else {
            let win = ConvAIChatWindow(convAI: convAI, agentName: agentName, agentColor: agentColor)
            shared = win
            win.orderFront(nil)
        }
    }

    static func hide() { shared?.orderOut(nil) }

    // MARK: -

    private static let size = NSSize(width: 390, height: 300)
    private let displayState = ChatDisplayState()

    private init(convAI: ElevenLabsConvAI, agentName: String, agentColor: Color) {
        displayState.agentName  = agentName
        displayState.agentColor = agentColor

        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )

        backgroundColor          = .clear
        isOpaque                 = false
        hasShadow                = true
        level                    = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed     = false
        collectionBehavior       = [.canJoinAllSpaces, .transient, .ignoresCycle]

        embedContent(convAI: convAI)
        positionAboveDock()
    }

    private func embedContent(convAI: ElevenLabsConvAI) {
        let sz  = Self.size
        let vfv = NSVisualEffectView(frame: NSRect(origin: .zero, size: sz))
        vfv.material          = .hudWindow
        vfv.blendingMode      = .behindWindow
        vfv.state             = .active
        vfv.wantsLayer        = true
        vfv.layer?.cornerRadius  = 18
        vfv.layer?.masksToBounds = true
        vfv.autoresizingMask  = [.width, .height]

        let rootView    = ChatPanelView(convAI: convAI, display: displayState)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame            = NSRect(origin: .zero, size: sz)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer       = true
        hostingView.layer?.backgroundColor = .clear

        vfv.addSubview(hostingView)
        contentView = vfv
    }

    private func positionAboveDock() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let x  = sf.midX - Self.size.width / 2
        let y  = sf.minY + 16 + 140 + 8     // margin + dock height + gap
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override var canBecomeKey:  Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Root SwiftUI view

private struct ChatPanelView: View {
    let convAI:  ElevenLabsConvAI
    let display: ChatDisplayState

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────────
            HStack(spacing: 6) {
                Circle()
                    .fill(display.agentColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: display.agentColor.opacity(0.7), radius: 3)
                Text(display.agentName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Conversation")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider().opacity(0.3)

            // ── Messages ─────────────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if convAI.messages.isEmpty {
                            Text("Start talking…")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 20)
                        }
                        ForEach(convAI.messages) { msg in
                            BubbleRow(msg: msg, agentName: display.agentName, agentColor: display.agentColor)
                                .id(msg.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .onChange(of: convAI.messages.count) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Bubble row

private struct BubbleRow: View {
    let msg:        ConvAIMessage
    let agentName:  String
    let agentColor: Color

    private var isUser: Bool { msg.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 56) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                // Sender label
                Text(isUser ? "You" : agentName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isUser ? Color.blue.opacity(0.7) : agentColor.opacity(0.85))
                    .padding(isUser ? .trailing : .leading, 4)

                // Bubble
                Text(msg.text)
                    .font(.system(size: 12))
                    .foregroundStyle(isUser ? .white : .primary)
                    .multilineTextAlignment(isUser ? .trailing : .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isUser
                                  ? AnyShapeStyle(Color.blue)
                                  : AnyShapeStyle(Color.primary.opacity(0.07)))
                    )
            }

            if !isUser { Spacer(minLength: 56) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.85,
                                  anchor: isUser ? .bottomTrailing : .bottomLeading)
                    .combined(with: .opacity),
                removal: .opacity
            )
        )
    }
}

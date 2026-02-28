// OverlayContentView.swift
// The overlay is now just the glass dock shelf — nothing else.
// Drag anywhere on the shelf to reposition (isMovableByWindowBackground = true
// on OverlayWindow handles this at the AppKit level, no DragHandleView needed).

import SwiftUI
import AppKit

struct OverlayContentView: View {

    let manager: OverlayWindowManager

    @State private var selectedAgentID: String? = nil
    @State private var convAI: ElevenLabsConvAI? = nil

    var body: some View {
        Group {
            if manager.isCollapsed {
                PeekStripView(snapEdge: manager.currentSnapEdge, onTap: { manager.expand() })
            } else {
                dockContent
            }
        }
        .onAppear { manager.setHasSelection(selectedAgentID != nil) }
    }

    private var dockContent: some View {
        VStack(spacing: 0) {
            if let convAI {
                ConvAIStatusStrip(state: convAI.state,
                                  agentText: convAI.agentText,
                                  userText:  convAI.userText)
            }
            AgentDockView(
                selectedID: $selectedAgentID,
                snapEdge: manager.currentSnapEdge,
                onInteraction: { manager.reportInteraction() }
            )
        }
        .overlay(alignment: .topTrailing) {
            if selectedAgentID == nil {
                Button {
                    manager.collapse()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if selectedAgentID == nil {
                Button {
                    AgentPersonalizationWindow.show()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
        .onChange(of: selectedAgentID) { _, newID in
            manager.setHasSelection(newID != nil)
            // Always stop the previous conversation first
            convAI?.stop()

            if let id = newID,
               let agent = AgentDockView.catalogue.first(where: { $0.id == id }) {
                let fresh = ElevenLabsConvAI(config: ElevenLabsConvAIConfig(
                    apiKey:       Secrets.elevenLabsAPIKey,
                    profileID:    agent.id,
                    voiceID:      agent.voiceID,
                    systemPrompt: agent.systemPrompt,
                    firstMessage: agent.firstMessage
                ))
                convAI = fresh
                fresh.start()
                ConvAIChatWindow.show(
                    convAI:     fresh,
                    agentName:  agent.fullName,
                    agentColor: agent.color
                )
            } else {
                convAI = nil
                ConvAIChatWindow.hide()
            }
        }
        // Right-click anywhere on the shelf → personalise, hide, or quit.
        .contextMenu {
                Button("Personalize Agents…") {
                    AgentPersonalizationWindow.show()
                }
                Button("Test Health Reminder") {
                    HealthReminderScheduler.shared.showNow()
                }
                Button("Test Alert") {
                    AlertOverlayWindow.show(
                        title:   "Urgent Alert",
                        message: "Something needs your immediate attention. Take a moment to address it before continuing."
                    )
                }
                Divider()
                Button("Hide") {
                    NSApp.windows.first { $0 is OverlayWindow }?.orderOut(nil)
                }
                Divider()
                Button("Quit VividTeam") { NSApp.terminate(nil) }
            }
    }
}

// MARK: - Peek strip (collapsed dock: small arrow at edge)

private struct PeekStripView: View {
    let snapEdge: DockSnapEdge
    let onTap: () -> Void

    private var chevronName: String {
        switch snapEdge {
        case .bottom: return "chevron.up"
        case .top:    return "chevron.down"
        case .left:   return "chevron.right"
        case .right:  return "chevron.left"
        }
    }

    var body: some View {
        Button(action: onTap) {
            Image(systemName: chevronName)
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Conversation status strip

private struct ConvAIStatusStrip: View {
    let state:     ElevenLabsConvAI.State
    let agentText: String
    let userText:  String

    private var label: String {
        switch state {
        case .provisioning:  return "Setting up agent…"
        case .connecting:    return "Connecting…"
        case .listening:     return userText.isEmpty ? "Listening…" : userText
        case .agentSpeaking: return agentText.isEmpty ? "Speaking…"  : agentText
        case .idle:          return ""
        }
    }

    private var dotColor: Color {
        switch state {
        case .provisioning:  return .yellow
        case .connecting:    return .orange
        case .listening:     return .green
        case .agentSpeaking: return .cyan
        case .idle:          return .gray
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .shadow(color: dotColor.opacity(0.8), radius: 3)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.2), value: label)
    }
}

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
        VStack(spacing: 0) {
            // ── Conversation status strip (visible only when an agent is active) ──
            if let convAI {
                ConvAIStatusStrip(state: convAI.state,
                                  agentText: convAI.agentText,
                                  userText:  convAI.userText)
            }
            AgentDockView(selectedID: $selectedAgentID, snapEdge: manager.currentSnapEdge)
        }
        .onChange(of: selectedAgentID) { _, newID in
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

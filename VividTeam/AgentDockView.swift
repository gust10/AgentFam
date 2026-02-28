// AgentDockView.swift
// macOS Dock-style horizontal strip of agent selectors.
// Human face avatars from HumanAvatarView replace icon glyphs.

import SwiftUI

// MARK: - Data model

struct AgentProfile: Identifiable {
    let id:          String
    let name:        String        // Short dock label
    let fullName:    String        // Full display name for the detail panel
    let description: String        // Role subtitle / tooltip
    let color:       Color         // Accent colour for glow / dot
    let avatarStyle: AvatarStyle   // Links to HumanAvatarView
    // ── Per-agent ElevenLabs config ──────────────────────────────────────────
    let voiceID:      String       // ElevenLabs voice ID
    let systemPrompt: String       // LLM system prompt
    let firstMessage: String       // Agent greeting
}

// MARK: - Dock view

struct AgentDockView: View {

    @Binding var selectedID: String?

    /// Shared catalogue — also consumed by ActiveAgentView.
    static let catalogue: [AgentProfile] = [
        AgentProfile(
            id: "alex", name: "Alex", fullName: "Alex Chen", description: "Code & debug",
            color: .cyan, avatarStyle: .alex,
            voiceID:      "pNInz6obpgDQGcFmaJgB",  // Adam — deep, authoritative male
            systemPrompt: "You are Alex Chen, a sharp software engineer specializing in code review, debugging, and technical architecture. Give concise, precise answers focused on correctness and performance. Be direct and technical.",
            firstMessage: "Hey! Ready to debug or review some code?"
        ),
        AgentProfile(
            id: "maya", name: "Maya", fullName: "Maya Patel", description: "UI & visuals",
            color: .pink, avatarStyle: .maya,
            voiceID:      "MF3mGyEYCl7XYWbV9V6O",  // Elli — young, energetic female
            systemPrompt: "You are Maya Patel, a creative UI/UX designer with a strong eye for aesthetics, color theory, and user experience. Be warm, enthusiastic, and visually imaginative in your responses.",
            firstMessage: "Hi there! Got something to design or make beautiful?"
        ),
        AgentProfile(
            id: "sam", name: "Sam", fullName: "Sam Okafor", description: "Web research",
            color: .green, avatarStyle: .sam,
            voiceID:      "ErXwobaYiN019PkySvjV",  // Antoni — well-rounded, clear male
            systemPrompt: "You are Sam Okafor, a thorough web researcher who excels at finding information, synthesizing sources, and summarizing complex topics clearly. Be curious, methodical, and always provide helpful context.",
            firstMessage: "Hello! What would you like me to research today?"
        ),
        AgentProfile(
            id: "kai", name: "Kai", fullName: "Kai Yamamoto", description: "Data analysis",
            color: .orange, avatarStyle: .kai,
            voiceID:      "21m00Tcm4TlvDq8ikWAM",  // Rachel — calm, professional female
            systemPrompt: "You are Kai Yamamoto, a methodical data analyst with expertise in statistics, patterns, and data visualization. Explain data concepts with precision and clarity. Be analytical, thoughtful, and grounded in evidence.",
            firstMessage: "Hi! Let's dig into some data. What are you analyzing?"
        ),
        AgentProfile(
            id: "lee", name: "Lee", fullName: "Lee Russo", description: "Run scripts",
            color: .purple, avatarStyle: .lee,
            voiceID:      "VR6AewLTigWG4xSOukaG",  // Arnold — crisp, confident male
            systemPrompt: "You are Lee Russo, an automation and scripting specialist. You write and debug shell scripts, automate workflows, and handle DevOps tasks. Be efficient, practical, and solution-focused.",
            firstMessage: "Hey! Got a script to write or a workflow to automate?"
        ),
    ]

    @State private var hoveredID: String?

    var body: some View {
        // The window IS the shelf — fill the whole space, no outer spacers.
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Self.catalogue) { agent in
                DockIconView(
                    agent:      agent,
                    isSelected: selectedID == agent.id,
                    isHovered:  hoveredID  == agent.id
                )
                .onTapGesture { selectedID = (selectedID == agent.id) ? nil : agent.id }
                .onHover      { hoveredID  = $0 ? agent.id : nil }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Single dock icon

private struct DockIconView: View {

    let agent:      AgentProfile
    let isSelected: Bool
    let isHovered:  Bool

    private var scale: CGFloat {
        if isHovered  { return 1.28 }
        if isSelected { return 1.12 }
        return 1.0
    }

    var body: some View {
        VStack(spacing: 3) {

            // ── Avatar ───────────────────────────────────────────────────
            ZStack {
                // Selection glow ring
                Circle()
                    .strokeBorder(agent.color.opacity(isSelected ? 0.75 : 0), lineWidth: 2.5)
                    .frame(width: 66, height: 66)
                    .shadow(color: agent.color.opacity(isSelected ? 0.5 : 0), radius: 10)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)

                // Human face
                HumanAvatarView(style: agent.avatarStyle)
                    .frame(width: 58, height: 58)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                    .shadow(
                        color: .black.opacity(isHovered ? 0.38 : 0.22),
                        radius: isHovered ? 10 : 5, y: 3
                    )
            }
            .frame(width: 66, height: 66)
            .scaleEffect(scale, anchor: .bottom)
            .animation(.spring(response: 0.22, dampingFraction: 0.60), value: isHovered)
            .animation(.spring(response: 0.22, dampingFraction: 0.60), value: isSelected)

            // ── Name label ───────────────────────────────────────────────
            Text(agent.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(
                    (isSelected || isHovered)
                        ? Color.primary.opacity(0.9)
                        : Color.secondary.opacity(0.55)
                )
                .animation(.easeInOut(duration: 0.15), value: isHovered)

            // ── Active dot ───────────────────────────────────────────────
            Circle()
                .fill(agent.color)
                .frame(width: 5, height: 5)
                .shadow(color: agent.color.opacity(0.7), radius: 3)
                .opacity(isSelected ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: isSelected)
        }
        .help("\(agent.fullName) · \(agent.description)")
    }
}

// ActiveAgentView.swift
// The content panel between the agent dock and the chat bar.
// Shows a large avatar + info when an agent is selected;
// shows a calm empty state when none is selected.

import SwiftUI

struct ActiveAgentView: View {
    let selectedID: String?

    // Keep in sync with AgentDockView's agent list.
    private let agents: [AgentProfile] = AgentDockView.catalogue

    private var selected: AgentProfile? {
        agents.first { $0.id == selectedID }
    }

    var body: some View {
        ZStack {
            if let agent = selected {
                selectedView(agent)
                    .transition(.asymmetric(
                        insertion:  .scale(scale: 0.85).combined(with: .opacity),
                        removal:    .opacity
                    ))
            } else {
                emptyState
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selectedID)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Selected agent

    private func selectedView(_ agent: AgentProfile) -> some View {
        VStack(spacing: 12) {

            Spacer(minLength: 0)

            // Large avatar with animated ring
            ZStack {
                // Glowing ring behind avatar
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [agent.color, agent.color.opacity(0.2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: agent.color.opacity(0.4), radius: 12)

                if let iconName = agent.iconName,
                   let img = Bundle.module.url(forResource: iconName, withExtension: "png"),
                   let nsImage = NSImage(contentsOf: img) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 86, height: 86)
                        .clipShape(Circle())
                } else {
                    HumanAvatarView(style: agent.avatarStyle)
                        .frame(width: 86, height: 86)
                        .clipShape(Circle())
                }
            }

            // Name + role
            VStack(spacing: 3) {
                Text(agent.fullName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(agent.description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            // Status pill
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .shadow(color: .green.opacity(0.8), radius: 3)
                Text("Ready")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.green.opacity(0.12), in: Capsule())

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            // Overlapping mini-avatars hint
            ZStack {
                ForEach(Array(agents.prefix(4).enumerated()), id: \.offset) { index, agent in
                    if let iconName = agent.iconName,
                       let img = Bundle.module.url(forResource: iconName, withExtension: "png"),
                       let nsImage = NSImage(contentsOf: img) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 1))
                            .offset(x: CGFloat(index) * 20 - 30)
                    } else {
                        HumanAvatarView(style: agent.avatarStyle)
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 1))
                            .offset(x: CGFloat(index) * 20 - 30)
                    }
                }
            }
            .frame(height: 38)

            Text("Pick an agent below")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Each agent specialises in a different task.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

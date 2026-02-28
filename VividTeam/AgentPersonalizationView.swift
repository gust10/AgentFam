// AgentPersonalizationView.swift
// Full-screen panel for customising each agent's name, role, and system prompt.
// Opened via right-click → "Personalize Agents…" on the dock shelf.
//
// Persistence: each agent's customisation is encoded as JSON and stored in
// UserDefaults under the key "agent_<id>" so edits survive app restarts.

import SwiftUI

// MARK: - Mutable data model for one agent

struct AgentCustomization: Codable {
    var name:         String
    var fullName:     String
    var description:  String
    var systemPrompt: String
}

// MARK: - Root view

struct AgentPersonalizationView: View {

    // Sidebar selection — default to first agent
    @State private var selectedID: String = AgentDockView.catalogue.first?.id ?? ""

    // In-memory edits for each agent; loaded from UserDefaults on appear
    @State private var edits: [String: AgentCustomization] = [:]

    var body: some View {
        NavigationSplitView {
            agentSidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            agentEditor
        }
        .onAppear { edits = Self.loadAll() }
    }

    // MARK: - Sidebar

    private var agentSidebar: some View {
        List(AgentDockView.catalogue, selection: $selectedID) { agent in
            HStack(spacing: 12) {
                HumanAvatarView(style: agent.avatarStyle)
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(edits[agent.id]?.name ?? agent.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(edits[agent.id]?.description ?? agent.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 4)
            .tag(agent.id)
        }
        .listStyle(.sidebar)
        .navigationTitle("Agents")
    }

    // MARK: - Editor panel

    @ViewBuilder
    private var agentEditor: some View {
        if let agent = AgentDockView.catalogue.first(where: { $0.id == selectedID }) {
            let binding = Binding<AgentCustomization>(
                get: { edits[agent.id] ?? Self.defaultCustomization(for: agent) },
                set: { edits[agent.id] = $0 }
            )
            AgentEditorPanel(agent: agent, customization: binding)
                .id(agent.id)          // force re-render when selection changes
        }
    }

    // MARK: - Persistence helpers

    static func defaultCustomization(for agent: AgentProfile) -> AgentCustomization {
        let prompts: [String: String] = [
            "alex": "You are Alex Chen, a senior software engineer. You write clean, efficient code and excel at debugging complex issues. Be precise, technical, and solution-focused.",
            "maya": "You are Maya Patel, a UI/UX designer and front-end developer. You have a keen eye for aesthetics and usability. Provide creative, user-centered design guidance.",
            "sam":  "You are Sam Okafor, a research specialist. You find accurate, up-to-date information quickly and synthesise it into clear insights. Always cite your sources.",
            "kai":  "You are Kai Yamamoto, a data analyst. You turn raw data into actionable insights using statistics and visualisation. Be precise and quantitative.",
            "lee":  "You are Lee Russo, a DevOps and automation engineer. You write reliable scripts, manage infrastructure, and automate repetitive tasks efficiently.",
        ]
        return AgentCustomization(
            name:         agent.name,
            fullName:     agent.fullName,
            description:  agent.description,
            systemPrompt: prompts[agent.id] ?? "You are \(agent.fullName), an AI assistant."
        )
    }

    static func loadAll() -> [String: AgentCustomization] {
        var result: [String: AgentCustomization] = [:]
        let decoder = JSONDecoder()
        for agent in AgentDockView.catalogue {
            if let data = UserDefaults.standard.data(forKey: "agent_\(agent.id)"),
               let decoded = try? decoder.decode(AgentCustomization.self, from: data) {
                result[agent.id] = decoded
            }
        }
        return result
    }
}

// MARK: - Per-agent editor panel

private struct AgentEditorPanel: View {

    let agent: AgentProfile
    @Binding var customization: AgentCustomization

    @State private var savedFlash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().padding(.vertical, 20)
                formFields
                Spacer(minLength: 24)
                actionRow
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 20) {
            HumanAvatarView(style: agent.avatarStyle)
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(agent.color.opacity(0.55), lineWidth: 2.5))
                .shadow(color: agent.color.opacity(0.35), radius: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("Personalize Agent")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(customization.fullName)
                    .font(.system(size: 24, weight: .bold))
                Text(customization.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: Form

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            fieldRow(label: "Display Name") {
                TextField("Short name shown in dock", text: $customization.name)
                    .textFieldStyle(.roundedBorder)
            }

            fieldRow(label: "Full Name") {
                TextField("Full display name", text: $customization.fullName)
                    .textFieldStyle(.roundedBorder)
            }

            fieldRow(label: "Role / Description") {
                TextField("e.g. Code & debug", text: $customization.description)
                    .textFieldStyle(.roundedBorder)
            }

            fieldRow(label: "System Prompt") {
                TextEditor(text: $customization.systemPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 130, maxHeight: 220)
                    .padding(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private func fieldRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: Action row

    private var actionRow: some View {
        HStack {
            Button("Reset to Default") {
                withAnimation { customization = AgentPersonalizationView.defaultCustomization(for: agent) }
            }
            .foregroundStyle(.secondary)

            Spacer()

            if savedFlash {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13, weight: .medium))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .padding(.trailing, 8)
            }

            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .animation(.easeInOut(duration: 0.2), value: savedFlash)
    }

    // MARK: Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(customization) {
            UserDefaults.standard.set(data, forKey: "agent_\(agent.id)")
        }
        withAnimation { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { savedFlash = false }
        }
    }
}

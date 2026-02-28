// OverlayContentView.swift
// The overlay is now just the glass dock shelf — nothing else.
// Drag anywhere on the shelf to reposition (isMovableByWindowBackground = true
// on OverlayWindow handles this at the AppKit level, no DragHandleView needed).

import SwiftUI
import AppKit

struct OverlayContentView: View {

    @State private var selectedAgentID: String? = nil

    var body: some View {
        // NSVisualEffectView (set in OverlayWindow) provides the glass background.
        // This SwiftUI layer is fully transparent — only the dock content paints.
        AgentDockView(selectedID: $selectedAgentID)
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

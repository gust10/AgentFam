// HealthReminderScheduler.swift
// Fires health-nudge popups on a repeating timer.
// Interval is 30 minutes in production; call showNow() to test immediately.

import Foundation

// MARK: - Reminder catalogue

struct HealthReminder {
    let icon:    String   // SF Symbol name
    let title:   String
    let message: String
    let tint:    String   // named Color string — passed to HealthReminderView

    static let all: [HealthReminder] = [
        HealthReminder(
            icon:    "figure.walk",
            title:   "Time to move!",
            message: "Stand up and stretch for 2 minutes. Your body will thank you.",
            tint:    "green"
        ),
        HealthReminder(
            icon:    "drop.fill",
            title:   "Stay hydrated",
            message: "Grab a glass of water. Hydration keeps you sharp.",
            tint:    "blue"
        ),
        HealthReminder(
            icon:    "eye.fill",
            title:   "Rest your eyes",
            message: "Look at something 20 ft away for 20 seconds. 20-20-20 rule.",
            tint:    "purple"
        ),
        HealthReminder(
            icon:    "lungs.fill",
            title:   "Breathe deeply",
            message: "Take 3 slow, deep breaths to reset your focus.",
            tint:    "cyan"
        ),
        HealthReminder(
            icon:    "person.fill",
            title:   "Check your posture",
            message: "Sit up straight, relax your shoulders, unclench your jaw.",
            tint:    "orange"
        ),
        HealthReminder(
            icon:    "sun.max.fill",
            title:   "Step outside",
            message: "Even 5 minutes of sunlight improves mood and energy.",
            tint:    "yellow"
        ),
    ]

    static func random() -> HealthReminder { all.randomElement()! }
}

// MARK: - Scheduler

final class HealthReminderScheduler {

    static let shared = HealthReminderScheduler()

    private var timer: Timer?

    // 30-minute interval; a Timer on the main run loop fires reliably
    // even when no windows are active.
    private let interval: TimeInterval = 30 * 60

    func start() {
        timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { _ in
            HealthReminderWindow.show(reminder: .random())
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Immediately show a random reminder — handy for testing.
    func showNow() {
        HealthReminderWindow.show(reminder: .random())
    }
}

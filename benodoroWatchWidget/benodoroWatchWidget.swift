//
//  benodoroWatchWidget.swift
//  benodoroWatchWidget
//
//  Created by Bryan de Bourbon on 1/28/25.
//

import WidgetKit
import SwiftUI

/// The main provider for our watch widget using App Intents.
struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        // Placeholder data shown in widget gallery or when no real data is available
        SimpleEntry(
            date: Date(),
            configuration: ConfigurationAppIntent(),
            endTime: Date().addingTimeInterval(25 * 60),
            isBreak: false
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        // Load the latest from iCloud before building snapshot
        await PomodoroManager.shared.loadFromCloud()
        let manager = PomodoroManager.shared

        let now = Date()
        guard let startTime = manager.startTime else {
            // No active session => 0 time left
            return SimpleEntry(
                date: now,
                configuration: configuration,
                endTime: now,
                isBreak: false
            )
        }

        let endTime = startTime.addingTimeInterval(manager.duration)
        return SimpleEntry(
            date: now,
            configuration: configuration,
            endTime: endTime,
            isBreak: manager.isBreak
        )
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        // 1) Load current Pomodoro state from iCloud
        await PomodoroManager.shared.loadFromCloud()
        let manager = PomodoroManager.shared

        let now = Date()

        // 2) If there's no active Pomodoro, return a single entry with 0 time remaining
        guard let startTime = manager.startTime else {
            let entry = SimpleEntry(
                date: now,
                configuration: configuration,
                endTime: now,  // No active session => 0 time left
                isBreak: manager.isBreak
            )
            return Timeline(entries: [entry], policy: .atEnd)
        }

        // 3) Generate timeline entries from now until the end of the session
        let endTime = startTime.addingTimeInterval(manager.duration)
        var entries: [SimpleEntry] = []

        // We'll produce a new entry every minute from now until endTime
        var current = now
        while current <= endTime {
            let entry = SimpleEntry(
                date: current,
                configuration: configuration,
                endTime: endTime,
                isBreak: manager.isBreak
            )
            entries.append(entry)

            // Advance current by 1 minute
            if let nextMinute = Calendar.current.date(byAdding: .minute, value: 1, to: current) {
                current = nextMinute
            } else {
                // Safety check in case date math fails
                break
            }
        }

        // Optional: one final entry exactly at endTime with 0 remaining
        if endTime > now {
            let endEntry = SimpleEntry(
                date: endTime,
                configuration: configuration,
                endTime: endTime,
                isBreak: manager.isBreak
            )
            entries.append(endEntry)
        }

        // 4) Return the timeline
        return Timeline(entries: entries, policy: .atEnd)
    }

    func recommendations() -> [AppIntentRecommendation<ConfigurationAppIntent>] {
        [
            AppIntentRecommendation(
                intent: ConfigurationAppIntent(),
                description: "Pomodoro Timer"
            )
        ]
    }
}

/// Our complication timeline entry
struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let endTime: Date
    let isBreak: Bool
}

/// The main view displayed in the watch widget/complication
struct benodoroWatchWidgetEntryView: View {
    var entry: SimpleEntry

    var body: some View {
        VStack {
            Text(entry.isBreak ? "Break" : "Focus")
                .font(.caption)

            // Use a live timer text so the watch can show a second-level countdown
            Text(entry.endTime, style: .timer)
                .font(.headline)
                .monospacedDigit()
        }
        // Provide a background, if desired
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

/// The widget declaration (entry point for the watch complication)
@main
struct benodoroWatchWidget: Widget {
    let kind: String = "benodoroWatchWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigurationAppIntent.self,
            provider: Provider()
        ) { entry in
            benodoroWatchWidgetEntryView(entry: entry)
        }
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

// MARK: - Example intent extensions (optional)
extension ConfigurationAppIntent {
    fileprivate static var smiley: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        return intent
    }

    fileprivate static var starEyes: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        return intent
    }
}

// MARK: - SwiftUI Preview
#Preview(as: .accessoryRectangular) {
    benodoroWatchWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        configuration: .smiley,
        endTime: Date().addingTimeInterval(25 * 60),
        isBreak: false
    )
    SimpleEntry(
        date: .now,
        configuration: .starEyes,
        endTime: Date().addingTimeInterval(25 * 60),
        isBreak: true
    )
}

//
//  benodoroWatchWidget.swift
//  benodoroWatchWidget
//
//  Created by Bryan de Bourbon on 1/28/25.
//

import WidgetKit
import SwiftUI
import CloudKit

/// The main provider for our watch widget using App Intents.
struct Provider: AppIntentTimelineProvider {
    // Reference to our shared manager
    let manager = PomodoroManager.shared

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            configuration: ConfigurationAppIntent(),
            endTime: Date().addingTimeInterval(25 * 60),
            isBreak: false
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        // Await an updated load from CloudKit
        await PomodoroManager.shared.loadFromCloud()
        let manager = PomodoroManager.shared

        let now = Date()
        guard let startTime = manager.startTime else {
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
        // Update state from CloudKit before building the timeline
        await PomodoroManager.shared.loadFromCloud()
        let manager = PomodoroManager.shared
        let now = Date()

        // If there is no active session, check frequently for updates
        guard let startTime = manager.startTime else {
            let entry = SimpleEntry(
                date: now,
                configuration: configuration,
                endTime: now,
                isBreak: manager.isBreak
            )
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30)))
        }

        let endTime = startTime.addingTimeInterval(manager.duration)

        // If the session has ended, check frequently for new ones
        if endTime <= now {
            let entry = SimpleEntry(
                date: now,
                configuration: configuration,
                endTime: now,
                isBreak: manager.isBreak
            )
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30)))
        }

        // Generate timeline entries in 1-minute intervals.
        var entries: [SimpleEntry] = []
        var currentDate = now

        while currentDate < endTime {
            let entry = SimpleEntry(
                date: currentDate,
                configuration: configuration,
                endTime: endTime,
                isBreak: manager.isBreak
            )
            entries.append(entry)
            currentDate = currentDate.addingTimeInterval(60)
        }

        // Add a final entry at the exact end time
        let finalEntry = SimpleEntry(
            date: endTime,
            configuration: configuration,
            endTime: endTime,
            isBreak: manager.isBreak
        )
        entries.append(finalEntry)

        return Timeline(entries: entries, policy: .after(endTime))
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
    @Environment(\.widgetFamily) var family
    var entry: SimpleEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Circular complication: show a progress indicator and a live timer.
            ZStack {
                CircularProgressView(
                    progress: progressValue(),
                    color: entry.isBreak ? .green : .blue
                )
                // Live countdown using the system's timer style.
                Text(entry.endTime, style: .timer)
                    .font(.system(.body, design: .monospaced))
                    .minimumScaleFactor(0.5)
            }
            .containerBackground(for: .widget) { Color.clear }

        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(entry.isBreak ? "Break" : "Focus")
                    .font(.caption2)
                    .foregroundColor(entry.isBreak ? .green : .blue)
                Text(entry.endTime, style: .timer)
                    .font(.system(.body, design: .monospaced))
            }
            .containerBackground(for: .widget) { Color.clear }

        case .accessoryInline:
            HStack {
                Text(entry.isBreak ? "Break " : "Focus ")
                Text(entry.endTime, style: .timer)
                    .font(.system(.body, design: .monospaced))
            }
            .containerBackground(for: .widget) { Color.clear }

        default:
            Text(entry.endTime, style: .timer)
                .containerBackground(for: .widget) { Color.clear }
        }
    }

    /// Calculate the progress for the circular progress view.
    private func progressValue() -> Double {
        let now = Date()
        guard entry.endTime > now else { return 0 }
        let total = entry.endTime.timeIntervalSince(entry.date)
        let remaining = entry.endTime.timeIntervalSince(now)
        return remaining / total
    }
}

/// Circular progress view for the circular complication
struct CircularProgressView: View {
    let progress: Double
    let color: Color

    var body: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
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
        .configurationDisplayName("Pomodoro Timer")
        .description("Shows your current Pomodoro session.")
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

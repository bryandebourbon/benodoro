import WidgetKit
import SwiftUI
import CloudKit

/// The main provider for our watch widget using App Intents.
struct Provider: AppIntentTimelineProvider {
    
    /// Reads the shared local state from UserDefaults.
    func getLocalState() -> (startTime: Date?, duration: TimeInterval, isBreak: Bool) {
        if let sharedDefaults = UserDefaults(suiteName: "group.com.bryandebourbon.Pomodoro") {
            let startTimeInterval = sharedDefaults.double(forKey: "startTime")
            let startTime = startTimeInterval > 0 ? Date(timeIntervalSince1970: startTimeInterval) : nil
            let duration = sharedDefaults.double(forKey: "duration")
            let isBreak = sharedDefaults.bool(forKey: "isBreak")
            return (startTime, duration > 0 ? duration : 25 * 60, isBreak)
        }
        return (nil, 25 * 60, false)
    }

    func placeholder(in context: Context) -> SimpleEntry {
        let localState = getLocalState()
        let now = Date()
        let endTime = (localState.startTime ?? now).addingTimeInterval(localState.duration)
        return SimpleEntry(
            date: now,
            configuration: ConfigurationAppIntent(),
            endTime: endTime,
            isBreak: localState.isBreak
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        let localState = getLocalState()
        let now = Date()
        let endTime = (localState.startTime ?? now).addingTimeInterval(localState.duration)
        return SimpleEntry(
            date: now,
            configuration: configuration,
            endTime: endTime,
            isBreak: localState.isBreak
        )
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let localState = getLocalState()
        let now = Date()
        let startTime = localState.startTime
        
        // If there's no active session, refresh soon.
        guard let start = startTime else {
            let entry = SimpleEntry(
                date: now,
                configuration: configuration,
                endTime: now,
                isBreak: localState.isBreak
            )
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30)))
        }
        
        let endTime = start.addingTimeInterval(localState.duration)
        
        // If the session has ended, refresh soon.
        if endTime <= now {
            let entry = SimpleEntry(
                date: now,
                configuration: configuration,
                endTime: now,
                isBreak: localState.isBreak
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
                isBreak: localState.isBreak
            )
            entries.append(entry)
            currentDate = currentDate.addingTimeInterval(60)
        }
        
        // Final entry at session end.
        let finalEntry = SimpleEntry(
            date: endTime,
            configuration: configuration,
            endTime: endTime,
            isBreak: localState.isBreak
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
            ZStack {
                CircularProgressView(
                    progress: progressValue(),
                    color: entry.isBreak ? .green : .blue
                )
                timerView
                    .minimumScaleFactor(0.5)
            }
            .containerBackground(for: .widget) { Color.clear }
            
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(entry.isBreak ? "Break" : "Focus")
                    .font(.caption2)
                    .foregroundColor(entry.isBreak ? .green : .blue)
                timerView
                    .font(.system(.body, design: .monospaced))
            }
            .containerBackground(for: .widget) { Color.clear }
            
        case .accessoryInline:
            HStack {
                Text(entry.isBreak ? "Break " : "Focus ")
                timerView
                    .font(.system(.body, design: .monospaced))
            }
            .containerBackground(for: .widget) { Color.clear }
            
        default:
            timerView
                .containerBackground(for: .widget) { Color.clear }
        }
    }
    
    /// A computed view that displays either the live timer or a static "00:00" if the session is over.
    @ViewBuilder
    private var timerView: some View {
        // Compare the current date to entry.endTime.
        // Note: In a widget, Date() might not update continuously,
        // so for a truly dynamic countdown you might wrap this in a TimelineView.
        if Date() >= entry.endTime {
            Text("00:00")
        } else {
            Text(entry.endTime, style: .timer)
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

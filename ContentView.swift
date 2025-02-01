import SwiftUI
import Combine
import CloudKit
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

//
//  ContentView.swift
//  Shared
//
//  Created by YourName on 1/28/25.
//

struct ContentView: View {
    @ObservedObject var manager = PomodoroManager.shared
    @State private var lastUpdate = Date()

    var body: some View {
        VStack(spacing: 20) {
            // Countdown in MM:SS format
            Text(formatTime(manager.timeRemaining))
                .font(.system(size: 48, weight: .medium, design: .monospaced))
                .padding()

            // Start a 25-minute focus session
            Button("Start 25-min Focus") {
                manager.startPomodoro(isBreak: false, duration: 25 * 60)
            }
            .buttonStyle(.borderedProminent)

            // Stop/reset the session
            Button("Stop / Reset") {
                manager.stopPomodoro()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .onAppear {
            // Use an asynchronous task to load from iCloud
            Task { await manager.loadFromCloud() }
            
            // Subscribe to notifications so the UI refreshes when the state changes
            NotificationCenter.default.addObserver(
                forName: PomodoroManager.pomodoroStateDidChange,
                object: nil,
                queue: .main
            ) { _ in
                lastUpdate = Date()
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - SwiftUI Preview

#Preview {
    ContentView()
        .previewLayout(.sizeThatFits)
}

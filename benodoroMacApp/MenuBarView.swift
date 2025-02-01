import SwiftUI

struct MenuBarView: View {
    @ObservedObject var manager = PomodoroManager.shared
    
    // Add state to force view updates
    @State private var lastUpdate = Date()
    
    var body: some View {
        VStack(spacing: 12) {
            // Timer Display
            Text(formatTime(manager.timeRemaining))
                .font(.system(.title, design: .monospaced))
                .foregroundColor(manager.isBreak ? .green : .blue)
            
            // Controls
            HStack(spacing: 16) {
                Button("25min Focus") {
                    manager.startPomodoro(isBreak: false, duration: 25 * 60)
                }
                
                Button("5min Break") {
                    manager.startPomodoro(isBreak: true, duration: 5 * 60)
                }
                
                Button("Stop") {
                    manager.stopPomodoro()
                }
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 200)
        .onAppear {
            // Subscribe to notifications
            NotificationCenter.default.addObserver(
                forName: PomodoroManager.pomodoroStateDidChange,
                object: nil,
                queue: .main
            ) { _ in
                // Force view to update
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
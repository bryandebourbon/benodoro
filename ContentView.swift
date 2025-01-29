//
//  GlobalPomodoro.swift
//  Shared
//
//  Created by YourName on 1/28/25.
//

import SwiftUI
import Combine
import CloudKit

// MARK: - PomodoroManager

final class PomodoroManager: ObservableObject {
    // Singleton so all platforms share the same instance
    static let shared = PomodoroManager()

    // MARK: - Published Properties
    @Published var startTime: Date?
    @Published var duration: TimeInterval = 25 * 60  // e.g., 25 minutes
    @Published var isBreak: Bool = false

    // A timer to trigger SwiftUI updates (for live countdown)
    private var timerCancellable: AnyCancellable?

    // MARK: - CloudKit Setup
    // Replace with your actual CloudKit container identifier
    private let container = CKContainer(identifier: "iCloud.com.example.Pomodoro")
    private let recordType = "PomodoroState"
    private let recordID = CKRecord.ID(recordName: "currentPomodoroState")

    // MARK: - Computed Property
    /// Returns how many seconds remain in the current session
    var timeRemaining: TimeInterval {
        guard let start = startTime else { return 0 }
        let end = start.addingTimeInterval(duration)
        return max(end.timeIntervalSinceNow, 0)
    }

    // MARK: - Init
    private init() {
        // Fire a timer every second to refresh the UI
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // Each tick: inform SwiftUI something changed (if we rely on computed property)
                self?.objectWillChange.send()
            }
    }

    // MARK: - Public Methods

    /// Start a Pomodoro or Break session
    func startPomodoro(isBreak: Bool = false, duration: TimeInterval) {
        self.isBreak = isBreak
        self.duration = duration
        self.startTime = Date()
        syncToCloud()
    }

    /// Stop or reset session
    func stopPomodoro() {
        self.startTime = nil
        self.isBreak = false
        self.duration = 25 * 60
        syncToCloud()
    }

    /// Load from iCloud if available
    func loadFromCloud() {
        let database = container.privateCloudDatabase

        database.fetch(withRecordID: recordID) { [weak self] (record, error) in
            guard let self = self else { return }
            if let error = error as? CKError {
                if error.code == .unknownItem {
                    // No existing record found—first-time user
                    print("No Pomodoro record found in iCloud. This is normal on first run.")
                    return
                } else {
                    // Handle other errors (network, permission, etc.)
                    print("Error fetching Pomodoro record: \(error)")
                    return
                }
            }

            guard let record = record else { return }
            DispatchQueue.main.async {
                self.apply(record: record)
            }
        }
    }

    // MARK: - Private Methods

    /// Convert our local state -> CKRecord, then save it
    private func syncToCloud() {
        let database = container.privateCloudDatabase

        // Attempt to fetch the existing record or create a new one
        database.fetch(withRecordID: recordID) { [weak self] (existingRecord, error) in
            guard let self = self else { return }

            if let fetchError = error as? CKError {
                if fetchError.code == .unknownItem {
                    // Record doesn't exist in iCloud; create it
                    let newRecord = CKRecord(recordType: self.recordType, recordID: self.recordID)
                    self.updateFields(record: newRecord)
                    self.saveRecord(newRecord, in: database)
                } else {
                    print("Error fetching record during sync: \(fetchError)")
                }
                return
            }

            // If a record exists, update it
            if let existingRecord = existingRecord {
                self.updateFields(record: existingRecord)
                self.saveRecord(existingRecord, in: database)
            }
        }
    }

    /// Update CKRecord fields from the current manager state
    private func updateFields(record: CKRecord) {
        // Convert optional Date to CKRecordValue
        if let start = startTime {
            record["startTime"] = start as CKRecordValue
        } else {
            record["startTime"] = nil
        }
        record["duration"] = duration as CKRecordValue
        record["isBreak"] = isBreak as CKRecordValue
    }

    /// Apply CKRecord fields to this manager
    private func apply(record: CKRecord) {
        // startTime
        if let fetchedStartTime = record["startTime"] as? Date {
            self.startTime = fetchedStartTime
        } else {
            self.startTime = nil
        }
        // duration
        self.duration = record["duration"] as? TimeInterval ?? 25 * 60
        // isBreak
        self.isBreak = record["isBreak"] as? Bool ?? false
    }

    /// Save the record to CloudKit
    private func saveRecord(_ record: CKRecord, in database: CKDatabase) {
        database.save(record) { (savedRecord, error) in
            if let error = error {
                print("Error saving Pomodoro record to iCloud: \(error)")
            } else {
                print("Pomodoro record successfully saved to iCloud.")
            }
        }
    }
}

// MARK: - GlobalContentView

struct ContentView: View {
    @ObservedObject var manager = PomodoroManager.shared

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
        // For example, load from iCloud on appear
        .onAppear {
            manager.loadFromCloud()
        }
    }

    // Helper to format time intervals in MM:SS
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

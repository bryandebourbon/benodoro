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
    
    // Add notification name as a static property
    static let pomodoroStateDidChange = Notification.Name("pomodoroStateDidChange")
    
    @Published var duration: TimeInterval = 25 * 60  // e.g., 25 minutes
    @Published var isBreak: Bool = false

    // A timer to trigger SwiftUI updates (for live countdown)
    private var timerCancellable: AnyCancellable?

    // MARK: - CloudKit Setup
    private let container = CKContainer(identifier: "iCloud.com.example.Pomodoro")
    private let recordType = "PomodoroState"
    private let recordID = CKRecord.ID(recordName: "currentPomodoroState")
    
    // Add subscription for remote changes
    private var subscription: CKQuerySubscription?
    private var notificationInfo: CKSubscription.NotificationInfo?
    
    // Add timer for periodic sync
    private var syncTimer: AnyCancellable?

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
                self?.objectWillChange.send()
            }
            
        // Setup periodic sync timer (every 5 seconds)
        syncTimer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.loadFromCloud()
            }
            
        // Setup CloudKit subscription
        setupCloudKitSubscription()
        
        // Setup notification observers for app state changes
        setupAppStateObservers()
    }
    
    private func setupAppStateObservers() {
        #if os(iOS)
        // iOS app state notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppStateChange),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #elseif os(macOS)
        // macOS app state notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppStateChange),
            name: NSApplication.willBecomeActiveNotification,
            object: nil
        )
        #endif
    }
    
    @objc private func handleAppStateChange() {
        // Immediately load from cloud when app becomes active
        loadFromCloud()
    }
    
    private func setupCloudKitSubscription() {
        // Create a subscription to watch for changes
        let predicate = NSPredicate(value: true)
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: predicate,
            subscriptionID: "PomodoroStateChanges",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        
        // Configure notification info
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        // Save the subscription
        let database = container.privateCloudDatabase
        database.save(subscription) { [weak self] _, error in
            if let error = error {
                print("Error setting up CloudKit subscription: \(error)")
            } else {
                print("CloudKit subscription setup successfully")
                self?.observeRemoteNotifications()
            }
        }
    }
    
    private func observeRemoteNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange),
            name: NSNotification.Name("CKAccountChanged"),
            object: nil
        )
        
        #if os(iOS)
        // Observe background refresh on iOS
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange),
            name: UIApplication.backgroundRefreshStatusDidChangeNotification,
            object: nil
        )
        #endif
    }
    
    @objc private func handleRemoteChange() {
        loadFromCloud()
    }

    // MARK: - Public Methods

    /// Start a Pomodoro or Break session
    func startPomodoro(isBreak: Bool = false, duration: TimeInterval) {
        self.isBreak = isBreak
        self.duration = duration
        self.startTime = Date()
        
        // Sync immediately to CloudKit
        syncToCloud()
    }

    /// Stop or reset session
    func stopPomodoro() {
        self.startTime = nil
        self.isBreak = false
        self.duration = 25 * 60
        
        // Sync immediately to CloudKit
        syncToCloud()
    }

    /// Load from iCloud if available
    func loadFromCloud() {
        let database = container.privateCloudDatabase

        database.fetch(withRecordID: recordID) { [weak self] (record, error) in
            guard let self = self else { return }
            
            if let error = error as? CKError {
                if error.code == .unknownItem {
                    print("No Pomodoro record found in iCloud. This is normal on first run.")
                    return
                } else {
                    print("Error fetching Pomodoro record: \(error)")
                    return
                }
            }

            guard let record = record else { return }
            
            // Only update if the cloud record is newer
            if let cloudModifiedTime = record.modificationDate,
               let localStartTime = self.startTime {
                // If our local time is more recent, we should be the source of truth
                if localStartTime > cloudModifiedTime {
                    return
                }
            }
            
            DispatchQueue.main.async {
                self.apply(record: record)
                // Notify all views to update
                NotificationCenter.default.post(name: PomodoroManager.pomodoroStateDidChange, object: self)
            }
        }
    }

    // MARK: - Private Methods

    /// Convert our local state -> CKRecord, then save it
    private func syncToCloud() {
        let database = container.privateCloudDatabase
        
        database.fetch(withRecordID: recordID) { [weak self] (existingRecord, error) in
            guard let self = self else { return }
            
            let record: CKRecord
            if let fetchError = error as? CKError, fetchError.code == .unknownItem {
                // Record doesn't exist, create new one
                record = CKRecord(recordType: self.recordType, recordID: self.recordID)
            } else if let existingRecord = existingRecord {
                record = existingRecord
            } else {
                return
            }
            
            self.updateFields(record: record)
            self.saveRecord(record, in: database)
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
    
    // Add state to force view updates
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
        // For example, load from iCloud on appear
        .onAppear {
            manager.loadFromCloud()
            
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

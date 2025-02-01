//
//  GlobalPomodoro.swift
//  Shared
//
//  Created by YourName on 1/28/25.
//

import SwiftUI
import Combine
import CloudKit
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - PomodoroManager

//final class PomodoroManager: NSObject, ObservableObject {
//    // Singleton so all platforms share the same instance
//    static let shared = PomodoroManager()
//
//    // MARK: - Published Properties
//    @Published var startTime: Date?
//
//    // Notification name so views can update when the state changes
//    static let pomodoroStateDidChange = Notification.Name("pomodoroStateDidChange")
//
//    @Published var duration: TimeInterval = 25 * 60  // e.g., 25 minutes
//    @Published var isBreak: Bool = false
//
//    // A timer to trigger SwiftUI updates (for live countdown)
//    private var timerCancellable: AnyCancellable?
//
//    // MARK: - CloudKit Setup
//    private let container = CKContainer(identifier: "iCloud.com.example.Pomodoro")
//    private let recordType = "PomodoroState"
//    private let recordID = CKRecord.ID(recordName: "currentPomodoroState")
//
//    // CloudKit subscription and notification info
//    private var subscription: CKQuerySubscription?
//    private var notificationInfo: CKSubscription.NotificationInfo?
//
//    // Timer for periodic sync
//    private var syncTimer: AnyCancellable?
//
//    // MARK: - Computed Property
//    /// Returns how many seconds remain in the current session
//    var timeRemaining: TimeInterval {
//        guard let start = startTime else { return 0 }
//        let end = start.addingTimeInterval(duration)
//        return max(end.timeIntervalSinceNow, 0)
//    }
//
//    // MARK: - Init
//    private init() {
//        // Fire a timer every second to refresh the UI
//        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
//            .autoconnect()
//            .sink { [weak self] _ in
//                self?.objectWillChange.send()
//            }
//
//        // Setup periodic sync timer (every 5 seconds) using async load
//        syncTimer = Timer.publish(every: 5.0, on: .main, in: .common)
//            .autoconnect()
//            .sink { [weak self] _ in
//                guard let self = self else { return }
//                Task {
//                    await self.loadFromCloud()
//                }
//            }
//
//        // Setup CloudKit subscription
//        setupCloudKitSubscription()
//
//        // Setup notification observers for app state changes
//        setupAppStateObservers()
//
//        // Setup WatchConnectivity session if available
//        #if canImport(WatchConnectivity)
//        setupWCSession()
//        #endif
//    }
//
//    private func setupAppStateObservers() {
//        #if os(iOS)
//        // iOS app state notifications
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(handleAppStateChange),
//            name: UIApplication.willEnterForegroundNotification,
//            object: nil
//        )
//        #elseif os(macOS)
//        // macOS app state notifications
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(handleAppStateChange),
//            name: NSApplication.willBecomeActiveNotification,
//            object: nil
//        )
//        #endif
//    }
//
//    @objc private func handleAppStateChange() {
//        // Immediately load from cloud when app becomes active
//        Task { await loadFromCloud() }
//    }
//
//    private func setupCloudKitSubscription() {
//        // Create a subscription to watch for changes
//        let predicate = NSPredicate(value: true)
//        let subscription = CKQuerySubscription(
//            recordType: recordType,
//            predicate: predicate,
//            subscriptionID: "PomodoroStateChanges",
//            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
//        )
//
//        // Configure notification info
//        let notificationInfo = CKSubscription.NotificationInfo()
//        notificationInfo.shouldSendContentAvailable = true
//        subscription.notificationInfo = notificationInfo
//
//        // Save the subscription
//        let database = container.privateCloudDatabase
//        database.save(subscription) { [weak self] _, error in
//            if let error = error {
//                print("Error setting up CloudKit subscription: \(error)")
//            } else {
//                print("CloudKit subscription setup successfully")
//                self?.observeRemoteNotifications()
//            }
//        }
//    }
//
//    private func observeRemoteNotifications() {
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(handleRemoteChange),
//            name: NSNotification.Name("CKAccountChanged"),
//            object: nil
//        )
//
//        #if os(iOS)
//        // Observe background refresh on iOS
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(handleRemoteChange),
//            name: UIApplication.backgroundRefreshStatusDidChangeNotification,
//            object: nil
//        )
//        #endif
//    }
//
//    @objc private func handleRemoteChange() {
//        Task { await loadFromCloud() }
//    }
//
//    // MARK: - Public Methods
//
//    /// Start a Pomodoro or Break session
//    func startPomodoro(isBreak: Bool = false, duration: TimeInterval) {
//        self.isBreak = isBreak
//        self.duration = duration
//        self.startTime = Date()
//
//        // Sync immediately to CloudKit
//        syncToCloud()
//
//        // Immediately send update to the watch if available.
//        #if canImport(WatchConnectivity)
//        sendUpdateToWatch()
//        #endif
//
//        // Force widget timeline reload so that the new focus time appears immediately.
//        #if os(iOS) || os(watchOS)
//        WidgetCenter.shared.reloadTimelines(ofKind: "benodoroWatchWidget")
//        #endif
//
//        // Post a notification so that other parts of the app (like the menu bar) update.
//        NotificationCenter.default.post(name: PomodoroManager.pomodoroStateDidChange, object: self)
//    }
//
//    /// Stop or reset session
//    func stopPomodoro() {
//        self.startTime = nil
//        self.isBreak = false
//        self.duration = 25 * 60
//
//        // Sync immediately to CloudKit
//        syncToCloud()
//
//        #if canImport(WatchConnectivity)
//        sendUpdateToWatch()
//        #endif
//
//        #if os(iOS) || os(watchOS)
//        WidgetCenter.shared.reloadTimelines(ofKind: "benodoroWatchWidget")
//        #endif
//
//        NotificationCenter.default.post(name: PomodoroManager.pomodoroStateDidChange, object: self)
//    }
//
//    /// Load from iCloud if available (async version)
//    func loadFromCloud() async {
//        await withCheckedContinuation { continuation in
//            let database = container.privateCloudDatabase
//
//            database.fetch(withRecordID: recordID) { [weak self] (record, error) in
//                guard let self = self else {
//                    continuation.resume()
//                    return
//                }
//
//                if let error = error as? CKError {
//                    if error.code == .unknownItem {
//                        print("No Pomodoro record found in iCloud. This is normal on first run.")
//                    } else {
//                        print("Error fetching Pomodoro record: \(error)")
//                    }
//                    continuation.resume()
//                    return
//                }
//
//                if let record = record {
//                    DispatchQueue.main.async {
//                        self.apply(record: record)
//                        // Notify all views to update
//                        NotificationCenter.default.post(name: PomodoroManager.pomodoroStateDidChange, object: self)
//                        continuation.resume()
//                    }
//                } else {
//                    continuation.resume()
//                }
//            }
//        }
//    }
//
//    // MARK: - Private Methods
//
//    /// Convert our local state -> CKRecord, then save it
//    private func syncToCloud() {
//        let database = container.privateCloudDatabase
//
//        database.fetch(withRecordID: recordID) { [weak self] (existingRecord, error) in
//            guard let self = self else { return }
//
//            let record: CKRecord
//            if let fetchError = error as? CKError, fetchError.code == .unknownItem {
//                // Record doesn't exist, create new one
//                record = CKRecord(recordType: self.recordType, recordID: self.recordID)
//            } else if let existingRecord = existingRecord {
//                record = existingRecord
//            } else {
//                return
//            }
//
//            self.updateFields(record: record)
//            self.saveRecord(record, in: database)
//        }
//    }
//
//    /// Update CKRecord fields from the current manager state
//    private func updateFields(record: CKRecord) {
//        if let start = startTime {
//            record["startTime"] = start as CKRecordValue
//        } else {
//            record["startTime"] = nil
//        }
//        record["duration"] = duration as CKRecordValue
//        record["isBreak"] = isBreak as CKRecordValue
//    }
//
//    /// Apply CKRecord fields to this manager
//    private func apply(record: CKRecord) {
//        if let fetchedStartTime = record["startTime"] as? Date {
//            self.startTime = fetchedStartTime
//        } else {
//            self.startTime = nil
//        }
//        self.duration = record["duration"] as? TimeInterval ?? 25 * 60
//        self.isBreak = record["isBreak"] as? Bool ?? false
//    }
//
//    /// Save the record to CloudKit
//    private func saveRecord(_ record: CKRecord, in database: CKDatabase) {
//        database.save(record) { (savedRecord, error) in
//            if let error = error {
//                print("Error saving Pomodoro record to iCloud: \(error)")
//            } else {
//                print("Pomodoro record successfully saved to iCloud.")
//            }
//        }
//    }
//}


// MARK: - GlobalContentView

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
            
            // Subscribe to notifications
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

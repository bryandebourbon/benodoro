import SwiftUI
import Combine
import CloudKit
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

final class PomodoroManager: NSObject, ObservableObject {
    // Singleton so all platforms share the same instance
    static let shared = PomodoroManager()

    // MARK: - Published Properties
    @Published var startTime: Date?
    @Published var duration: TimeInterval = 25 * 60  // e.g., 25 minutes
    @Published var isBreak: Bool = false

    // Notification name so views can update when the state changes
    static let pomodoroStateDidChange = Notification.Name("pomodoroStateDidChange")

    // A timer to trigger SwiftUI updates (for live countdown)
    private var timerCancellable: AnyCancellable?

    // MARK: - CloudKit Setup
    private let container = CKContainer(identifier: "iCloud.com.example.Pomodoro")
    private let recordType = "PomodoroState"
    private let recordID = CKRecord.ID(recordName: "currentPomodoroState")

    // Timer for periodic sync
    private var syncTimer: AnyCancellable?

    // MARK: - Computed Property
    /// Returns how many seconds remain in the current session
    var timeRemaining: TimeInterval {
        guard let start = startTime else { return 0 }
        let end = start.addingTimeInterval(duration)
        return max(end.timeIntervalSinceNow, 0)
    }

    // MARK: - Init
    override init() {
        super.init()

        // Fire a timer every second to refresh the UI
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        // Setup periodic sync timer (every 5 seconds) using async load
        syncTimer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.loadFromCloud()
                }
            }

        // Setup CloudKit subscription
        setupCloudKitSubscription()

        // Setup notification observers for app state changes
        setupAppStateObservers()

        // Setup WatchConnectivity session if available
        #if canImport(WatchConnectivity)
        setupWCSession()
        #endif

        // Load local state from shared container on initialization
        loadLocalState()
    }

    // MARK: - Local State (Shared)
    private let appGroupIdentifier = "group.com.bryandebourbon.Pomodoro"

    /// Save the current state to shared UserDefaults for immediate widget updates.
    private func saveLocalState() {
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            // Save the start time (as a timestamp), duration, and break state.
            if let startTime = self.startTime {
                sharedDefaults.set(startTime.timeIntervalSince1970, forKey: "startTime")
            } else {
                sharedDefaults.set(0, forKey: "startTime")
            }
            sharedDefaults.set(duration, forKey: "duration")
            sharedDefaults.set(isBreak, forKey: "isBreak")
        }
    }

    /// Load the current state from shared UserDefaults.
    private func loadLocalState() {
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            let startTimeInterval = sharedDefaults.double(forKey: "startTime")
            self.startTime = startTimeInterval > 0 ? Date(timeIntervalSince1970: startTimeInterval) : nil
            let savedDuration = sharedDefaults.double(forKey: "duration")
            self.duration = savedDuration > 0 ? savedDuration : 25 * 60
            self.isBreak = sharedDefaults.bool(forKey: "isBreak")
        }
    }

    // MARK: - App State Observers
    private func setupAppStateObservers() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppStateChange),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #elseif os(macOS)
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
        Task { await loadFromCloud() }
    }

    // MARK: - CloudKit Subscription
    private func setupCloudKitSubscription() {
        let predicate = NSPredicate(value: true)
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: predicate,
            subscriptionID: "PomodoroStateChanges",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange),
            name: UIApplication.backgroundRefreshStatusDidChangeNotification,
            object: nil
        )
        #endif
    }

    @objc private func handleRemoteChange() {
        Task { await loadFromCloud() }
    }

    // MARK: - Public Methods

    /// Start a Pomodoro or Break session
    func startPomodoro(isBreak: Bool = false, duration: TimeInterval) {
        self.isBreak = isBreak
        self.duration = duration
        self.startTime = Date()

        // Update local shared state immediately.
        saveLocalState()

        // Sync immediately to CloudKit.
        syncToCloud()

        // Immediately send update to the watch if available.
        #if canImport(WatchConnectivity)
        sendUpdateToWatch()
        #endif

        // Force widget timeline reload so that the new focus time appears immediately.
        #if os(iOS) || os(watchOS)
        WidgetCenter.shared.reloadTimelines(ofKind: "benodoroWatchWidget")
        #endif

        NotificationCenter.default.post(name: PomodoroManager.pomodoroStateDidChange, object: self)
    }

    /// Stop or reset session
    func stopPomodoro() {
        self.startTime = nil
        self.isBreak = false
        self.duration = 25 * 60

        // Update local shared state immediately.
        saveLocalState()

        // Sync immediately to CloudKit.
        syncToCloud()

        #if canImport(WatchConnectivity)
        sendUpdateToWatch()
        #endif

        #if os(iOS) || os(watchOS)
        WidgetCenter.shared.reloadTimelines(ofKind: "benodoroWatchWidget")
        #endif

        NotificationCenter.default.post(name: PomodoroManager.pomodoroStateDidChange, object: self)
    }

    /// Load from iCloud if available (async version)
    func loadFromCloud() async {
        await withCheckedContinuation { continuation in
            let database = container.privateCloudDatabase

            database.fetch(withRecordID: recordID) { [weak self] (record, error) in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                if let error = error as? CKError {
                    if error.code == .unknownItem {
                        print("No Pomodoro record found in iCloud. This is normal on first run.")
                    } else {
                        print("Error fetching Pomodoro record: \(error)")
                    }
                    continuation.resume()
                    return
                }

                if let record = record {
                    DispatchQueue.main.async {
                        self.apply(record: record)
                        // Also update the shared local state
                        self.saveLocalState()
                        // Post notification so that UI updates
                        NotificationCenter.default.post(name: PomodoroManager.pomodoroStateDidChange, object: self)
                        // *** Force the widget timeline to reload ***
                        WidgetCenter.shared.reloadTimelines(ofKind: "benodoroWatchWidget")
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                }

            }
        }
    }

    // MARK: - Private Methods

    private func syncToCloud() {
        let database = container.privateCloudDatabase

        database.fetch(withRecordID: recordID) { [weak self] (existingRecord, error) in
            guard let self = self else { return }

            let record: CKRecord
            if let fetchError = error as? CKError, fetchError.code == .unknownItem {
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

    private func updateFields(record: CKRecord) {
        if let start = startTime {
            record["startTime"] = start as CKRecordValue
        } else {
            record["startTime"] = nil
        }
        record["duration"] = duration as CKRecordValue
        record["isBreak"] = isBreak as CKRecordValue
    }

    private func apply(record: CKRecord) {
        if let fetchedStartTime = record["startTime"] as? Date {
            self.startTime = fetchedStartTime
        } else {
            self.startTime = nil
        }
        self.duration = record["duration"] as? TimeInterval ?? 25 * 60
        self.isBreak = record["isBreak"] as? Bool ?? false
    }

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

#if canImport(WatchConnectivity)
extension PomodoroManager: WCSessionDelegate {
    /// Setup the watch connectivity session
    func setupWCSession() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    /// Sends an immediate update to the watch with the current Pomodoro state.
    func sendUpdateToWatch() {
        let data: [String: Any] = [
            "startTime": startTime?.timeIntervalSince1970 ?? 0,
            "duration": duration,
            "isBreak": isBreak
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(data, replyHandler: nil) { error in
                print("Error sending update to watch: \(error)")
            }
        } else {
            do {
                try WCSession.default.updateApplicationContext(data)
            } catch {
                print("Error updating application context: \(error)")
            }
        }
    }

    // MARK: - WCSessionDelegate Methods
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Optionally handle activation changes.
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // Not needed in this example.
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { }
    
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            if let startTimeValue = applicationContext["startTime"] as? TimeInterval, startTimeValue > 0 {
                self.startTime = Date(timeIntervalSince1970: startTimeValue)
            } else {
                self.startTime = nil
            }
            self.duration = applicationContext["duration"] as? TimeInterval ?? 25 * 60
            self.isBreak = applicationContext["isBreak"] as? Bool ?? false

            // Update the shared local state as well.
            self.saveLocalState()

            NotificationCenter.default.post(name: PomodoroManager.pomodoroStateDidChange, object: self)

            #if os(watchOS)
            WidgetCenter.shared.reloadTimelines(ofKind: "benodoroWatchWidget")
            #endif
        }
    }
}
#endif

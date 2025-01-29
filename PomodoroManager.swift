//import Foundation
//import Combine
//import CloudKit
//
//final class PomodoroManager: ObservableObject {
//    // Singleton
//    static let shared = PomodoroManager()
//
//    // MARK: - Published Properties
//    @Published var startTime: Date?
//    @Published var duration: TimeInterval = 25 * 60  // e.g., 25 minutes
//    @Published var isBreak: Bool = false
//
//    private var timer: AnyCancellable?
//
//    // MARK: - CloudKit Setup
//    /// Replace with your actual CloudKit container identifier, e.g. "iCloud.com.yourcompany.yourapp"
//    private let container = CKContainer(identifier: "iCloud.com.example.Pomodoro")
//    private let recordType = "PomodoroState"
//    /// You can choose any unique record name. We’ll use “currentPomodoroState” for the single global record.
//    private let recordID = CKRecord.ID(recordName: "currentPomodoroState")
//
//    // MARK: - Computed Property
//    var timeRemaining: TimeInterval {
//        guard let start = startTime else { return 0 }
//        let end = start.addingTimeInterval(duration)
//        return max(end.timeIntervalSinceNow, 0)
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
//        // Possibly schedule a local notification, etc.
//        syncToCloud()
//    }
//
//    /// Stop or reset session
//    func stopPomodoro() {
//        self.startTime = nil
//        self.isBreak = false
//        self.duration = 25 * 60
//        syncToCloud()
//    }
//
//    /// Load from iCloud if available
//    func loadFromCloud() {
//        let database = container.privateCloudDatabase
//
//        database.fetch(withRecordID: recordID) { [weak self] (record, error) in
//            guard let self = self else { return }
//            if let error = error as? CKError {
//                if error.code == .unknownItem {
//                    // No existing record found—this may be normal for a first-time user.
//                    print("No Pomodoro record found in iCloud. This is normal on first run.")
//                    return
//                } else {
//                    // Handle other errors (network, permission, etc.)
//                    print("Error fetching Pomodoro record: \(error)")
//                    return
//                }
//            }
//
//            guard let record = record else { return }
//            DispatchQueue.main.async {
//                self.apply(record: record)
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
//        // First, try to fetch the existing record or create a new one if it doesn't exist
//        database.fetch(withRecordID: recordID) { [weak self] (existingRecord, error) in
//            guard let self = self else { return }
//
//            if let fetchError = error as? CKError {
//                // If the record doesn't exist in iCloud, we'll create it
//                if fetchError.code == .unknownItem {
//                    let newRecord = CKRecord(recordType: self.recordType, recordID: self.recordID)
//                    self.updateFields(record: newRecord)
//                    self.saveRecord(newRecord, in: database)
//                } else {
//                    print("Error fetching record during sync: \(fetchError)")
//                }
//                return
//            }
//
//            // If a record exists, update it
//            if let existingRecord = existingRecord {
//                self.updateFields(record: existingRecord)
//                self.saveRecord(existingRecord, in: database)
//            }
//        }
//    }
//
//    /// Update CKRecord fields from the current manager state
//    private func updateFields(record: CKRecord) {
//        // Convert optional Date to a CKRecordValue or set nil if no start time
//        if let start = startTime {
//            record["startTime"] = start as CKRecordValue
//        } else {
//            record["startTime"] = nil
//        }
//
//        record["duration"] = duration as CKRecordValue
//        record["isBreak"] = isBreak as CKRecordValue
//    }
//
//    /// Apply CKRecord fields to the manager
//    private func apply(record: CKRecord) {
//        // Optional cast to Date
//        if let fetchedStartTime = record["startTime"] as? Date {
//            self.startTime = fetchedStartTime
//        } else {
//            self.startTime = nil
//        }
//        self.duration = record["duration"] as? TimeInterval ?? 25 * 60
//        self.isBreak = record["isBreak"] as? Bool ?? false
//    }
//
//    /// Save (create or modify) the record in CloudKit
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

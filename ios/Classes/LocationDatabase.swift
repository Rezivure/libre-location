import Foundation
import SQLite3

/// SQLite-based local persistence for location data on iOS.
/// Uses the sqlite3 C API directly (available on iOS without dependencies).
/// Schema mirrors the Android LocationDatabase for consistency.
final class LocationDatabase {

    static let shared = LocationDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "io.rezivure.libre_location.db", qos: .utility)

    // Maintenance constants
    private static let defaultMaxAgeDays = 7
    private static let defaultMaxRecords = 10000
    private static let maintenanceInterval: TimeInterval = 3600 // 1 hour

    private var maintenanceTimer: Timer?

    private init() {
        openDatabase()
        createTable()
        performMaintenance()
        schedulePeriodicMaintenance()
    }

    deinit {
        maintenanceTimer?.invalidate()
        if db != nil {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            LibreLocationPlugin.log("LocationDatabase: Could not find app support directory")
            return
        }

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let dbPath = appSupport.appendingPathComponent("libre_location.db").path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let errmsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            LibreLocationPlugin.log("LocationDatabase: Failed to open database: \(errmsg)")
            db = nil
        }

        // Enable WAL mode for better concurrent performance
        exec("PRAGMA journal_mode=WAL")
    }

    private func createTable() {
        let sql = """
            CREATE TABLE IF NOT EXISTS locations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                latitude REAL,
                longitude REAL,
                altitude REAL,
                accuracy REAL,
                speed REAL,
                heading REAL,
                timestamp INTEGER,
                provider TEXT,
                is_moving INTEGER,
                battery_level INTEGER,
                is_charging INTEGER,
                delivered INTEGER DEFAULT 0
            )
            """
        exec(sql)

        // Index for efficient undelivered queries
        exec("CREATE INDEX IF NOT EXISTS idx_delivered ON locations(delivered)")
        exec("CREATE INDEX IF NOT EXISTS idx_timestamp ON locations(timestamp)")
    }

    // MARK: - Public API

    /// Insert a location record from a map (same format as locationToMap output).
    func insertLocation(_ map: [String: Any]) {
        queue.async { [weak self] in
            self?._insertLocation(map)
        }
    }

    /// Get all undelivered locations, ordered oldest first.
    func getUndelivered() -> [[String: Any]] {
        var results: [[String: Any]] = []
        queue.sync {
            results = _getUndelivered()
        }
        return results
    }

    /// Mark locations as delivered by their database IDs.
    func markDelivered(_ ids: [Int64]) {
        queue.async { [weak self] in
            self?._markDelivered(ids)
        }
    }

    /// Delete locations older than the specified number of days.
    func deleteOlderThan(days: Int) {
        queue.async { [weak self] in
            self?._deleteOlderThan(days: days)
        }
    }

    /// Delete excess records, keeping only the most recent maxRecords.
    func deleteExcess(maxRecords: Int) {
        queue.async { [weak self] in
            self?._deleteExcess(maxRecords: maxRecords)
        }
    }

    /// Get the total number of location records.
    func getCount() -> Int {
        var count = 0
        queue.sync {
            count = _getCount()
        }
        return count
    }

    // MARK: - Private Implementation

    private func _insertLocation(_ map: [String: Any]) {
        guard let db = db else { return }

        let sql = """
            INSERT INTO locations (latitude, longitude, altitude, accuracy, speed, heading, timestamp, provider, is_moving, battery_level, is_charging, delivered)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("insertLocation prepare"); return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, map["latitude"] as? Double ?? 0)
        sqlite3_bind_double(stmt, 2, map["longitude"] as? Double ?? 0)
        sqlite3_bind_double(stmt, 3, map["altitude"] as? Double ?? 0)
        sqlite3_bind_double(stmt, 4, map["accuracy"] as? Double ?? 0)
        sqlite3_bind_double(stmt, 5, map["speed"] as? Double ?? 0)
        sqlite3_bind_double(stmt, 6, map["heading"] as? Double ?? 0)
        sqlite3_bind_int64(stmt, 7, Int64(map["timestamp"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)))
        
        let provider = (map["provider"] as? String) ?? "unknown"
        sqlite3_bind_text(stmt, 8, (provider as NSString).utf8String, -1, nil)
        
        sqlite3_bind_int(stmt, 9, (map["isMoving"] as? Bool ?? false) ? 1 : 0)
        sqlite3_bind_int(stmt, 10, Int32(map["batteryLevel"] as? Int ?? -1))
        sqlite3_bind_int(stmt, 11, (map["isCharging"] as? Bool ?? false) ? 1 : 0)

        if sqlite3_step(stmt) != SQLITE_DONE {
            logError("insertLocation step")
        }
    }

    private func _getUndelivered() -> [[String: Any]] {
        guard let db = db else { return [] }

        let sql = "SELECT id, latitude, longitude, altitude, accuracy, speed, heading, timestamp, provider, is_moving, battery_level, is_charging FROM locations WHERE delivered = 0 ORDER BY timestamp ASC"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("getUndelivered prepare"); return []
        }
        defer { sqlite3_finalize(stmt) }

        var results: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            row["_dbId"] = sqlite3_column_int64(stmt, 0)
            row["latitude"] = sqlite3_column_double(stmt, 1)
            row["longitude"] = sqlite3_column_double(stmt, 2)
            row["altitude"] = sqlite3_column_double(stmt, 3)
            row["accuracy"] = sqlite3_column_double(stmt, 4)
            row["speed"] = sqlite3_column_double(stmt, 5)
            row["heading"] = sqlite3_column_double(stmt, 6)
            row["timestamp"] = sqlite3_column_int64(stmt, 7)
            
            if let cStr = sqlite3_column_text(stmt, 8) {
                row["provider"] = String(cString: cStr)
            } else {
                row["provider"] = "unknown"
            }
            
            row["isMoving"] = sqlite3_column_int(stmt, 9) != 0
            let batteryLevel = sqlite3_column_int(stmt, 10)
            if batteryLevel >= 0 { row["batteryLevel"] = Int(batteryLevel) }
            row["isCharging"] = sqlite3_column_int(stmt, 11) != 0
            
            results.append(row)
        }
        return results
    }

    private func _markDelivered(_ ids: [Int64]) {
        guard let db = db, !ids.isEmpty else { return }

        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = "UPDATE locations SET delivered = 1 WHERE id IN (\(placeholders))"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("markDelivered prepare"); return
        }
        defer { sqlite3_finalize(stmt) }

        for (i, id) in ids.enumerated() {
            sqlite3_bind_int64(stmt, Int32(i + 1), id)
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            logError("markDelivered step")
        }
    }

    private func _deleteOlderThan(days: Int) {
        guard let db = db else { return }

        let cutoff = Int64((Date().timeIntervalSince1970 - Double(days * 86400)) * 1000)
        let sql = "DELETE FROM locations WHERE timestamp < ? AND delivered = 1"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("deleteOlderThan prepare"); return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, cutoff)
        if sqlite3_step(stmt) != SQLITE_DONE {
            logError("deleteOlderThan step")
        } else {
            let deleted = sqlite3_changes(db)
            if deleted > 0 {
                LibreLocationPlugin.log("LocationDatabase: Deleted \(deleted) old records")
            }
        }
    }

    private func _deleteExcess(maxRecords: Int) {
        guard let db = db else { return }

        let sql = "DELETE FROM locations WHERE id NOT IN (SELECT id FROM locations ORDER BY timestamp DESC LIMIT ?)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("deleteExcess prepare"); return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(maxRecords))
        if sqlite3_step(stmt) != SQLITE_DONE {
            logError("deleteExcess step")
        } else {
            let deleted = sqlite3_changes(db)
            if deleted > 0 {
                LibreLocationPlugin.log("LocationDatabase: Trimmed \(deleted) excess records")
            }
        }
    }

    private func _getCount() -> Int {
        guard let db = db else { return 0 }

        let sql = "SELECT COUNT(*) FROM locations"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    // MARK: - Maintenance

    private func performMaintenance() {
        deleteOlderThan(days: Self.defaultMaxAgeDays)
        deleteExcess(maxRecords: Self.defaultMaxRecords)
    }

    private func schedulePeriodicMaintenance() {
        DispatchQueue.main.async { [weak self] in
            self?.maintenanceTimer = Timer.scheduledTimer(
                withTimeInterval: Self.maintenanceInterval,
                repeats: true
            ) { [weak self] _ in
                self?.performMaintenance()
            }
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db = db else { return false }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            LibreLocationPlugin.log("LocationDatabase SQL error: \(msg)")
            return false
        }
        return true
    }

    private func logError(_ context: String) {
        let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        LibreLocationPlugin.log("LocationDatabase \(context) error: \(msg)")
    }
}

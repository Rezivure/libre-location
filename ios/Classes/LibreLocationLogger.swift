import Foundation
import os.log

/// Structured logging system for iOS native layer.
/// Uses os_log with subsystem "io.rezivure.libre_location" and stores
/// the last N entries in memory for retrieval via getLog().
final class LibreLocationNativeLogger {

    static var logLevel: Int = 0 // 0=off, 1=error, 2=warning, 3=info, 4=debug, 5=verbose
    private static let maxEntries = 500
    private static var entries: [[String: Any]] = []
    private static let lock = NSLock()

    private static let subsystem = "io.rezivure.libre_location"
    private static let category = "location"

    @available(iOS 10.0, *)
    private static let osLog = OSLog(subsystem: subsystem, category: category)

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func verbose(_ message: String) { log(5, "verbose", message) }
    static func debug(_ message: String) { log(4, "debug", message) }
    static func info(_ message: String) { log(3, "info", message) }
    static func warning(_ message: String) { log(2, "warning", message) }
    static func error(_ message: String) { log(1, "error", message) }

    private static func log(_ level: Int, _ levelName: String, _ message: String) {
        guard logLevel > 0, level <= logLevel else { return }

        // Write to os_log
        if #available(iOS 10.0, *) {
            let type: OSLogType
            switch level {
            case 1: type = .error
            case 2: type = .default  // warning
            case 3: type = .info
            case 4: type = .debug
            default: type = .debug
            }
            os_log("%{public}@", log: osLog, type: type, message)
        }

        // Store in ring buffer
        let entry: [String: Any] = [
            "timestamp": dateFormatter.string(from: Date()),
            "level": levelName,
            "message": message,
            "platform": "ios",
        ]

        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst()
        }
        lock.unlock()
    }

    static func getLog() -> [[String: Any]] {
        lock.lock()
        let result = entries
        lock.unlock()
        return result
    }

    static func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

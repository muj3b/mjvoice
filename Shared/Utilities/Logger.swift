import Foundation

public enum LogLevel: String { case debug, info, warn, error }

public struct Logger {
    public static var isDebugEnabled = true

    public static func log(_ level: LogLevel, _ message: @autoclosure () -> String) {
        #if DEBUG
        if level == .debug || isDebugEnabled {
            NSLog("[mjvoice][\(level.rawValue.uppercased())] \(message())")
        }
        #else
        if level != .debug {
            NSLog("[mjvoice][\(level.rawValue.uppercased())] \(message())")
        }
        #endif
    }
}

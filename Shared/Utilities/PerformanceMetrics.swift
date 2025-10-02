import Foundation

public struct PerformanceMetrics {
    public static func measure<T>(_ label: String, block: () -> T) -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = block()
        let end = CFAbsoluteTimeGetCurrent()
        NSLog("[Perf] \(label): \(String(format: "%.3f", end - start))s")
        return result
    }
}

import Foundation
struct SystemReading {
    var cpu: Double?; var memoryUsed: Double?; var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    var diskUsed: Double?; var diskTotal: Double?; var download: Double?; var upload: Double?
    var date = Date()
    static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if value >= 1_000_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
        return String(format: "%.0f KB/s", value / 1_000)
    }
    static func memory(_ value: Double?) -> String { value.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "—" }
    static func bytes(_ value: Double?) -> String { value.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "—" }
    static func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", min(100,max(0,$0))) } ?? "—" }
}


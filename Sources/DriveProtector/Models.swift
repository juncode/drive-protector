import Foundation

// MARK: - 磁盘与卷

struct VolumeInfo: Hashable {
    let name: String
    let mountPath: String
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    var usedFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }
}

struct DiskInfo: Identifiable, Hashable {
    let bsdName: String          // 例如 disk5
    let model: String
    let vendor: String?
    let serial: String?
    let firmware: String?
    let sizeBytes: Int64
    let isRemovable: Bool
    let isExternal: Bool
    let isSSD: Bool
    let interconnect: String     // PCI-Express / USB / Thunderbolt / SATA / Unknown
    let volumes: [VolumeInfo]

    var id: String { bsdName }
    var devicePath: String { "/dev/\(bsdName)" }

    var totalCapacity: Int64 { volumes.map(\.totalBytes).max() ?? sizeBytes }
    var availableCapacity: Int64 { volumes.map(\.availableBytes).max() ?? 0 }
    var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
    var usedFraction: Double {
        totalCapacity > 0 ? Double(usedCapacity) / Double(totalCapacity) : 0
    }

    var profile: DriveProfile {
        DriveProfile.match(model: model, sizeBytes: sizeBytes,
                           interconnect: interconnect, isExternal: isExternal)
    }

    var iconName: String {
        if isExternal { return "externaldrive.fill" }
        return "internaldrive.fill"
    }

    func withVolumes(_ volumes: [VolumeInfo]) -> DiskInfo {
        DiskInfo(
            bsdName: bsdName, model: model, vendor: vendor, serial: serial,
            firmware: firmware, sizeBytes: sizeBytes, isRemovable: isRemovable,
            isExternal: isExternal, isSSD: isSSD, interconnect: interconnect,
            volumes: volumes)
    }
}

struct RawDisk {
    let info: DiskInfo
    let bytesRead: Int64
    let bytesWritten: Int64
}

// MARK: - SMART

enum SMARTDataSource: String {
    case smartctl = "smartctl 实时数据"
    case demo = "演示数据"
}

enum AttrStatus {
    case good
    case warning
    case critical
    case info
}

struct SMARTAttribute: Identifiable, Hashable {
    let id: Int
    let name: String
    let value: Int?
    let worst: Int?
    let threshold: Int?
    let raw: Int64?
    let rawDisplay: String
    let status: AttrStatus
}

struct SMARTReport: Hashable {
    var healthPercent: Double
    var temperatureC: Double?
    var powerOnHours: Int64?
    var powerCycles: Int64?
    var bytesRead: Int64?
    var bytesWritten: Int64?
    var unsafeShutdowns: Int64?
    var mediaErrors: Int64?
    var overallPassed: Bool?
    var attributes: [SMARTAttribute]
    var source: SMARTDataSource
}

// MARK: - 实时吞吐

struct Throughput: Hashable {
    var readBytesPerSec: Double
    var writeBytesPerSec: Double
}

struct ThroughputSample: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let readMBps: Double
    let writeMBps: Double
}

// MARK: - 测速

struct BenchmarkResult: Hashable {
    var readMBps: Double
    var writeMBps: Double
    var sizeMB: Int
}

struct BenchmarkState {
    var running = false
    var progress: Double = 0
    var phase: String = ""
    var result: BenchmarkResult?
    var error: String?
}

// MARK: - 格式化

enum Fmt {
    static func capacity(_ bytes: Int64) -> String {
        let tb = Double(bytes) / 1_000_000_000_000
        if tb >= 1 { return String(format: "%.1f TB", tb) }
        let gb = Double(bytes) / 1_000_000_000
        return String(format: "%.0f GB", gb)
    }

    static func gb(_ bytes: Int64) -> String {
        String(format: "%.0f GB", Double(bytes) / 1_000_000_000)
    }

    static func tb(_ bytes: Int64) -> String {
        String(format: "%.2f TB", Double(bytes) / 1_000_000_000_000)
    }

    static func speed(_ bytesPerSec: Double) -> String {
        switch bytesPerSec {
        case 1_000_000_000...:
            return String(format: "%.2f GB/s", bytesPerSec / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.0f MB/s", bytesPerSec / 1_000_000)
        case 1_000...:
            return String(format: "%.0f KB/s", bytesPerSec / 1_000)
        default:
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }

    static func mbps(_ bytesPerSec: Double) -> String {
        String(format: "%.0f", bytesPerSec / 1_000_000)
    }

    static func hours(_ h: Int64?) -> String {
        guard let h else { return "—" }
        if h >= 24 * 365 {
            return String(format: "%.1f 年", Double(h) / (24 * 365))
        }
        if h >= 24 * 60 {
            return String(format: "%.0f 天", Double(h) / 24)
        }
        return "\(h) 小时"
    }

    static func number(_ v: Int64?) -> String {
        guard let v else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}

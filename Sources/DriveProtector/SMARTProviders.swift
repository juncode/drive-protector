import Foundation

/// SMART 数据来源：
/// 1. 优先调用开源 smartmontools 的 smartctl（若已安装），解析其 JSON 输出，
///    可覆盖内置 NVMe、SATA 以及支持 SAT 的 USB / 雷雳外接硬盘（含 D1 SSD PRO 等）。
/// 2. smartctl 查找顺序：App Bundle 内 Resources/bin/smartctl > 系统已安装路径
/// 3. 未安装 smartctl 时返回「演示数据」，保证界面可完整体验，并明确标注数据来源。
enum SMARTProvider {

    /// App Bundle 内的 smartctl 路径（打包脚本会自动嵌入）
    private static var bundledSmartctlPath: String? {
        Bundle.main.path(forResource: "smartctl", ofType: nil, inDirectory: "bin")
    }

    private static let systemCandidatePaths = [
        "/opt/homebrew/sbin/smartctl",
        "/opt/homebrew/bin/smartctl",
        "/usr/local/sbin/smartctl",
        "/usr/local/bin/smartctl",
        "/usr/bin/smartctl"
    ]

    /// 可执行的 smartctl 路径（优先 Bundle 内置）
    static var smartctlPath: String? {
        if let bundled = bundledSmartctlPath,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        return systemCandidatePaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    /// 是否已具备 SMART 读取能力
    static var isAvailable: Bool { smartctlPath != nil }

    // MARK: - 对外入口（在后台线程调用）

    static func load(for disk: DiskInfo,
                     readMBps: Double,
                     writeMBps: Double) -> SMARTReport {
        if let path = smartctlPath,
           let report = loadViaSmartCtl(path: path, disk: disk) {
            return report
        }
        return DemoData.report(for: disk, readMBps: readMBps, writeMBps: writeMBps)
    }

    // MARK: - smartctl

    private static func loadViaSmartCtl(path: String, disk: DiskInfo) -> SMARTReport? {
        // 1) 先用普通权限执行（内置 NVMe / USB-NVMe 通常不需要 root）
        if let data = runSmartctl(path: path, devicePath: disk.devicePath, elevated: false),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parseSmartCtlJSON(json, disk: disk)
        }

        // 2) 回退：用 osascript 提权执行（SATA / USB-SAT 桥接盘需要 root 发送 ATA SMART 命令）
        if let data = runSmartctl(path: path, devicePath: disk.devicePath, elevated: true),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parseSmartCtlJSON(json, disk: disk)
        }
        return nil
    }

    /// 执行 smartctl -j -a <device>
    /// - elevated: true 时通过 osascript 以管理员权限运行，会弹出系统密码框
    private static func runSmartctl(path: String, devicePath: String, elevated: Bool) -> Data? {
        let arguments = ["-j", "-a", devicePath]

        if !elevated {
            return runProcess(path, arguments: arguments)
        }

        // 提权执行：用 osascript 包装，smartctl 输出经 base64 避免 shell 转义问题
        let cmd = "'\(path)' \(arguments.map { "'\($0)'" }.joined(separator: " ")) | base64"
        let script = "do shell script \"\(cmd)\" with administrator privileges"
        let osa = Process()
        osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osa.arguments = ["-e", script]
        guard let out = runProcess("/usr/bin/osascript", arguments: osa.arguments!),
              let b64 = String(data: out, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: ""),
              let data = Data(base64Encoded: b64), !data.isEmpty
        else { return nil }
        return data
    }

    private static func runProcess(_ path: String, arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        // 部分 USB 桥接芯片可能长时间无响应，8 秒看门狗
        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return data.isEmpty ? nil : data
    }

    private static func parseSmartCtlJSON(_ json: [String: Any], disk: DiskInfo) -> SMARTReport? {
        var attributes: [SMARTAttribute] = []
        var health: Double?
        var temperature: Double?
        var hours: Int64?
        var cycles: Int64?
        var bytesRead: Int64?
        var bytesWritten: Int64?
        var unsafe: Int64?
        var mediaErrors: Int64?
        var passed: Bool?

        if let status = json["smart_status"] as? [String: Any] {
            passed = status["passed"] as? Bool
        }
        if let t = json["temperature"] as? [String: Any] {
            temperature = (t["current"] as? NSNumber)?.doubleValue
        }

        // NVMe 健康日志
        if let nvme = json["nvme_smart_health_information_log"] as? [String: Any] {
            let pctUsed = num(nvme["percentage_used"])?.doubleValue ?? 0
            health = max(0, min(100, 100 - pctUsed))
            temperature = temperature ?? num(nvme["temperature"])?.doubleValue
            hours = num(nvme["power_on_hours"])?.int64Value
            cycles = num(nvme["power_cycles"])?.int64Value

            let unitsRead = num(nvme["data_units_read"])?.int64Value
            let unitsWritten = num(nvme["data_units_written"])?.int64Value
            if let unitsRead { bytesRead = unitsRead * 512_000 }
            if let unitsWritten { bytesWritten = unitsWritten * 512_000 }
            unsafe = num(nvme["unsafe_shutdowns"])?.int64Value
            mediaErrors = num(nvme["media_errors"])?.int64Value
            let spare = num(nvme["available_spare"])?.int64Value
            let spareThr = num(nvme["available_spare_threshold"])?.int64Value
            let critical = num(nvme["critical_warning"])?.int64Value ?? 0

            attributes = [
                attr(1, "Critical Warning", raw: critical,
                     display: critical == 0 ? "0 (正常)" : "0x\(String(critical, radix: 16))",
                     status: critical == 0 ? .good : .critical),
                attr(2, "Temperature", raw: Int64(temperature ?? 0),
                     display: temperature.map { String(format: "%.0f°C", $0) } ?? "—",
                     status: tempStatus(temperature)),
                attr(3, "Available Spare", value: Int(spare ?? 0), raw: spare,
                     display: spare.map { "\($0)%" } ?? "—"),
                attr(4, "Available Spare Threshold", value: Int(spareThr ?? 0), raw: spareThr,
                     display: spareThr.map { "\($0)%" } ?? "—", status: .info),
                attr(5, "Percentage Used", raw: Int64(pctUsed), display: "\(Int(pctUsed))%",
                     status: pctUsed >= 90 ? .warning : .good),
                attr(6, "Data Units Read", raw: unitsRead,
                     display: unitsRead.map { Fmt.tb($0 * 512_000) } ?? "—"),
                attr(7, "Data Units Written", raw: unitsWritten,
                     display: unitsWritten.map { Fmt.tb($0 * 512_000) } ?? "—"),
                attr(8, "Power Cycles", raw: cycles),
                attr(9, "Power On Hours", raw: hours),
                attr(10, "Unsafe Shutdowns", raw: unsafe,
                     status: (unsafe ?? 0) > 0 ? .warning : .good),
                attr(11, "Media and Data Integrity Errors", raw: mediaErrors,
                     status: (mediaErrors ?? 0) > 0 ? .critical : .good),
                attr(12, "Error Information Log Entries",
                     raw: num(nvme["num_err_log_entries"])?.int64Value ?? 0)
            ]
        }

        // ATA / SATA / USB-SAT 属性表
        if let ata = json["ata_smart_attributes"] as? [String: Any],
           let table = ata["table"] as? [[String: Any]] {
            for entry in table {
                let id = num(entry["id"])?.intValue ?? 0
                let name = entry["name"] as? String ?? "Attribute \(id)"
                let value = num(entry["value"])?.intValue
                let worst = num(entry["worst"])?.intValue
                let thresh = num(entry["thresh"])?.intValue
                let rawDict = entry["raw"] as? [String: Any]
                let rawValue = num(rawDict?["value"])?.int64Value
                let rawString = rawDict?["string"] as? String
                    ?? rawValue.map { Fmt.number($0) } ?? "—"

                var status: AttrStatus = .good
                if let value, let thresh, thresh > 0, value <= thresh {
                    status = .critical
                } else if isErrorAttribute(id), (rawValue ?? 0) > 0 {
                    status = .warning
                }
                attributes.append(SMARTAttribute(
                    id: id, name: name, value: value, worst: worst,
                    threshold: thresh, raw: rawValue,
                    rawDisplay: rawString, status: status))
            }

            if health == nil {
                let byId = Dictionary(attributes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let life = byId[231]?.value ?? byId[177]?.value ?? byId[173]?.value
                if let life { health = Double(life) }
            }
            if hours == nil, let a9 = attributes.first(where: { $0.id == 9 }) {
                hours = a9.raw
            }
            if cycles == nil, let a12 = attributes.first(where: { $0.id == 12 }) {
                cycles = a12.raw
            }
            if bytesWritten == nil, let a241 = attributes.first(where: { $0.id == 241 }) {
                bytesWritten = (a241.raw ?? 0) * 512
            }
            if bytesRead == nil, let a242 = attributes.first(where: { $0.id == 242 }) {
                bytesRead = (a242.raw ?? 0) * 512
            }
        }

        guard !attributes.isEmpty else { return nil }

        return SMARTReport(
            healthPercent: health ?? 100,
            temperatureC: temperature,
            powerOnHours: hours,
            powerCycles: cycles,
            bytesRead: bytesRead,
            bytesWritten: bytesWritten,
            unsafeShutdowns: unsafe,
            mediaErrors: mediaErrors,
            overallPassed: passed,
            attributes: attributes.sorted { $0.id < $1.id },
            source: .smartctl)
    }

    private static func isErrorAttribute(_ id: Int) -> Bool {
        [5, 183, 184, 187, 196, 197, 198, 199, 201, 202, 220].contains(id)
    }

    private static func tempStatus(_ t: Double?) -> AttrStatus {
        guard let t else { return .info }
        if t >= 70 { return .critical }
        if t >= 55 { return .warning }
        return .good
    }

    private static func attr(_ id: Int, _ name: String,
                             value: Int? = nil, worst: Int? = nil,
                             threshold: Int? = nil, raw: Int64? = nil,
                             display: String? = nil,
                             status: AttrStatus = .good) -> SMARTAttribute {
        SMARTAttribute(id: id, name: name, value: value, worst: worst,
                       threshold: threshold, raw: raw,
                       rawDisplay: display ?? raw.map { Fmt.number($0) } ?? "—",
                       status: status)
    }

    private static func num(_ any: Any?) -> NSNumber? {
        any as? NSNumber
    }
}

// MARK: - 演示数据（确定性生成，温度随实时负载波动）

enum DemoData {

    static func report(for disk: DiskInfo,
                       readMBps: Double,
                       writeMBps: Double) -> SMARTReport {
        let h = stableHash(disk.bsdName + "|" + disk.model)
        let health = 86.0 + Double(h % 12)            // 86% - 97%
        let hours = 600 + Int64(h % 12_000)
        let cycles = 120 + Int64((h >> 5) % 2_400)

        let tbwTB = disk.profile.tbwTB ?? DriveProfile.estimatedTBW(sizeBytes: disk.sizeBytes)
        let usedTB = Int64(Double(tbwTB) * (100 - health) / 100.0) + Int64(60 + h % 200)
        let bytesWritten = usedTB * 1_000_000_000_000
        let bytesRead = bytesWritten * (2 + Int64(h % 4))

        let unsafe: Int64 = (h % 11 == 0) ? Int64(2 + h % 5) : Int64(h % 3)
        let mediaErrors: Int64 = (h % 29 == 0) ? 1 : 0
        let temperature = 30.0
            + min(25.0, readMBps / 140.0 + writeMBps / 110.0)
            + Double(h % 5)

        let isNVMe = disk.profile.isNVMe || disk.interconnect == "PCI-Express"
        let attributes: [SMARTAttribute] = isNVMe
            ? nvmeAttributes(health: health, temperature: temperature, hours: hours,
                             cycles: cycles, bytesRead: bytesRead, bytesWritten: bytesWritten,
                             unsafe: unsafe, mediaErrors: mediaErrors, h: h)
            : ataAttributes(health: health, temperature: temperature, hours: hours,
                            cycles: cycles, bytesRead: bytesRead, bytesWritten: bytesWritten,
                            unsafe: unsafe, mediaErrors: mediaErrors, h: h)

        return SMARTReport(
            healthPercent: health,
            temperatureC: temperature,
            powerOnHours: hours,
            powerCycles: cycles,
            bytesRead: bytesRead,
            bytesWritten: bytesWritten,
            unsafeShutdowns: unsafe,
            mediaErrors: mediaErrors,
            overallPassed: true,
            attributes: attributes,
            source: .demo)
    }

    private static func nvmeAttributes(
        health: Double, temperature: Double, hours: Int64, cycles: Int64,
        bytesRead: Int64, bytesWritten: Int64, unsafe: Int64, mediaErrors: Int64, h: UInt64
    ) -> [SMARTAttribute] {
        let pctUsed = Int64(100 - health)
        let unitsRead = bytesRead / 512_000
        let unitsWritten = bytesWritten / 512_000
        func a(_ id: Int, _ name: String, raw: Int64? = nil,
               display: String, value: Int? = nil, status: AttrStatus = .good) -> SMARTAttribute {
            SMARTAttribute(id: id, name: name, value: value, worst: nil, threshold: nil,
                           raw: raw, rawDisplay: display, status: status)
        }
        return [
            a(1, "Critical Warning", raw: 0, display: "0 (正常)"),
            a(2, "Temperature", raw: Int64(temperature),
              display: String(format: "%.1f°C", temperature),
              status: temperature >= 70 ? .critical : temperature >= 55 ? .warning : .good),
            a(3, "Available Spare", raw: 100, display: "100%", value: 100),
            a(4, "Available Spare Threshold", raw: 10, display: "10%", value: 10, status: .info),
            a(5, "Percentage Used", raw: pctUsed, display: "\(pctUsed)%",
              value: Int(health), status: health < 15 ? .warning : .good),
            a(6, "Data Units Read", raw: unitsRead, display: Fmt.tb(bytesRead)),
            a(7, "Data Units Written", raw: unitsWritten, display: Fmt.tb(bytesWritten)),
            a(8, "Power Cycles", raw: cycles, display: Fmt.number(cycles)),
            a(9, "Power On Hours", raw: hours, display: Fmt.number(hours)),
            a(10, "Unsafe Shutdowns", raw: unsafe,
              display: Fmt.number(unsafe), status: unsafe > 0 ? .warning : .good),
            a(11, "Media and Data Integrity Errors", raw: mediaErrors,
              display: Fmt.number(mediaErrors),
              status: mediaErrors > 0 ? .critical : .good),
            a(12, "Error Information Log Entries", raw: Int64(h % 7),
              display: Fmt.number(Int64(h % 7)), status: .info)
        ]
    }

    private static func ataAttributes(
        health: Double, temperature: Double, hours: Int64, cycles: Int64,
        bytesRead: Int64, bytesWritten: Int64, unsafe: Int64, mediaErrors: Int64, h: UInt64
    ) -> [SMARTAttribute] {
        let hv = Int(health)
        let lbaWritten = bytesWritten / 512
        let lbaRead = bytesRead / 512
        func a(_ id: Int, _ name: String, value: Int? = nil, worst: Int? = nil,
               threshold: Int? = nil, raw: Int64? = nil,
               display: String? = nil, status: AttrStatus = .good) -> SMARTAttribute {
            SMARTAttribute(id: id, name: name, value: value, worst: worst,
                           threshold: threshold, raw: raw,
                           rawDisplay: display ?? raw.map { Fmt.number($0) } ?? "—",
                           status: status)
        }
        return [
            a(1, "Raw Read Error Rate", value: 100, worst: 100, threshold: 6, raw: 0),
            a(5, "Reallocated Sectors Count", value: 100, worst: 100, threshold: 10, raw: 0),
            a(9, "Power-On Hours", value: 100, raw: hours),
            a(12, "Power Cycle Count", value: 100, raw: cycles),
            a(173, "Wear Leveling Count", value: hv, worst: max(0, hv - 2),
              threshold: 0, raw: 100 - Int64(health)),
            a(174, "Unexpected Power Loss", value: 100, raw: unsafe,
              status: unsafe > 0 ? .warning : .good),
            a(177, "Wear Leveling Count", value: hv, worst: max(0, hv - 3),
              threshold: 0, raw: 100 - Int64(health) + 2),
            a(181, "Program Fail Count", value: 100, worst: 100, threshold: 0, raw: 0),
            a(182, "Erase Fail Count", value: 100, worst: 100, threshold: 0, raw: 0),
            a(183, "Runtime Bad Block Total", value: 100, worst: 100, threshold: 0, raw: 0),
            a(184, "End-to-End Error Count", value: 100, worst: 100, threshold: 0,
              raw: mediaErrors, status: mediaErrors > 0 ? .critical : .good),
            a(187, "Reported Uncorrectable Errors", value: 100, worst: 100, threshold: 0,
              raw: mediaErrors, status: mediaErrors > 0 ? .warning : .good),
            a(194, "Temperature Celsius", value: min(100, max(0, 100 - Int(temperature))),
              worst: 70, threshold: 0, raw: Int64(temperature),
              display: String(format: "%.1f°C", temperature),
              status: temperature >= 70 ? .critical : temperature >= 55 ? .warning : .good),
            a(199, "UDMA CRC Error Count", value: 100, worst: 100, threshold: 0,
              raw: Int64(h % 3), status: (h % 3) > 0 ? .info : .good),
            a(231, "SSD Life Left", value: hv, worst: max(0, hv - 1), threshold: 0,
              raw: Int64(health), display: "\(hv)%"),
            a(241, "Total LBAs Written", value: 100, raw: lbaWritten),
            a(242, "Total LBAs Read", value: 100, raw: lbaRead),
            a(245, "NAND Writes (1GiB)", value: 100,
              raw: bytesWritten / 1_000_000_000, display: Fmt.gb(bytesWritten))
        ]
    }

    // FNV-1a 64 位哈希：同一块磁盘每次生成稳定数据
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

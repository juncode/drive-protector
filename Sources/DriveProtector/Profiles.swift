import Foundation

/// 硬盘型号档案：为常见/主流硬盘提供厂商规格（顺序读写标称值、TBW、保修等），
/// 用于仪表盘展示与速率量程标定。匹配方式为型号名称关键字匹配。
struct DriveProfile {
    let vendor: String
    let productLine: String
    let interface: String
    let formFactor: String
    let maxReadMBps: Double
    let maxWriteMBps: Double
    let warrantyYears: Int
    let tbwTB: Int?
    let isExternal: Bool
    let isNVMe: Bool
    let features: [String]

    /// 外接便携 SSD 默认 TBW 未知时按容量估算（约 600 TBW / TB 容量）
    static func estimatedTBW(sizeBytes: Int64) -> Int {
        let tb = max(1, Int((Double(sizeBytes) / 1_000_000_000_000).rounded()))
        return tb * 600
    }
}

extension DriveProfile {

    // MARK: 型号库（匹配关键字按特异性从高到低排列）
    private struct Entry {
        let keywords: [String]
        let profile: DriveProfile
    }

    private static let entries: [Entry] = [
        // MARK: D1 SSD PRO（外接移动固态）
        Entry(keywords: ["d1 ssd pro", "d1ssdpro", "d1 pro"],
              profile: DriveProfile(
                vendor: "D1", productLine: "D1 SSD PRO 移动固态",
                interface: "USB 3.2 Gen 2 (10 Gbps)", formFactor: "便携式 SSD",
                maxReadMBps: 1050, maxWriteMBps: 1000,
                warrantyYears: 5, tbwTB: nil, isExternal: true, isNVMe: false,
                features: ["UASP 加速", "USB Type-C", "即插即用", "TRIM 支持"])),

        // MARK: 西部数据 WD_BLACK SN8100（PCIe 5.0 旗舰，含 4TB）
        Entry(keywords: ["sn8100"],
              profile: DriveProfile(
                vendor: "Western Digital", productLine: "WD_BLACK SN8100",
                interface: "PCIe 5.0 x4 (NVMe 2.0)", formFactor: "M.2 2280",
                maxReadMBps: 14800, maxWriteMBps: 14000,
                warrantyYears: 5, tbwTB: 2400, isExternal: false, isNVMe: true,
                features: ["NVMe 2.0", "PCIe 5.0", "2400+ MTBF", "全速动态 SLC 缓存", "游戏模式 2.0"])),

        Entry(keywords: ["sn850x", "sn850"],
              profile: DriveProfile(
                vendor: "Western Digital", productLine: "WD_BLACK SN850X",
                interface: "PCIe 4.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 7300, maxWriteMBps: 6600,
                warrantyYears: 5, tbwTB: 2400, isExternal: false, isNVMe: true,
                features: ["NVMe 1.4", "PCIe 4.0", "Game Mode 2.0", "自适应热能效管理"])),

        Entry(keywords: ["sn7100"],
              profile: DriveProfile(
                vendor: "Western Digital", productLine: "WD_BLACK SN7100",
                interface: "PCIe 4.0 x4 (NVMe)", formFactor: "M.2 2230/2280",
                maxReadMBps: 4900, maxWriteMBps: 4700,
                warrantyYears: 5, tbwTB: 600, isExternal: false, isNVMe: true,
                features: ["NVMe 1.4", "单面颗粒", "低功耗"])),

        Entry(keywords: ["sn770"],
              profile: DriveProfile(
                vendor: "Western Digital", productLine: "WD_BLACK SN770",
                interface: "PCIe 4.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 5150, maxWriteMBps: 4900,
                warrantyYears: 5, tbwTB: 600, isExternal: false, isNVMe: true,
                features: ["NVMe 1.4", "无 DRAM 设计", "游戏模式"])),

        Entry(keywords: ["sn580"],
              profile: DriveProfile(
                vendor: "Western Digital", productLine: "WD Blue SN580",
                interface: "PCIe 4.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 4150, maxWriteMBps: 4100,
                warrantyYears: 5, tbwTB: 600, isExternal: false, isNVMe: true,
                features: ["NVMe 1.4", "nCache 4.0", "低功耗"])),

        Entry(keywords: ["sn5000"],
              profile: DriveProfile(
                vendor: "Western Digital", productLine: "WD Blue SN5000",
                interface: "PCIe 4.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 5000, maxWriteMBps: 4200,
                warrantyYears: 5, tbwTB: 600, isExternal: false, isNVMe: true,
                features: ["NVMe 2.0", "PCIe 4.0", "低功耗温控"])),

        // MARK: 三星
        Entry(keywords: ["990 pro"],
              profile: DriveProfile(
                vendor: "Samsung", productLine: "990 PRO",
                interface: "PCIe 4.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 7450, maxWriteMBps: 6900,
                warrantyYears: 5, tbwTB: 2400, isExternal: false, isNVMe: true,
                features: ["NVMe 2.0", "V7 V-NAND", "RGB 散热片版可选", "全速性能模式"])),

        Entry(keywords: ["980 pro"],
              profile: DriveProfile(
                vendor: "Samsung", productLine: "980 PRO",
                interface: "PCIe 4.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 7000, maxWriteMBps: 5100,
                warrantyYears: 5, tbwTB: 1200, isExternal: false, isNVMe: true,
                features: ["NVMe 1.3c", "V7 V-NAND", "Magician 支持"])),

        Entry(keywords: ["970 evo plus", "970 evo+"],
              profile: DriveProfile(
                vendor: "Samsung", productLine: "970 EVO Plus",
                interface: "PCIe 3.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 3500, maxWriteMBps: 3300,
                warrantyYears: 5, tbwTB: 1200, isExternal: false, isNVMe: true,
                features: ["NVMe 1.3", "V5/V6 V-NAND"])),

        Entry(keywords: ["970 evo"],
              profile: DriveProfile(
                vendor: "Samsung", productLine: "970 EVO",
                interface: "PCIe 3.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 3400, maxWriteMBps: 2500,
                warrantyYears: 5, tbwTB: 600, isExternal: false, isNVMe: true,
                features: ["NVMe 1.3", "Phoenix 控制器"])),

        Entry(keywords: ["870 evo"],
              profile: DriveProfile(
                vendor: "Samsung", productLine: "870 EVO",
                interface: "SATA 6 Gbps", formFactor: "2.5 英寸 / M.2",
                maxReadMBps: 560, maxWriteMBps: 530,
                warrantyYears: 5, tbwTB: 2400, isExternal: false, isNVMe: false,
                features: ["SATA III", "MKX 控制器", "V-NAND"])),

        Entry(keywords: ["portable t9", "t9 shield", "portable ssd t9"],
              profile: DriveProfile(
                vendor: "Samsung", productLine: "Portable SSD T9",
                interface: "USB 3.2 Gen 2x2 (20 Gbps)", formFactor: "便携式 SSD",
                maxReadMBps: 2000, maxWriteMBps: 1950,
                warrantyYears: 5, tbwTB: nil, isExternal: true, isNVMe: false,
                features: ["USB 3.2 Gen 2x2", "Type-C", "抗震防摔"])),

        Entry(keywords: ["t7 shield", "portable t7", "portable ssd t7"],
              profile: DriveProfile(
                vendor: "Samsung", productLine: "Portable SSD T7",
                interface: "USB 3.2 Gen 2 (10 Gbps)", formFactor: "便携式 SSD",
                maxReadMBps: 1050, maxWriteMBps: 1000,
                warrantyYears: 5, tbwTB: nil, isExternal: true, isNVMe: false,
                features: ["UASP", "Type-C", "硬件加密", "跌落防护"])),

        // MARK: 英睿达 / 美光
        Entry(keywords: ["t705"],
              profile: DriveProfile(
                vendor: "Crucial", productLine: "T705",
                interface: "PCIe 5.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 14500, maxWriteMBps: 12700,
                warrantyYears: 5, tbwTB: 2400, isExternal: false, isNVMe: true,
                features: ["NVMe 2.0", "PCIe 5.0", "232 层 NAND"])),

        Entry(keywords: ["t700"],
              profile: DriveProfile(
                vendor: "Crucial", productLine: "T700",
                interface: "PCIe 5.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 12400, maxWriteMBps: 11800,
                warrantyYears: 5, tbwTB: 2400, isExternal: false, isNVMe: true,
                features: ["NVMe 2.0", "PCIe 5.0", "主动散热片可选"])),

        Entry(keywords: ["t500"],
              profile: DriveProfile(
                vendor: "Crucial", productLine: "T500",
                interface: "PCIe 4.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 7400, maxWriteMBps: 7000,
                warrantyYears: 5, tbwTB: 1200, isExternal: false, isNVMe: true,
                features: ["NVMe 2.0", "232 层 TLC NAND"])),

        // MARK: 金士顿 / 希捷 / SK 海力士 / Solidigm
        Entry(keywords: ["kc3000"],
              profile: DriveProfile(
                vendor: "Kingston", productLine: "KC3000",
                interface: "PCIe 4.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 7000, maxWriteMBps: 7000,
                warrantyYears: 5, tbwTB: 1600, isExternal: false, isNVMe: true,
                features: ["NVMe 1.4", "石墨烯散热"])),

        Entry(keywords: ["fury renegade"],
              profile: DriveProfile(
                vendor: "Kingston", productLine: "Fury Renegade",
                interface: "PCIe 4.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 7300, maxWriteMBps: 6600,
                warrantyYears: 5, tbwTB: 1000, isExternal: false, isNVMe: true,
                features: ["NVMe 2.0", "石墨烯散热标签"])),

        Entry(keywords: ["firecuda 540"],
              profile: DriveProfile(
                vendor: "Seagate", productLine: "FireCuda 540",
                interface: "PCIe 5.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 10000, maxWriteMBps: 10000,
                warrantyYears: 5, tbwTB: 2200, isExternal: false, isNVMe: true,
                features: ["NVMe 2.0", "PCIe 5.0", "3D TLC"])),

        Entry(keywords: ["firecuda 530"],
              profile: DriveProfile(
                vendor: "Seagate", productLine: "FireCuda 530",
                interface: "PCIe 4.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 7300, maxWriteMBps: 6900,
                warrantyYears: 5, tbwTB: 1275, isExternal: false, isNVMe: true,
                features: ["NVMe 1.4", "E18 控制器"])),

        Entry(keywords: ["platinum p41", "p41 platinum"],
              profile: DriveProfile(
                vendor: "SK hynix", productLine: "Platinum P41",
                interface: "PCIe 4.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 7000, maxWriteMBps: 6500,
                warrantyYears: 5, tbwTB: 1200, isExternal: false, isNVMe: true,
                features: ["NVMe 1.4", "176 层 TLC NAND"])),

        Entry(keywords: ["gold p31"],
              profile: DriveProfile(
                vendor: "SK hynix", productLine: "Gold P31",
                interface: "PCIe 3.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 3500, maxWriteMBps: 3200,
                warrantyYears: 5, tbwTB: 750, isExternal: false, isNVMe: true,
                features: ["NVMe 1.3", "128 层 TLC", "低功耗"])),

        Entry(keywords: ["p44 pro"],
              profile: DriveProfile(
                vendor: "Solidigm", productLine: "P44 Pro",
                interface: "PCIe 4.0 x4 (NVMe)", formFactor: "M.2 2280",
                maxReadMBps: 7000, maxWriteMBps: 6500,
                warrantyYears: 5, tbwTB: 1200, isExternal: false, isNVMe: true,
                features: ["NVMe 2.0", "144 层 NAND"])),
    ]

    static func match(model: String, sizeBytes: Int64,
                      interconnect: String, isExternal: Bool) -> DriveProfile {
        let haystack = model.lowercased()
        for entry in entries where entry.keywords.contains(where: { haystack.contains($0) }) {
            return entry.profile
        }

        // 未命中型号库：按接口/厂商给出通用规格
        if let apple = appleFallback(model: model) { return apple }

        switch interconnect {
        case "USB", "Thunderbolt":
            return DriveProfile(
                vendor: "通用", productLine: "外接移动 SSD",
                interface: interconnect == "Thunderbolt" ? "Thunderbolt / USB-C" : "USB",
                formFactor: "便携式 SSD",
                maxReadMBps: 1050, maxWriteMBps: 1000,
                warrantyYears: 3, tbwTB: nil, isExternal: true, isNVMe: false,
                features: ["UASP", "Type-C", "热插拔"])
        case "SATA":
            return DriveProfile(
                vendor: "通用", productLine: "SATA SSD",
                interface: "SATA 6 Gbps", formFactor: "2.5 英寸 / M.2",
                maxReadMBps: 560, maxWriteMBps: 530,
                warrantyYears: 3, tbwTB: estimatedTBW(sizeBytes: sizeBytes),
                isExternal: false, isNVMe: false,
                features: ["SATA III", "TRIM", "NCQ"])
        default:
            return DriveProfile(
                vendor: "通用", productLine: "NVMe SSD",
                interface: "PCIe NVMe", formFactor: "M.2",
                maxReadMBps: 7000, maxWriteMBps: 6000,
                warrantyYears: 5, tbwTB: estimatedTBW(sizeBytes: sizeBytes),
                isExternal: isExternal, isNVMe: true,
                features: ["NVMe", "PCI Express", "TRIM"])
        }
    }

    private static func appleFallback(model: String) -> DriveProfile? {
        let m = model.lowercased()
        guard m.contains("apple") || m.contains("appl") else { return nil }
        return DriveProfile(
            vendor: "Apple", productLine: "Apple 内置 SSD",
            interface: "Apple 定制 NVMe (PCIe)", formFactor: "板载 / 模组",
            maxReadMBps: 7400, maxWriteMBps: 6500,
            warrantyYears: 0, tbwTB: nil, isExternal: false, isNVMe: true,
            features: ["Apple 定制控制器", "统一内存架构存储", "硬件加密", "APFS"])
    }
}

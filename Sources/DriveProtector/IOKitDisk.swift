import Foundation
import IOKit
import DiskArbitration

/// 通过 IOKit 枚举整机物理磁盘（含外接 USB / 雷雳硬盘），
/// 并从 IOBlockStorageDriver 的 Statistics 读取累计读写字节数（无需特权）。
enum IOKitDisk {

    private struct Node {
        let name: String
        let className: String
        let props: [String: Any]
    }

    // MARK: - 枚举

    static func enumerate() -> [RawDisk] {
        // 注意：IOServiceMatching("IOMedia") 在部分 macOS 版本上无法枚举到
        // 外接 NVMe / 雷电盘的 IOMedia 节点，因此改用从服务树根节点递归遍历，
        // 可可靠地发现所有整盘（含外接 USB / 雷雳 / 雷电硬盘）。
        var result: [RawDisk] = []
        var aliases: [String: String] = [:]

        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return [] }
        walkMediaTree(root, result: &result, aliases: &aliases)
        IOObjectRelease(root)

        // 别名表收集完成后，统一通过 DiskArbitration 关联卷与物理磁盘
        let physicals = result.map {
            PhysicalSummary(bsd: $0.info.bsdName,
                            size: $0.info.sizeBytes,
                            isExternal: $0.info.isExternal)
        }
        let volumeMap = attachVolumes(physicals: physicals, aliases: aliases)

        let enriched = result.map { raw -> RawDisk in
            let info = raw.info.withVolumes(volumeMap[raw.info.bsdName] ?? [])
            return RawDisk(info: info, bytesRead: raw.bytesRead, bytesWritten: raw.bytesWritten)
        }

        return enriched.sorted { lhs, rhs in
            if lhs.info.isExternal != rhs.info.isExternal {
                return !lhs.info.isExternal
            }
            return diskIndex(lhs.info.bsdName) < diskIndex(rhs.info.bsdName)
        }
    }

    /// 递归遍历 IO 服务树，收集所有 Whole=true 的 IOMedia 整盘
    private static func walkMediaTree(
        _ entry: io_registry_entry_t,
        result: inout [RawDisk],
        aliases: inout [String: String]
    ) {
        var childIter: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &childIter) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(childIter) }

        var child = IOIteratorNext(childIter)
        while child != 0 {
            var released = false
            if let mediaProps = properties(child) {
                let isWhole = (mediaProps["Whole"] as? Bool) == true
                let bsd = mediaProps["BSD Name"] as? String

                if isWhole, let bsd,
                   let size = (mediaProps["Size"] as? NSNumber)?.int64Value,
                   size > 0 {
                    processWholeMedia(
                        entry: child, bsd: bsd, size: size,
                        mediaProps: mediaProps,
                        result: &result, aliases: &aliases)
                    IOObjectRelease(child)
                    released = true
                    // 整盘的子节点是分区，无需继续深入
                    child = IOIteratorNext(childIter)
                    continue
                }
            }

            // 非整盘 IOMedia 或其他节点，继续递归
            walkMediaTree(child, result: &result, aliases: &aliases)
            if !released { IOObjectRelease(child) }
            child = IOIteratorNext(childIter)
        }
    }

    /// 处理一块整盘 IOMedia（与原 while 循环内逻辑一致）
    private static func processWholeMedia(
        entry: io_registry_entry_t, bsd: String, size: Int64,
        mediaProps: [String: Any],
        result: inout [RawDisk], aliases: inout [String: String]
    ) {
        let chain = parentChain(entry)
        let model = resolveModel(mediaProps: mediaProps, chain: chain, bsd: bsd)
        let lowerModel = model.lowercased()

        if lowerModel.contains("disk image") { return }

        let interconnect = detectInterconnect(mediaProps: mediaProps, chain: chain)
        let isPhysical = interconnect != "Unknown"
            || lowerModel.contains("apple") || lowerModel.contains("appl")

        if isPhysical {
            let vendor = firstString(
                mediaProps, chain,
                keys: ["Vendor Name", "USB Vendor Name", "Manufacturer", "Vendor"])
            let serial = firstString(
                mediaProps, chain,
                keys: ["Serial Number", "USB Serial Number", "Serial"])
            let firmware = firstString(
                mediaProps, chain,
                keys: ["Firmware Revision", "Product Revision Level", "Revision"])

            let location = physicalLocation(mediaProps: mediaProps, chain: chain)
            let removable = (mediaProps["Removable"] as? Bool)
                ?? (mediaProps["Ejectable"] as? Bool) ?? false
            let external = location == "External"
                || interconnect == "USB" || interconnect == "Thunderbolt"
                || (removable && location != "Internal")

            let ssd = detectSSD(mediaProps: mediaProps, chain: chain,
                                model: model, interconnect: interconnect)

            let (bytesRead, bytesWritten) = statistics(in: chain)

            let info = DiskInfo(
                bsdName: bsd,
                model: model,
                vendor: vendor?.nonEmpty,
                serial: serial?.nonEmpty,
                firmware: firmware?.nonEmpty,
                sizeBytes: size,
                isRemovable: removable,
                isExternal: external,
                isSSD: ssd,
                interconnect: interconnect,
                volumes: [])
            result.append(RawDisk(info: info,
                                  bytesRead: bytesRead,
                                  bytesWritten: bytesWritten))
        } else if let ancestorBSD = ancestorWholeDisk(chain: chain) {
            aliases[bsd] = ancestorBSD
        }
    }

    private struct PhysicalSummary {
        let bsd: String
        let size: Int64
        let isExternal: Bool
    }

    private struct MountCandidate {
        let volume: VolumeInfo
        let wholeBSD: String
        let wholeSize: Int64?
        let isInternal: Bool
        let isSystemRoot: Bool
    }

    /// 通过 BSD 名称（disk5）快速获取累计 IO 字节数，用于高频采样
    static func counters(bsdName: String) -> (read: Int64, write: Int64)? {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else {
            return nil
        }
        let media = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard media != 0 else { return nil }
        defer { IOObjectRelease(media) }
        let chain = parentChain(media)
        let (r, w) = statistics(in: chain)
        return (r, w)
    }

    // MARK: - IOKit 辅助

    private static func properties(_ entry: io_registry_entry_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return dict
    }

    private static func parentChain(_ entry: io_registry_entry_t) -> [Node] {
        var nodes: [Node] = []
        var current: io_registry_entry_t = entry

        while true {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS
            else { break }

            if let props = properties(parent) {
                nodes.append(Node(name: ioName(parent) ?? "",
                                  className: ioClass(parent) ?? "",
                                  props: props))
            }
            if current != entry { IOObjectRelease(current) }
            current = parent
        }
        if current != entry { IOObjectRelease(current) }
        return nodes
    }

    private static func ioName(_ entry: io_registry_entry_t) -> String? {
        let ptr = UnsafeMutablePointer<CChar>.allocate(capacity: 256)
        defer { ptr.deallocate() }
        let kr = ptr.withMemoryRebound(to: io_name_t.self, capacity: 1) {
            IORegistryEntryGetName(entry, $0)
        }
        return kr == KERN_SUCCESS ? String(cString: ptr) : nil
    }

    private static func ioClass(_ entry: io_registry_entry_t) -> String? {
        let ptr = UnsafeMutablePointer<CChar>.allocate(capacity: 256)
        defer { ptr.deallocate() }
        let kr = ptr.withMemoryRebound(to: io_name_t.self, capacity: 1) {
            IOObjectGetClass(entry, $0)
        }
        return kr == KERN_SUCCESS ? String(cString: ptr) : nil
    }

    private static func statistics(in chain: [Node]) -> (Int64, Int64) {
        // 不同 macOS 版本键名有两种："Bytes (Content) Read" 与 "Bytes (Read)"
        let readKeys = ["Bytes (Content) Read", "Bytes (Read)"]
        let writeKeys = ["Bytes (Content) Written", "Bytes (Write)", "Bytes (Written)"]
        for node in chain {
            if let stats = node.props["Statistics"] as? [String: Any] {
                let read = readKeys.compactMap { (stats[$0] as? NSNumber)?.int64Value }.first
                let written = writeKeys.compactMap { (stats[$0] as? NSNumber)?.int64Value }.first
                if read != nil || written != nil {
                    return (read ?? 0, written ?? 0)
                }
            }
        }
        return (0, 0)
    }

    // MARK: 设备身份解析

    private static func resolveModel(
        mediaProps: [String: Any], chain: [Node], bsd: String
    ) -> String {
        let keys = ["Model", "Product Name", "Device Name", "USB Product Name"]
        if let model = firstString(mediaProps, chain, keys: keys),
           !model.lowercased().hasPrefix("unknown") {
            return model.trimmingCharacters(in: .whitespaces)
        }
        if let chars = deviceCharacteristics(mediaProps: mediaProps, chain: chain),
           let product = chars["Product Name"] as? String, !product.isEmpty {
            return product.trimmingCharacters(in: .whitespaces)
        }
        return "未知磁盘 \(bsd)"
    }

    private static func deviceCharacteristics(
        mediaProps: [String: Any], chain: [Node]
    ) -> [String: Any]? {
        if let d = mediaProps["Device Characteristics"] as? [String: Any] { return d }
        for node in chain {
            if let d = node.props["Device Characteristics"] as? [String: Any] { return d }
        }
        return nil
    }

    private static func physicalLocation(
        mediaProps: [String: Any], chain: [Node]
    ) -> String? {
        if let chars = mediaProps["Protocol Characteristics"] as? [String: Any],
           let loc = chars["Physical Interconnect Location"] as? String {
            return loc
        }
        for node in chain {
            if let chars = node.props["Protocol Characteristics"] as? [String: Any],
               let loc = chars["Physical Interconnect Location"] as? String {
                return loc
            }
        }
        return nil
    }

    /// 在父链中寻找第一块「整盘 IOMedia」，用于把 APFS 合成盘映射回物理磁盘
    private static func ancestorWholeDisk(chain: [Node]) -> String? {
        for node in chain {
            if (node.props["Whole"] as? Bool) == true,
               let bsd = node.props["BSD Name"] as? String {
                return bsd
            }
        }
        return nil
    }

    private static func firstString(
        _ mediaProps: [String: Any], _ chain: [Node], keys: [String]
    ) -> String? {
        for key in keys {
            if let v = mediaProps[key] as? String, !v.isEmpty { return v }
        }
        for node in chain {
            for key in keys {
                if let v = node.props[key] as? String, !v.isEmpty { return v }
            }
            if let chars = node.props["Device Characteristics"] as? [String: Any] {
                for key in keys {
                    if let v = chars[key] as? String, !v.isEmpty { return v }
                }
            }
        }
        return nil
    }

    private static func detectInterconnect(
        mediaProps: [String: Any], chain: [Node]
    ) -> String {
        if let s = interconnect(from: mediaProps) { return s }
        for node in chain {
            if let s = interconnect(from: node.props) { return s }
            let name = node.name.lowercased()
            let cls = node.className.lowercased()
            if name.contains("thunderbolt") || cls.contains("thunderbolt") {
                return "Thunderbolt"
            }
            if name.contains("usb") || cls.contains("usb") {
                return "USB"
            }
            if name.contains("nvme") || cls.contains("nvme")
                || name.contains("appleans") || cls.contains("appleans") {
                return "PCI-Express"
            }
            if name.contains("ahci") || cls.contains("ahci") {
                return "SATA"
            }
        }
        return "Unknown"
    }

    private static func interconnect(from props: [String: Any]) -> String? {
        guard let chars = props["Protocol Characteristics"] as? [String: Any],
              let raw = chars["Physical Interconnect"] as? String
        else { return nil }
        let lower = raw.lowercased()
        if lower.contains("apple fabric") { return "PCI-Express" }
        if lower.contains("pci") { return "PCI-Express" }
        if lower.contains("sata") || lower.contains("s-ata") { return "SATA" }
        if lower.contains("thunderbolt") { return "Thunderbolt" }
        if lower.contains("usb") { return "USB" }
        if lower.contains("ata") { return "SATA" }
        return raw
    }

    private static func detectSSD(
        mediaProps: [String: Any], chain: [Node],
        model: String, interconnect: String
    ) -> Bool {
        if let v = mediaProps["Solid State"] as? Bool { return v }
        for node in chain {
            if let v = node.props["Solid State"] as? Bool { return v }
        }
        if let chars = deviceCharacteristics(mediaProps: mediaProps, chain: chain),
           let medium = chars["Medium Type"] as? String {
            let m = medium.lowercased()
            if m.contains("solid") { return true }
            if m.contains("rotat") || m.contains("hdd") { return false }
        }
        if interconnect == "PCI-Express" { return true }
        let m = model.lowercased()
        let hddKeywords = ["hdd", "hard disk", "harddrive", "barracuda", "ironwolf",
                           "wd blue ", "green ", "5400", "7200"]
        if hddKeywords.contains(where: { m.contains($0) }) { return false }
        return true
    }

    // MARK: - 挂载卷（DiskArbitration）

    private static let wholeDiskRegex = try? NSRegularExpression(pattern: "^disk\\d+")

    private static func wholeDisk(of bsdName: String) -> String? {
        guard let regex = wholeDiskRegex else { return nil }
        let range = NSRange(bsdName.startIndex..., in: bsdName)
        guard let match = regex.firstMatch(in: bsdName, range: range),
              let r = Range(match.range, in: bsdName)
        else { return nil }
        return String(bsdName[r])
    }

    /// 枚举已挂载的用户卷，并按 直接同名 → APFS 别名 → 容量匹配 → 单内置盘兜底 的顺序归属物理磁盘
    private static func attachVolumes(
        physicals: [PhysicalSummary], aliases: [String: String]
    ) -> [String: [VolumeInfo]] {
        guard let session = DASessionCreate(nil),
              let urls = FileManager.default.mountedVolumeURLs(
                  includingResourceValuesForKeys: nil, options: [])
        else { return [:] }

        var candidates: [MountCandidate] = []

        for url in urls {
            let path = url.path
            guard path == "/" || path.hasPrefix("/Volumes/") else { continue }

            guard let daDisk = DADiskCreateFromVolumePath(
                kCFAllocatorDefault, session, url as CFURL)
            else { continue }

            let desc = (DADiskCopyDescription(daDisk) as? [String: Any]) ?? [:]
            let mediaBSD = (desc["DAMediaBSDName"] as? String) ?? ""
            let mediaWhole = (desc["DAMediaWhole"] as? Bool) ?? false
            let internalDisk = (desc["DADeviceInternal"] as? Bool) ?? (path == "/")
            var wholeSize = (desc["DAMediaSize"] as? NSNumber)?.int64Value

            // 取得卷所在的整盘（APFS 合成盘 / 物理盘）及其容量
            var wholeBSD = wholeDisk(of: mediaBSD) ?? mediaBSD
            if !mediaWhole,
               let wholeDA = DADiskCopyWholeDisk(daDisk),
               let wholeDesc = DADiskCopyDescription(wholeDA) as? [String: Any] {
                wholeBSD = (wholeDesc["DAMediaBSDName"] as? String)
                    .flatMap { wholeDisk(of: $0) } ?? wholeBSD
                wholeSize = (wholeDesc["DAMediaSize"] as? NSNumber)?.int64Value ?? wholeSize
            }

            guard let rv = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeNameKey
            ]), let total = rv.volumeTotalCapacity.map(Int64.init),
                  let free = rv.volumeAvailableCapacity.map(Int64.init),
                  total > 0
            else { continue }

            let name = rv.volumeName
                ?? (path == "/" ? "Macintosh HD" : url.lastPathComponent)
            candidates.append(MountCandidate(
                volume: VolumeInfo(name: name, mountPath: path,
                                   totalBytes: total, availableBytes: free),
                wholeBSD: wholeBSD,
                wholeSize: wholeSize,
                isInternal: internalDisk,
                isSystemRoot: path == "/"))
        }

        var map: [String: [VolumeInfo]] = [:]
        for c in candidates {
            guard let target = resolvePhysical(
                wholeBSD: c.wholeBSD, wholeSize: c.wholeSize,
                isInternal: c.isInternal, isSystemRoot: c.isSystemRoot,
                physicals: physicals, aliases: aliases)
            else { continue }
            map[target, default: []].append(c.volume)
        }
        for key in map.keys {
            map[key]?.sort { $0.mountPath < $1.mountPath }
        }
        return map
    }

    private static func resolvePhysical(
        wholeBSD: String, wholeSize: Int64?, isInternal: Bool,
        isSystemRoot: Bool,
        physicals: [PhysicalSummary], aliases: [String: String]
    ) -> String? {
        // 1. 整盘 BSD 名与物理盘同名（USB / 雷雳盘以及未合成的内置盘）
        if physicals.contains(where: { $0.bsd == wholeBSD }) {
            return wholeBSD
        }
        // 2. APFS 合成盘别名
        if let alias = aliases[wholeBSD],
           physicals.contains(where: { $0.bsd == alias }) {
            return alias
        }
        let wantExternal = !isInternal
        let sameClass = physicals.filter { $0.isExternal == wantExternal }

        // 3. 容量匹配：APFS 容器占整盘 85%~102%
        if let size = wholeSize, size > 0 {
            let sized = sameClass.filter {
                Double(size) >= Double($0.size) * 0.85
                && Double(size) <= Double($0.size) * 1.02
            }
            if sized.count == 1 { return sized[0].bsd }
        }
        // 4. 系统根卷：归属第一块内置物理盘（含虚拟化 / 叠加层将系统盘标记为外置的场景）
        if isSystemRoot {
            return physicals.filter { !$0.isExternal }
                .sorted { diskIndex($0.bsd) < diskIndex($1.bsd) }
                .first?.bsd
        }
        // 5. 其它内置卷且只有一块内置物理盘
        if isInternal {
            let internals = physicals.filter { !$0.isExternal }
            if internals.count == 1 { return internals[0].bsd }
        }
        return nil
    }

    private static func diskIndex(_ bsdName: String) -> Int {
        Int(bsdName.replacingOccurrences(of: "disk", with: "")) ?? Int.max
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

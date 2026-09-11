import Foundation

/// 轻量顺序读写测速：在所选卷上写入一个临时文件并读回，
/// 模拟三星魔术师 Performance Benchmark 的顺序吞吐测试。
enum Benchmark {

    private static let blockBytes = 4 * 1024 * 1024 // 4 MiB

    /// - Parameters:
    ///   - volume: 卷挂载路径 URL
    ///   - sizeMB: 测试大小（MB）
    ///   - progress: 0...1 进度回调
    static func run(
        volume: URL,
        sizeMB: Int,
        progress: @escaping (Double, String) -> Void
    ) async throws -> BenchmarkResult {
        let fileURL = volume.appendingPathComponent(
            ".driveprotector-bench-\(UUID().uuidString).tmp")
        let totalBytes = sizeMB * 1_000_000
        let blockCount = max(1, totalBytes / blockBytes)
        var block = Data(count: blockBytes)
        // 填充可压缩度较低的数据，避免缓存层优化失真
        for i in 0..<blockBytes {
            block[i] = UInt8((i &* 31 &+ 17) & 0xFF)
        }

        // MARK: 写入
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let writeStart = Date()
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }

        do {
            for i in 0..<blockCount {
                try handle.write(contentsOf: block)
                if i % 8 == 0 {
                    let p = Double(i) / Double(blockCount) * 0.5
                    progress(p, "正在顺序写入… \(Int(p * 100))%")
                    try await Task.sleep(nanoseconds: 1_000_000) // 让进度回调有机会刷新
                }
            }
            try handle.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
        let writeSeconds = Date().timeIntervalSince(writeStart)
        let writtenBytes = blockCount * blockBytes
        let writeMBps = Double(writtenBytes) / 1_000_000 / max(0.001, writeSeconds)
        progress(0.5, "写入完成，准备读取…")

        // MARK: 读取
        let readHandle: FileHandle
        do {
            readHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
        var checksum: UInt64 = 0
        let readStart = Date()
        do {
            for i in 0..<blockCount {
                let data = try readHandle.read(upToCount: blockBytes) ?? Data()
                checksum = checksum &+ UInt64(data.count)
                if !data.isEmpty {
                    checksum = checksum &+ UInt64(data[data.count / 2])
                }
                if i % 8 == 0 {
                    let p = 0.5 + Double(i) / Double(blockCount) * 0.5
                    progress(p, "正在顺序读取… \(Int(p * 100))%")
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
            }
        } catch {
            try? readHandle.close()
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
        let readSeconds = Date().timeIntervalSince(readStart)
        try? readHandle.close()
        try? FileManager.default.removeItem(at: fileURL)

        let readBytes = blockCount * blockBytes
        let readMBps = Double(readBytes) / 1_000_000 / max(0.001, readSeconds)
        progress(1, "测试完成（校验和 \(checksum)）")

        return BenchmarkResult(readMBps: readMBps, writeMBps: writeMBps, sizeMB: sizeMB)
    }
}

import Foundation
import SwiftUI

/// 全局监控状态中心：定时枚举磁盘、采样 IO 吞吐、刷新 SMART 报告、执行测速
@MainActor
final class MonitorStore: ObservableObject {

    @Published var disks: [DiskInfo] = []
    @Published var selectedBSD: String?
    @Published var reports: [String: SMARTReport] = [:]
    @Published var throughput: [String: Throughput] = [:]
    @Published var samples: [String: [ThroughputSample]] = [:]
    @Published var lastUpdated: Date = .now
    @Published var isRefreshingSMART = false
    @Published var benchmark = BenchmarkState()

    let smartctlInstalled = SMARTProvider.smartctlPath != nil

    private var counters: [String: (read: Int64, write: Int64, date: Date)] = [:]
    private var tickCount: UInt64 = 0
    private var timer: Timer?
    private var inflightSmart = Set<String>()
    private var lastSmartLoad: [String: Date] = [:]

    // MARK: 生命周期

    func start() {
        guard timer == nil else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func select(_ bsd: String) {
        selectedBSD = bsd
    }

    var selectedDisk: DiskInfo? {
        disks.first { $0.bsdName == selectedBSD } ?? disks.first
    }

    func report(for bsd: String) -> SMARTReport? { reports[bsd] }
    func throughput(for bsd: String) -> Throughput {
        throughput[bsd] ?? Throughput(readBytesPerSec: 0, writeBytesPerSec: 0)
    }

    func peakReadMBps(for bsd: String) -> Double {
        samples[bsd]?.map(\.readMBps).max() ?? 0
    }
    func peakWriteMBps(for bsd: String) -> Double {
        samples[bsd]?.map(\.writeMBps).max() ?? 0
    }
    func averageReadMBps(for bsd: String) -> Double {
        guard let s = samples[bsd], !s.isEmpty else { return 0 }
        return s.map(\.readMBps).reduce(0, +) / Double(s.count)
    }
    func averageWriteMBps(for bsd: String) -> Double {
        guard let s = samples[bsd], !s.isEmpty else { return 0 }
        return s.map(\.writeMBps).reduce(0, +) / Double(s.count)
    }

    // MARK: 手动刷新

    func manualRefresh() {
        tick()
        if smartctlInstalled, let disk = selectedDisk {
            loadSMART(disk, force: true)
        }
    }

    // MARK: 定时采样

    private func tick() {
        tickCount &+= 1
        let raws = IOKitDisk.enumerate()
        let infos = raws.map(\.info)
        if infos != disks {
            disks = infos
        }

        let now = Date()
        let active = Set(infos.map(\.id))

        for raw in raws {
            let bsd = raw.info.bsdName
            if let prev = counters[bsd] {
                let dt = now.timeIntervalSince(prev.date)
                if dt > 0.05 {
                    let dr = max(0, raw.bytesRead - prev.read)
                    let dw = max(0, raw.bytesWritten - prev.write)
                    let current = Throughput(
                        readBytesPerSec: Double(dr) / dt,
                        writeBytesPerSec: Double(dw) / dt)
                    throughput[bsd] = current

                    var arr = samples[bsd] ?? []
                    arr.append(ThroughputSample(
                        date: now,
                        readMBps: current.readBytesPerSec / 1_000_000,
                        writeMBps: current.writeBytesPerSec / 1_000_000))
                    if arr.count > 60 { arr.removeFirst(arr.count - 60) }
                    samples[bsd] = arr
                }
            }
            counters[bsd] = (raw.bytesRead, raw.bytesWritten, now)
        }

        for key in counters.keys where !active.contains(key) {
            counters[key] = nil
            throughput[key] = nil
            samples[key] = nil
            reports[key] = nil
        }

        if let selected = selectedBSD, !active.contains(selected) {
            selectedBSD = infos.first?.bsdName
        } else if selectedBSD == nil {
            selectedBSD = infos.first?.bsdName
        }

        lastUpdated = now

        // SMART 刷新
        if smartctlInstalled {
            for info in infos where reports[info.bsdName] == nil || tickCount % 20 == 0 {
                loadSMART(info, force: false)
            }
        } else if tickCount % 3 == 0 {
            // 演示数据：跟随实时负载刷新温度
            for info in infos {
                let t = throughput(for: info.bsdName)
                reports[info.bsdName] = DemoData.report(
                    for: info,
                    readMBps: t.readBytesPerSec / 1_000_000,
                    writeMBps: t.writeBytesPerSec / 1_000_000)
            }
        }
    }

    private func loadSMART(_ disk: DiskInfo, force: Bool) {
        guard !inflightSmart.contains(disk.bsdName) else { return }
        if !force, let last = lastSmartLoad[disk.bsdName],
           Date().timeIntervalSince(last) < 40 {
            return
        }
        inflightSmart.insert(disk.bsdName)
        isRefreshingSMART = true

        let current = throughput(for: disk.bsdName)
        let readMBps = current.readBytesPerSec / 1_000_000
        let writeMBps = current.writeBytesPerSec / 1_000_000

        Task.detached { [weak self] in
            let report = SMARTProvider.load(
                for: disk, readMBps: readMBps, writeMBps: writeMBps)
            guard let self else { return }
            await self.handleSMARTResult(report, bsd: disk.bsdName)
        }
    }

    private func handleSMARTResult(_ report: SMARTReport, bsd: String) {
        reports[bsd] = report
        lastSmartLoad[bsd] = .now
        inflightSmart.remove(bsd)
        isRefreshingSMART = !inflightSmart.isEmpty
    }

    // MARK: 测速

    func runBenchmark(volumePath: String, sizeMB: Int) {
        guard !benchmark.running else { return }
        benchmark = BenchmarkState(running: true, progress: 0, phase: "准备测试…")
        let url = URL(fileURLWithPath: volumePath)

        Task.detached { [weak self] in
            do {
                let result = try await Benchmark.run(volume: url, sizeMB: sizeMB) { prog, phase in
                    Task { @MainActor [weak self] in
                        self?.benchmark.progress = prog
                        self?.benchmark.phase = phase
                    }
                }
                guard let self else { return }
                await self.handleBenchmarkFinished(result)
            } catch {
                guard let self else { return }
                await self.handleBenchmarkFailed(error)
            }
        }
    }

    private func handleBenchmarkFinished(_ result: BenchmarkResult) {
        benchmark.running = false
        benchmark.progress = 1
        benchmark.phase = "测试完成"
        benchmark.result = result
        benchmark.error = nil
    }

    private func handleBenchmarkFailed(_ error: Error) {
        benchmark.running = false
        benchmark.phase = "测试失败"
        benchmark.error = error.localizedDescription
    }

    func clearBenchmark() {
        benchmark = BenchmarkState()
    }
}

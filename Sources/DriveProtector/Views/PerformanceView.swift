import SwiftUI

struct PerformanceView: View {
    @ObservedObject var store: MonitorStore
    let disk: DiskInfo

    @State private var volumePath: String?
    @State private var sizeMB = 256

    private var samples: [ThroughputSample] { store.samples[disk.bsdName] ?? [] }

    private var chartScale: Double {
        let peak = max(store.peakReadMBps(for: disk.bsdName),
                       store.peakWriteMBps(for: disk.bsdName))
        return max(50, peak * 1.25, disk.profile.maxReadMBps * 0.12)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                liveCard
                benchmarkCard
                specCard
            }
            .padding(24)
        }
    }

    // MARK: 实时曲线卡

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeader(title: "实时读写吞吐",
                              subtitle: "过去 90 秒采样（每 1.5 秒）",
                              icon: "waveform.path.ecg")
                Spacer()
                legendDot(color: Theme.cyan, text: "读取")
                legendDot(color: Theme.purple, text: "写入")
            }

            ThroughputChart(samples: samples, scaleMaxMBps: chartScale)
                .frame(height: 230)

            HStack(spacing: 12) {
                metricTile(title: "当前读取",
                           value: Fmt.speed(store.throughput(for: disk.bsdName).readBytesPerSec),
                           color: Theme.cyan)
                metricTile(title: "当前写入",
                           value: Fmt.speed(store.throughput(for: disk.bsdName).writeBytesPerSec),
                           color: Theme.purple)
                metricTile(title: "读取峰值",
                           value: String(format: "%.0f MB/s", store.peakReadMBps(for: disk.bsdName)),
                           color: Theme.green)
                metricTile(title: "写入峰值",
                           value: String(format: "%.0f MB/s", store.peakWriteMBps(for: disk.bsdName)),
                           color: Theme.amber)
                metricTile(title: "平均读取",
                           value: String(format: "%.0f MB/s", store.averageReadMBps(for: disk.bsdName)),
                           color: Theme.blue)
            }
        }
        .padding(18)
        .cardStyle()
    }

    private func metricTile(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.white.opacity(0.03)))
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: 测速卡

    private var benchmarkCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "顺序性能测试",
                          subtitle: "在所选卷上写入临时文件并读回，测试结束自动删除",
                          icon: "speedometer")

            HStack(spacing: 14) {
                Picker("", selection: volumeBinding) {
                    if disk.volumes.isEmpty {
                        Text("无可用卷").tag(String?.none)
                    }
                    ForEach(disk.volumes, id: \.mountPath) { v in
                        Text("\(v.name)（\(v.mountPath)）").tag(String?.some(v.mountPath))
                    }
                }
                .labelsHidden()
                .frame(width: 300)

                Picker("", selection: $sizeMB) {
                    Text("128 MB").tag(128)
                    Text("256 MB").tag(256)
                    Text("512 MB").tag(512)
                    Text("1 GB").tag(1024)
                }
                .labelsHidden()
                .frame(width: 110)

                Button {
                    if let path = volumePath ?? disk.volumes.first?.mountPath {
                        store.clearBenchmark()
                        store.runBenchmark(volumePath: path, sizeMB: sizeMB)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: store.benchmark.running ? "stop.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(store.benchmark.running ? "测试中…" : "开始测速")
                            .font(.system(size: 12.5, weight: .bold))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    Capsule().fill(store.benchmark.running
                                   ? AnyShapeStyle(Theme.red)
                                   : AnyShapeStyle(Theme.cyanGradient)))
                .disabled(store.benchmark.running || (volumePath ?? disk.volumes.first?.mountPath) == nil)
                .opacity((store.benchmark.running || (volumePath ?? disk.volumes.first?.mountPath) != nil) ? 1 : 0.45)

                Spacer()
            }

            if disk.volumes.isEmpty {
                Label("该磁盘当前没有挂载可读写的卷，无法执行测速。请先在系统中挂载磁盘。",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.amber)
            }

            if store.benchmark.running || store.benchmark.progress > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(store.benchmark.phase)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(String(format: "%.0f%%", store.benchmark.progress * 100))
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.cyan)
                    }
                    CapacityBar(fraction: store.benchmark.progress, height: 8)
                }
            }

            if let error = store.benchmark.error {
                Label("测试失败：\(error)", systemImage: "xmark.circle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.red)
            }

            if let result = store.benchmark.result, !store.benchmark.running {
                HStack(spacing: 14) {
                    benchResultTile(title: "顺序读取",
                                    mbps: result.readMBps,
                                    maxMBps: disk.profile.maxReadMBps,
                                    gradient: Theme.cyanGradient)
                    benchResultTile(title: "顺序写入",
                                    mbps: result.writeMBps,
                                    maxMBps: disk.profile.maxWriteMBps,
                                    gradient: Theme.purpleGradient)
                }
            }
        }
        .padding(18)
        .cardStyle()
        .onAppear {
            if volumePath == nil {
                volumePath = disk.volumes.first?.mountPath
            }
        }
        .onChange(of: disk.bsdName) { _ in
            volumePath = disk.volumes.first?.mountPath
        }
    }

    private var volumeBinding: Binding<String?> {
        Binding(
            get: { volumePath ?? disk.volumes.first?.mountPath },
            set: { volumePath = $0 })
    }

    private func benchResultTile(title: String, mbps: Double, maxMBps: Double,
                                 gradient: LinearGradient) -> some View {
        let ratio = min(1, mbps / max(1, maxMBps))
        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.0f", mbps))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("MB/s")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(String(format: "达到厂商标称 %.0f%%", ratio * 100))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ratio >= 0.7 ? Theme.green : Theme.amber)
            }
            CapacityBar(fraction: ratio, height: 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Color.white.opacity(0.03)))
    }

    // MARK: 厂商标称

    private var specCard: some View {
        let p = disk.profile
        return HStack(spacing: 0) {
            specColumn(title: "厂商标称顺序读取",
                       value: "\(String(format: "%.0f", p.maxReadMBps)) MB/s",
                       icon: "arrow.down.circle.fill", tint: Theme.cyan)
            divider
            specColumn(title: "厂商标称顺序写入",
                       value: "\(String(format: "%.0f", p.maxWriteMBps)) MB/s",
                       icon: "arrow.up.circle.fill", tint: Theme.purple)
            divider
            specColumn(title: "接口",
                       value: p.interface,
                       icon: "cable.connector", tint: Theme.green)
            divider
            specColumn(title: "质保 TBW",
                       value: p.tbwTB.map { "\($0) TB" } ?? "未提供",
                       icon: "shield.fill", tint: Theme.amber)
        }
        .padding(.vertical, 16)
        .cardStyle()
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(width: 1)
    }

    private func specColumn(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
    }
}

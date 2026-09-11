import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: MonitorStore
    let disk: DiskInfo

    private var report: SMARTReport? { store.report(for: disk.bsdName) }
    private var throughput: Throughput { store.throughput(for: disk.bsdName) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topRow
                alertBanner
                statsGrid
            }
            .padding(24)
        }
    }

    // MARK: 顶部主卡行

    private var topRow: some View {
        HStack(alignment: .top, spacing: 18) {
            driveCard
                .frame(width: 392)

            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    SpeedCard(
                        title: "顺序读取",
                        icon: "arrow.down",
                        bytesPerSec: throughput.readBytesPerSec,
                        peakMBps: store.peakReadMBps(for: disk.bsdName),
                        maxScaleMBps: disk.profile.maxReadMBps,
                        gradient: Theme.cyanGradient)
                    SpeedCard(
                        title: "顺序写入",
                        icon: "arrow.up",
                        bytesPerSec: throughput.writeBytesPerSec,
                        peakMBps: store.peakWriteMBps(for: disk.bsdName),
                        maxScaleMBps: disk.profile.maxWriteMBps,
                        gradient: Theme.purpleGradient)
                }
                temperatureCard
            }
        }
    }

    // MARK: 磁盘主卡

    private var driveCard: some View {
        let p = disk.profile
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: disk.isExternal
                                ? [Color(hex: 0xB18BFF), Color(hex: 0x5A3BE0)]
                                : [Color(hex: 0x36C9F2), Color(hex: 0x2B5FF0)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: disk.iconName)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
                .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: 5) {
                    Text(disk.model)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text(p.productLine)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 5) {
                        Chip(text: disk.isExternal ? "外接磁盘" : "内置磁盘",
                             color: disk.isExternal ? Theme.purple : Theme.cyan,
                             icon: disk.isExternal ? "cable.connector" : "macbook")
                        Chip(text: disk.isSSD ? "SSD" : "HDD",
                             color: Theme.green, icon: "bolt.fill")
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            // 容量
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("已用容量")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(Fmt.capacity(disk.usedCapacity)) / \(Fmt.capacity(disk.totalCapacity))")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
                CapacityBar(fraction: disk.usedFraction, height: 9)
                HStack {
                    Text("可用 \(Fmt.capacity(disk.availableCapacity))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Text(String(format: "%.1f%% 已用", disk.usedFraction * 100))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.cyan)
                }
            }

            Rectangle().fill(Theme.stroke).frame(height: 1)

            // 健康环 + 寿命信息
            HStack(spacing: 18) {
                HealthRing(percent: report?.healthPercent ?? 100, size: 118, lineWidth: 10)
                VStack(alignment: .leading, spacing: 9) {
                    infoRow("厂商规格",
                            "\(String(format: "%.0f", p.maxReadMBps)) / \(String(format: "%.0f", p.maxWriteMBps)) MB/s")
                    infoRow("通电时间",
                            Fmt.hours(report?.powerOnHours))
                    infoRow("总写入量",
                            report?.bytesWritten.map { Fmt.tb($0) } ?? "—")
                    infoRow("固件版本",
                            disk.firmware ?? "—")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .cardStyle()
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: 温度卡

    private var temperatureCard: some View {
        let t = report?.temperatureC
        let color = temperatureColor(t)
        let statusText: String = {
            guard let t else { return "暂无数据" }
            if t >= 70 { return "过热告警 · 请加强散热" }
            if t >= 55 { return "温度偏高" }
            return "温度正常"
        }()
        return HStack(spacing: 20) {
            TempDial(temperature: t)
                .frame(width: 132, height: 132)

            VStack(alignment: .leading, spacing: 10) {
                Text("磁盘温度")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .shadow(color: color.opacity(0.8), radius: 4)
                    Text(statusText)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(color)
                }
                Spacer().frame(height: 2)
                thresholdRow("正常区间", "< 50°C", color: Theme.green)
                thresholdRow("注意区间", "50 – 70°C", color: Theme.amber)
                thresholdRow("过热告警", "≥ 70°C", color: Theme.red)
                Spacer()
                Text(report?.source.rawValue ?? "")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(18)
        .cardStyle()
    }

    private func thresholdRow(_ title: String, _ range: String, color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 14, height: 4)
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(range)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(width: 190)
    }

    // MARK: 告警横幅

    @ViewBuilder
    private var alertBanner: some View {
        let t = report?.temperatureC ?? 0
        let h = report?.healthPercent ?? 100
        if t >= 70 {
            banner(icon: "exclamationmark.triangle.fill",
                   title: "磁盘温度过高（\(String(format: "%.1f", t))°C）",
                   message: "持续高温会加速 NAND 老化，建议改善散热并避免大负载连续写入。",
                   color: Theme.red)
        } else if h < 60 {
            banner(icon: "exclamationmark.triangle.fill",
                   title: "磁盘健康度偏低（\(Int(h))%）",
                   message: "建议尽快备份重要数据，并关注 SMART 属性中的坏块与磨损指标。",
                   color: Theme.amber)
        } else if report?.source == .demo {
            banner(icon: "info.circle.fill",
                   title: "当前为演示数据",
                   message: "macOS 不向第三方应用直接开放完整 SMART。安装 smartmontools（brew install smartmontools）后将自动读取真实 SMART，支持外接 USB / 雷雳硬盘。",
                   color: Theme.cyan)
        } else {
            banner(icon: "checkmark.seal.fill",
                   title: "磁盘运行状态良好",
                   message: "实时监测运行中：温度、读写吞吐与 SMART 健康状态持续更新。",
                   color: Theme.green)
        }
    }

    private func banner(icon: String, title: String, message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(Circle().fill(color.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: 指标网格

    private var statsGrid: some View {
        let r = report
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                         spacing: 12) {
            StatTile(icon: "checkmark.shield.fill",
                     title: "SMART 总评",
                     value: (r?.overallPassed ?? true) ? "评估通过" : "未通过",
                     tint: Theme.green,
                     warning: r?.overallPassed == false)
            StatTile(icon: "clock.fill",
                     title: "通电时间",
                     value: Fmt.hours(r?.powerOnHours),
                     tint: Theme.cyan)
            StatTile(icon: "power.fill",
                     title: "通电次数",
                     value: Fmt.number(r?.powerCycles),
                     tint: Theme.blue)
            StatTile(icon: "arrow.down.circle.fill",
                     title: "历史总读取",
                     value: r?.bytesRead.map { Fmt.tb($0) } ?? "—",
                     tint: Theme.cyan)
            StatTile(icon: "arrow.up.circle.fill",
                     title: "历史总写入",
                     value: r?.bytesWritten.map { Fmt.tb($0) } ?? "—",
                     tint: Theme.purple)
            StatTile(icon: "bolt.horizontal.circle.fill",
                     title: "非正常断电",
                     value: Fmt.number(r?.unsafeShutdowns),
                     tint: Theme.amber,
                     warning: (r?.unsafeShutdowns ?? 0) > 10)
            StatTile(icon: "xmark.octagon.fill",
                     title: "介质错误",
                     value: Fmt.number(r?.mediaErrors),
                     tint: Theme.red,
                     warning: (r?.mediaErrors ?? 0) > 0)
            StatTile(icon: "speedometer",
                     title: "标称顺序读",
                     value: "\(String(format: "%.0f", disk.profile.maxReadMBps)) MB/s",
                     tint: Theme.green)
        }
    }
}

import SwiftUI
import AppKit

// MARK: - 菜单栏挂件入口
struct DriveProtectorMenuBarExtra: Scene {
    @ObservedObject var store: MonitorStore

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - 菜单栏图标 + 紧凑温度
private struct MenuBarLabel: View {
    @ObservedObject var store: MonitorStore

    private var hottestTemp: Double? {
        store.disks.compactMap { store.reports[$0.bsdName]?.temperatureC }.max()
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.cyan)
            if let t = hottestTemp {
                Text(String(format: "%.0f°", t))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tempColor(t))
            }
        }
    }

    private func tempColor(_ t: Double) -> Color {
        if t >= 70 { return Color.red }
        if t >= 55 { return Color.orange }
        return Theme.textPrimary
    }
}

// MARK: - 下拉面板
private struct MenuBarPanel: View {
    @ObservedObject var store: MonitorStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Theme.stroke)
            if store.disks.isEmpty {
                emptyState
            } else {
                diskList
            }
            Divider().background(Theme.stroke)
            footer
        }
        .frame(width: 360)
        .padding(.vertical, 10)
        .background(Theme.sidebar)
    }

    private var header: some View {
        HStack {
            Text("磁盘状态")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if store.smartctlInstalled {
                Text("实时 SMART")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.cyan)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.cyan.opacity(0.12))
                    .clipShape(Capsule())
            } else {
                Text("演示数据")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.amber.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textTertiary)
            Text("未检测到磁盘")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var diskList: some View {
        VStack(spacing: 2) {
            ForEach(store.disks) { disk in
                DiskRow(
                    disk: disk,
                    report: store.reports[disk.bsdName],
                    throughput: store.throughput(for: disk.bsdName)
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11))
                    Text("打开主窗口")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("更新于 \(store.lastUpdated, style: .time)")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}

// MARK: - 单块磁盘行
private struct DiskRow: View {
    let disk: DiskInfo
    let report: SMARTReport?
    let throughput: Throughput

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 左侧：磁盘标识
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: disk.isExternal ? "externaldrive.fill" : "internaldrive.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(disk.isExternal ? Theme.cyan : Theme.green)
                    Text(disk.model)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                Text("\(disk.bsdName) · \(Fmt.capacity(disk.sizeBytes))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            // 右侧：温度 + 读写
            VStack(alignment: .trailing, spacing: 3) {
                if let t = report?.temperatureC {
                    HStack(spacing: 3) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 10))
                            .foregroundStyle(tempColor(t))
                        Text(String(format: "%.0f°C", t))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(tempColor(t))
                    }
                } else {
                    Text("— °C")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }

                HStack(spacing: 6) {
                    speedChip(icon: "arrow.down.circle.fill", value: throughput.readBytesPerSec, tint: Theme.cyan)
                    speedChip(icon: "arrow.up.circle.fill", value: throughput.writeBytesPerSec, tint: Theme.green)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func speedChip(icon: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(tint)
            Text(Fmt.speed(value))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func tempColor(_ t: Double) -> Color {
        if t >= 70 { return Color.red }
        if t >= 55 { return Color.orange }
        if t >= 45 { return Theme.amber }
        return Theme.green
    }
}

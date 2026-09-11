import SwiftUI
import AppKit

enum MainTab: String, CaseIterable, Identifiable {
    case dashboard
    case smart
    case performance
    case detail

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "仪表盘"
        case .smart: return "SMART 信息"
        case .performance: return "性能监测"
        case .detail: return "详细信息"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .smart: return "list.clipboard"
        case .performance: return "waveform.path.ecg"
        case .detail: return "info.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: MonitorStore
    @State private var tab: MainTab = .dashboard

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(store: store)
                .frame(width: 272)
            Rectangle()
                .fill(Theme.stroke)
                .frame(width: 1)

            VStack(spacing: 0) {
                topBar
                Rectangle()
                    .fill(Theme.stroke)
                    .frame(height: 1)

                ZStack {
                    Theme.background
                    if let disk = store.selectedDisk {
                        Group {
                            switch tab {
                            case .dashboard:
                                DashboardView(store: store, disk: disk)
                            case .smart:
                                SMARTView(store: store, disk: disk)
                            case .performance:
                                PerformanceView(store: store, disk: disk)
                            case .detail:
                                DetailView(store: store, disk: disk)
                            }
                        }
                        .id(disk.bsdName)
                        .transition(.opacity)
                    } else {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.large)
                            Text("正在枚举磁盘设备…")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            store.start()
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .onDisappear { store.stop() }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.selectedDisk?.model ?? "Drive Protector")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let disk = store.selectedDisk {
                    HStack(spacing: 6) {
                        Text(disk.profile.productLine)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                        Circle()
                            .fill(Theme.textTertiary)
                            .frame(width: 3, height: 3)
                        Text("\(disk.devicePath)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            Spacer()

            HStack(spacing: 4) {
                ForEach(MainTab.allCases) { t in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { tab = t }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: t.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(t.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundStyle(tab == t ? .white : Theme.textSecondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if tab == t {
                                    Theme.cyanGradient
                                } else {
                                    Color.white.opacity(0.05)
                                }
                            }
                            .clipShape(Capsule(style: .continuous))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Theme.sidebar.opacity(0.4))
    }
}

// MARK: - 侧边栏

private struct Sidebar: View {
    @ObservedObject var store: MonitorStore

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("已连接磁盘 · \(store.disks.count)")
                        .sectionLabel()
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)

                    ForEach(store.disks) { disk in
                        DriveRow(disk: disk,
                                 selected: disk.bsdName == store.selectedBSD,
                                 store: store)
                    }
                }
                .padding(.horizontal, 12)
            }

            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 1)
            footer
                .padding(16)
        }
        .background(Theme.sidebar.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.cyanGradient)
                Image(systemName: "internaldrive.fill.badge.checkmark")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            .shadow(color: Theme.cyan.opacity(0.35), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Drive Protector")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("磁盘安全守护")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(store.smartctlInstalled ? Theme.green : Theme.amber)
                    .frame(width: 7, height: 7)
                Text(store.smartctlInstalled
                     ? "smartctl 已就绪 · 真实 SMART"
                     : "演示模式 · 未检测到 smartctl")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button {
                    store.manualRefresh()
                } label: {
                    Label("立即刷新", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                        .foregroundStyle(Theme.textPrimary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(store.lastUpdated.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

// MARK: - 磁盘行

private struct DriveRow: View {
    let disk: DiskInfo
    let selected: Bool
    @ObservedObject var store: MonitorStore

    var body: some View {
        let report = store.report(for: disk.bsdName)
        Button {
            store.select(disk.bsdName)
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected
                              ? AnyShapeStyle(Theme.cyanGradient)
                              : AnyShapeStyle(Color.white.opacity(0.07)))
                    Image(systemName: disk.iconName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(disk.model)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if disk.isExternal {
                            Image(systemName: "cable.connector")
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.purple)
                        }
                    }
                    Text("\(disk.interconnect) · \(Fmt.capacity(disk.sizeBytes))")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                    CapacityBar(fraction: disk.usedFraction, height: 4)
                        .frame(width: 150)
                }
                Spacer(minLength: 0)

                if let t = report?.temperatureC {
                    Text("\(Int(t))°")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(temperatureColor(t))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected ? Theme.cyan.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(selected ? Theme.cyan.opacity(0.5) : Color.clear,
                                  lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

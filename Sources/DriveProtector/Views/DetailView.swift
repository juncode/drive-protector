import SwiftUI
import AppKit

struct DetailView: View {
    @ObservedObject var store: MonitorStore
    let disk: DiskInfo

    @State private var copied = false

    private var report: SMARTReport? { store.report(for: disk.bsdName) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    deviceCard
                    vendorCard
                }
                smartSourceCard
                featuresCard
            }
            .padding(24)
        }
    }

    // MARK: 设备信息

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "设备信息",
                          subtitle: "来自 IOKit / DiskArbitration 的实时枚举",
                          icon: "internaldrive")
                .padding(.vertical, 18)

            row("设备节点", disk.devicePath, mono: true)
            row("型号名称", disk.model)
            row("供应商", disk.vendor ?? disk.profile.vendor)
            row("序列号", disk.serial ?? "—", mono: true)
            row("固件版本", disk.firmware ?? "—", mono: true)
            row("总线协议", disk.interconnect)
            row("介质类型", disk.isSSD ? "固态硬盘 (SSD)" : "机械硬盘 (HDD)")
            row("安装方式", disk.isExternal ? "外接（热插拔）" : "内置")
            row("可弹出", disk.isRemovable ? "是" : "否")
            row("物理容量", Fmt.capacity(disk.sizeBytes))
            row("挂载卷", disk.volumes.isEmpty ? "未挂载" : disk.volumes.map(\.name).joined(separator: "、"))
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func row(_ title: String, _ value: String, mono: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(value)
                    .font(.system(size: 12,
                                  weight: .semibold,
                                  design: mono ? .monospaced : .default))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
            .padding(.vertical, 10)
            Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
        }
    }

    // MARK: 厂商规格

    private var vendorCard: some View {
        let p = disk.profile
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "厂商规格档案",
                          subtitle: "依据型号识别结果匹配",
                          icon: "shippingbox")
                .padding(.vertical, 18)

            specRow("品牌", p.vendor)
            specRow("产品系列", p.productLine)
            specRow("接口", p.interface)
            specRow("外形规格", p.formFactor)
            specRow("顺序读取", "\(String(format: "%.0f", p.maxReadMBps)) MB/s")
            specRow("顺序写入", "\(String(format: "%.0f", p.maxWriteMBps)) MB/s")
            specRow("质保", p.warrantyYears > 0 ? "\(p.warrantyYears) 年" : "—")
            specRow("额定 TBW", p.tbwTB.map { "\($0) TB" } ?? "未公开")
            specRow("形态", p.isExternal ? "移动便携 SSD" : (p.isNVMe ? "NVMe SSD" : "SATA SSD"))

            VStack(alignment: .leading, spacing: 8) {
                Text("主要特性")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                FlowChips(items: p.features)
            }
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func specRow(_ title: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.vertical, 10)
            Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
        }
    }

    // MARK: SMART 数据源

    private var smartSourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "SMART 数据来源", icon: "sensor.tag.radiowaves.forward")

            if report?.source == .smartctl {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.green)
                    Text("当前通过 smartctl 实时读取设备 SMART（设备节点 \(disk.devicePath)），支持内置 NVMe、SATA 以及具备 SAT 透传的 USB / 雷雳外接硬盘（含 D1 SSD PRO 等移动固态）。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.bubble.fill")
                            .foregroundStyle(Theme.amber)
                        Text("当前显示演示数据。macOS 出于安全限制不向第三方应用直接开放完整 SMART 属性；安装开源 smartmontools 后，本应用会自动调用 smartctl 读取真实数据，无需更改任何设置。")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Text("brew install smartmontools")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.cyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05)))
                        Button {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString("brew install smartmontools", forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copied = false
                            }
                        } label: {
                            Label(copied ? "已复制" : "复制命令",
                                  systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Theme.cyanGradient))
                        Spacer()
                    }
                }
            }
        }
        .padding(18)
        .cardStyle()
    }

    // MARK: 特性

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "守护能力", subtitle: "本设备当前可监测的项目",
                          icon: "shield.lefthalf.filled")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                      spacing: 10) {
                capability(icon: "thermometer.medium", title: "温度监测",
                           detail: "实时温度与过热告警")
                capability(icon: "waveform", title: "读写速率",
                           detail: "实时吞吐与 90 秒曲线")
                capability(icon: "list.clipboard", title: "SMART 属性",
                           detail: report?.source == .smartctl ? "真实属性读取" : "演示数据展示")
                capability(icon: "speedometer", title: "顺序测速",
                           detail: "卷级读写基准测试")
                capability(icon: "externaldrive", title: "外接盘支持",
                           detail: "USB / 雷雳移动固态")
                capability(icon: "bell.badge", title: "安全提醒",
                           detail: "高温 / 寿命 / 错误计数告警")
            }
        }
        .padding(18)
        .cardStyle()
    }

    private func capability(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.cyan.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.025)))
    }
}

// MARK: - 简单换行布局

private struct FlowChips: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Chip(text: item)
            }
        }
    }
}

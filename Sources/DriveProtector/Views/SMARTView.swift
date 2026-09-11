import SwiftUI

struct SMARTView: View {
    @ObservedObject var store: MonitorStore
    let disk: DiskInfo

    private var report: SMARTReport? { store.report(for: disk.bsdName) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryHeader
                attributesCard
                legendCard
            }
            .padding(24)
        }
    }

    // MARK: 顶部摘要

    private var summaryHeader: some View {
        let r = report
        return HStack(spacing: 12) {
            summaryPill(title: "健康度",
                        value: r.map { "\(Int($0.healthPercent))%" } ?? "—",
                        color: r.map { healthColor($0.healthPercent) } ?? Theme.textSecondary)
            summaryPill(title: "温度",
                        value: r?.temperatureC.map { String(format: "%.1f°C", $0) } ?? "—",
                        color: temperatureColor(r?.temperatureC))
            summaryPill(title: "SMART 总评",
                        value: (r?.overallPassed ?? true) ? "通过" : "警告",
                        color: (r?.overallPassed ?? true) ? Theme.green : Theme.red)
            summaryPill(title: "属性条数",
                        value: r.map { "\($0.attributes.count)" } ?? "—",
                        color: Theme.cyan)

            Spacer()

            HStack(spacing: 8) {
                if store.isRefreshingSMART {
                    ProgressView().controlSize(.small)
                }
                Chip(text: r?.source.rawValue ?? "等待数据",
                     color: r?.source == .smartctl ? Theme.green : Theme.amber,
                     icon: r?.source == .smartctl ? "checkmark.seal.fill" : "eye.fill")
                Button {
                    store.manualRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func summaryPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.stroke)
        )
    }

    // MARK: 属性表

    private var attributesCard: some View {
        VStack(spacing: 0) {
            HStack {
                SectionHeader(title: "SMART 属性",
                              subtitle: "Self-Monitoring, Analysis and Reporting Technology",
                              icon: "list.clipboard")
                Spacer()
            }
            .padding(18)

            tableHeader
            Rectangle().fill(Theme.stroke).frame(height: 1)

            if let attrs = report?.attributes, !attrs.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(Array(attrs.enumerated()), id: \.element) { index, attr in
                        attributeRow(attr, zebra: index % 2 == 0)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在读取 SMART 属性…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }
        }
        .cardStyle()
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("ID")
                .frame(width: 46, alignment: .leading)
            Text("属性名称")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("正常")
                .frame(width: 56, alignment: .trailing)
            Text("最差")
                .frame(width: 56, alignment: .trailing)
            Text("临界")
                .frame(width: 56, alignment: .trailing)
            Text("原始值")
                .frame(width: 200, alignment: .trailing)
            Text("状态")
                .frame(width: 30)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
        .textCase(.uppercase)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.02))
    }

    private func attributeRow(_ a: SMARTAttribute, zebra: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(String(format: "%02X", a.id))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 46, alignment: .leading)
                Text(a.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                normalizedText(a.value)
                    .frame(width: 56, alignment: .trailing)
                normalizedText(a.worst)
                    .frame(width: 56, alignment: .trailing)
                normalizedText(a.threshold)
                    .frame(width: 56, alignment: .trailing)
                Text(a.rawDisplay)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 200, alignment: .trailing)
                    .lineLimit(1)
                StatusDot(status: a.status)
                    .frame(width: 30)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(zebra ? Color.white.opacity(0.02) : Color.clear)
            Rectangle()
                .fill(Color.white.opacity(0.03))
                .frame(height: 1)
        }
    }

    private func normalizedText(_ v: Int?) -> some View {
        Text(v.map { "\($0)" } ?? "—")
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundStyle(v == nil ? Theme.textTertiary : Theme.textPrimary)
    }

    // MARK: 图例

    private var legendCard: some View {
        HStack(spacing: 20) {
            legendItem(color: Theme.green, text: "正常")
            legendItem(color: Theme.amber, text: "警告 · 需要关注")
            legendItem(color: Theme.red, text: "严重 · 建议备份更换")
            legendItem(color: Theme.textTertiary, text: "信息")
            Spacer()
            Text("注：NVMe 盘展示健康日志条目，SATA / USB-SAT 盘展示 ATA SMART 属性")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(16)
        .cardStyle()
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

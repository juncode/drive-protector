import SwiftUI

// MARK: - 标签 Chip

struct Chip: View {
    let text: String
    var color: Color = Theme.cyan
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule(style: .continuous).fill(color.opacity(0.14)))
        .foregroundStyle(color)
        .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 0.8))
    }
}

// MARK: - 健康度圆环

struct HealthRing: View {
    let percent: Double
    var size: CGFloat = 148
    var lineWidth: CGFloat = 11

    var body: some View {
        let color = healthColor(percent)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, percent / 100))
                .stroke(
                    LinearGradient(colors: [color.opacity(0.75), color],
                                   startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: percent)

            VStack(spacing: 2) {
                Text("\(Int(percent.rounded()))")
                    .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("%")
                    .font(.system(size: size * 0.11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("健康度")
                    .font(.system(size: size * 0.085, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 温度表盘（270° 弧）

struct TempDial: View {
    let temperature: Double?

    private let maxScale: Double = 100

    var body: some View {
        let t = temperature ?? 0
        let color = temperatureColor(temperature)
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.08), lineWidth: 10)
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: 0.75 * min(1, max(0, t) / maxScale))
                .stroke(
                    LinearGradient(colors: [Theme.cyan.opacity(0.7), color],
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.5), value: t)

            VStack(spacing: 4) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                if let temperature {
                    Text(String(format: "%.1f", temperature))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("°C")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("--")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .offset(y: 4)
        }
    }
}

// MARK: - 读写速率卡

struct SpeedCard: View {
    let title: String
    let icon: String
    let bytesPerSec: Double
    let peakMBps: Double
    let maxScaleMBps: Double
    let gradient: LinearGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(gradient))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: bytesPerSec > 1_000_000 ? "waveform" : "circle")
                    .font(.system(size: 9))
                    .foregroundStyle(bytesPerSec > 1_000_000 ? Theme.green : Theme.textTertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.mbps(bytesPerSec))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("MB/s")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            GeometryReader { geo in
                let fraction = min(1, bytesPerSec / 1_000_000 / max(1, maxScaleMBps))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(gradient)
                        .frame(width: max(4, geo.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 6)

            HStack {
                Text("峰值 \(String(format: "%.0f", peakMBps)) MB/s")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(bytesPerSec > 1_000_000 ? "传输中" : "空闲")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(bytesPerSec > 1_000_000 ? Theme.green : Theme.textTertiary)
            }
        }
        .padding(16)
        .cardStyle()
    }
}

// MARK: - 数据小格

struct StatTile: View {
    let icon: String
    let title: String
    let value: String
    var tint: Color = Theme.cyan
    var warning: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(warning ? Theme.red : tint)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(warning ? Theme.red : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(warning ? 0.05 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(warning ? Theme.red.opacity(0.35) : Theme.stroke, lineWidth: 1)
        )
    }
}

// MARK: - 容量条

struct CapacityBar: View {
    let fraction: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(Theme.cyanGradient)
                    .frame(width: max(height, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: height)
    }
}

// MARK: - 实时吞吐曲线

struct ThroughputChart: View {
    let samples: [ThroughputSample]
    let scaleMaxMBps: Double

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 6
            let plotW = geo.size.width - inset * 2
            let plotH = geo.size.height - 24
            let maxV = max(10, scaleMaxMBps)
            let stepX = plotW / CGFloat(max(1, samples.count - 1))

            ZStack(alignment: .topLeading) {
                // 网格横线
                Path { p in
                    for i in 0...3 {
                        let y = CGFloat(i) * plotH / 3
                        p.move(to: CGPoint(x: inset, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width - inset, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.05), lineWidth: 1)

                // Y 轴刻度
                ForEach(0..<4) { i in
                    let v = maxV * Double(3 - i) / 3
                    Text(v >= 1000 ? String(format: "%.0fk", v / 1000) : String(format: "%.0f", v))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .position(x: inset + 14, y: CGFloat(i) * plotH / 3 + 8)
                }

                if samples.count >= 2 {
                    areaPath(samples: samples, stepX: stepX, plotH: plotH,
                             inset: inset, keyPath: \.readMBps, maxV: maxV)
                        .fill(Theme.cyan.opacity(0.10))

                    linePath(samples: samples, stepX: stepX, plotH: plotH,
                             inset: inset, keyPath: \.readMBps, maxV: maxV)
                        .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                    linePath(samples: samples, stepX: stepX, plotH: plotH,
                             inset: inset, keyPath: \.writeMBps, maxV: maxV)
                        .stroke(Theme.purple, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                    // 末端光点
                    if let last = samples.last {
                        Circle()
                            .fill(Theme.cyan)
                            .frame(width: 7, height: 7)
                            .position(point(last, idx: samples.count - 1, stepX: stepX,
                                           plotH: plotH, inset: inset,
                                           keyPath: \.readMBps, maxV: maxV))
                            .shadow(color: Theme.cyan, radius: 6)
                    }
                } else {
                    Text("正在采集实时数据…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .position(x: geo.size.width / 2, y: plotH / 2)
                }
            }
        }
    }

    private func point(_ s: ThroughputSample, idx: Int, stepX: CGFloat, plotH: CGFloat,
                       inset: CGFloat, keyPath: KeyPath<ThroughputSample, Double>,
                       maxV: Double) -> CGPoint {
        let v = min(1, s[keyPath: keyPath] / maxV)
        return CGPoint(x: inset + CGFloat(idx) * stepX,
                       y: plotH * (1 - CGFloat(v)))
    }

    private func areaPath(samples: [ThroughputSample], stepX: CGFloat, plotH: CGFloat,
                          inset: CGFloat, keyPath: KeyPath<ThroughputSample, Double>,
                          maxV: Double) -> Path {
        Path { p in
            p.move(to: CGPoint(x: inset, y: plotH))
            for (i, s) in samples.enumerated() {
                p.addLine(to: point(s, idx: i, stepX: stepX, plotH: plotH,
                                    inset: inset, keyPath: keyPath, maxV: maxV))
            }
            p.addLine(to: CGPoint(x: inset + CGFloat(max(1, samples.count - 1)) * stepX, y: plotH))
            p.closeSubpath()
        }
    }

    private func linePath(samples: [ThroughputSample], stepX: CGFloat, plotH: CGFloat,
                          inset: CGFloat, keyPath: KeyPath<ThroughputSample, Double>,
                          maxV: Double) -> Path {
        Path { p in
            for (i, s) in samples.enumerated() {
                let pt = point(s, idx: i, stepX: stepX, plotH: plotH,
                               inset: inset, keyPath: keyPath, maxV: maxV)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }
}

// MARK: - 状态圆点

struct StatusDot: View {
    let status: AttrStatus
    var body: some View {
        let color: Color = switch status {
        case .good: Theme.green
        case .warning: Theme.amber
        case .critical: Theme.red
        case .info: Theme.textTertiary
        }
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.8), radius: 3)
    }
}

// MARK: - 标题行

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}

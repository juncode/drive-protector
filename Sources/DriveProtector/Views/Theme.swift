import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0A0E16)
    static let sidebar = Color(hex: 0x0D1420)
    static let card = Color(hex: 0x121A2A)
    static let cardAlt = Color(hex: 0x162032, alpha: 0.55)
    static let stroke = Color.white.opacity(0.07)
    static let strokeStrong = Color.white.opacity(0.12)

    static let cyan = Color(hex: 0x35C8F2)
    static let blue = Color(hex: 0x3D7BF5)
    static let purple = Color(hex: 0x9B7BFF)
    static let green = Color(hex: 0x2BD99A)
    static let amber = Color(hex: 0xF7B50C)
    static let red = Color(hex: 0xFF5C6C)

    static let textPrimary = Color(hex: 0xE9EFFA)
    static let textSecondary = Color(hex: 0x8D9AB3)
    static let textTertiary = Color(hex: 0x5B667F)

    static let cyanGradient = LinearGradient(
        colors: [Color(hex: 0x4FD8FF), Color(hex: 0x2E7BFF)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let purpleGradient = LinearGradient(
        colors: [Color(hex: 0xB18BFF), Color(hex: 0x6B4DFF)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let greenGradient = LinearGradient(
        colors: [Color(hex: 0x3DE8B0), Color(hex: 0x12A872)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    init(hex: Int, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha)
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }

    func sectionLabel() -> some View {
        self
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

// MARK: - 状态配色

func healthColor(_ percent: Double) -> Color {
    switch percent {
    case 80...: return Theme.green
    case 60..<80: return Theme.amber
    default: return Theme.red
    }
}

func temperatureColor(_ c: Double?) -> Color {
    guard let c else { return Theme.textSecondary }
    switch c {
    case ..<50: return Theme.green
    case 50..<70: return Theme.amber
    default: return Theme.red
    }
}

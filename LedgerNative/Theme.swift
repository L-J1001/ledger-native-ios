import SwiftUI
import UIKit

enum AppTheme {
    static let accent = Color(red: 0.16, green: 0.42, blue: 0.95)
    static let accentDeep = Color(red: 0.08, green: 0.26, blue: 0.72)
    static let accentSoft = Color(red: 0.16, green: 0.42, blue: 0.95).opacity(0.11)
    static let income = Color(red: 0.06, green: 0.63, blue: 0.42)
    static let incomeSoft = Color(red: 0.06, green: 0.63, blue: 0.42).opacity(0.12)
    static let expense = Color(red: 0.90, green: 0.26, blue: 0.35)
    static let expenseSoft = Color(red: 0.90, green: 0.26, blue: 0.35).opacity(0.12)
    static let gold = Color(red: 0.83, green: 0.62, blue: 0.25)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let grouped = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .tertiarySystemGroupedBackground)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let hairline = Color(uiColor: .separator).opacity(0.30)
    static let heroTop = Color(red: 0.055, green: 0.125, blue: 0.255)
    static let heroBottom = Color(red: 0.115, green: 0.255, blue: 0.455)
    static let shadow = Color.black.opacity(0.05)
}

extension Color {
    init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        let scanner = Scanner(string: cleaned)
        var value: UInt64 = 0
        if scanner.scanHexInt64(&value), cleaned.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xFF) / 255.0,
                green: Double((value >> 8) & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0
            )
        } else {
            self.init(red: 0.16, green: 0.42, blue: 0.95)
        }
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 0.5)
            )
            .shadow(color: AppTheme.shadow, radius: 14, x: 0, y: 6)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16, radius: CGFloat = 22) -> some View {
        modifier(CardBackground(padding: padding, radius: radius))
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.30, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = AppTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: [tint, tint.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: tint.opacity(0.22), radius: 10, x: 0, y: 5)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct SoftChip: View {
    let title: String
    var selected: Bool = false
    var color: Color = AppTheme.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(selected ? color : AppTheme.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : AppTheme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct MetricPill: View {
    let title: String
    let value: String
    var color: Color = AppTheme.accent
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

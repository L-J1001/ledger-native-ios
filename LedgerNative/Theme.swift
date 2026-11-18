import SwiftUI
import UIKit

enum AppTheme {
    static let accent = Color(red: 0.247, green: 0.470, blue: 0.980)
    static let accentSoft = Color(red: 0.247, green: 0.470, blue: 0.980).opacity(0.12)
    static let income = Color(red: 0.102, green: 0.639, blue: 0.404)
    static let expense = Color(red: 0.914, green: 0.298, blue: 0.365)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let grouped = Color(uiColor: .systemGroupedBackground)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let hairline = Color(uiColor: .separator).opacity(0.35)
    static let heroTop = Color(red: 0.075, green: 0.145, blue: 0.290)
    static let heroBottom = Color(red: 0.145, green: 0.275, blue: 0.470)
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
            self.init(red: 0.247, green: 0.470, blue: 0.980)
        }
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 5)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: [AppTheme.accent, Color(red: 0.18, green: 0.36, blue: 0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

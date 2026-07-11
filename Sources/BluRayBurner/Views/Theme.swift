import SwiftUI

// Queimada design language — tokens and shared styles lifted from design.pen
// (Window / Drag & Drop, Window / Data Disc). The app renders dark-only.
enum Theme {
    // Surfaces
    static let windowBg = Color(hex: 0x263C3C)
    static let panelBg = Color(hex: 0x203232)
    static let chromeTint = Color.white.opacity(0.04)      // titlebar/footer #FFFFFF0A
    static let insetTint = Color.white.opacity(0.03)       // drop zone #FFFFFF08
    static let hairline = Color.white.opacity(0.08)        // #FFFFFF14

    // Text
    static let textPrimary = Color(hex: 0xF0F6F5)
    static let textSecondary = Color(hex: 0x9FB6B4)
    static let textTertiary = Color(hex: 0x6E8886)

    // Accents
    static let accent = Color(hex: 0x00BFFF)               // blue-flame cyan
    static let gold = Color(hex: 0xFFD700)                 // folder / drive icons
    static let clay = Color(hex: 0xA0522D)                 // destructive-ish brand accent
    static let clayText = Color(hex: 0xEDBB94)

    // Gradients (design: linear, top → bottom)
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: 0x00BFFF), Color(hex: 0x0077E6)],
        startPoint: .top, endPoint: .bottom
    )
    static let burnGradient = LinearGradient(
        colors: [Color(hex: 0xA33027), Color(hex: 0x691A15)],
        startPoint: .top, endPoint: .bottom
    )

    /// Brand mark (flame disc) bundled from images/queimada-flame-disc.png.
    static var brandMark: Image? {
        guard let url = Bundle.module.url(forResource: "queimada-flame-disc", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: image)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Motion

extension Theme {
    /// Screen-navigation motion. The flow has a fixed spatial order — welcome
    /// is the hub on the left, workflows live to its right — so each screen's
    /// transition is static and direction stays correct for push and pop.
    enum Motion {
        static let screen = Animation.easeOut(duration: 0.35)

        static let hubScreen = AnyTransition.offset(x: -28).combined(with: .opacity)
        static let workflowScreen = AnyTransition.offset(x: 28).combined(with: .opacity)
        static let footer = AnyTransition.offset(y: 12).combined(with: .opacity)
    }
}

// MARK: - Buttons

/// Filled gradient action button (Start Over, Burn Disc, Done).
struct GradientButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.primaryGradient
    var shadow: Color = Theme.accent.opacity(0.3)
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: isEnabled ? shadow : .clear, radius: 6, y: 2)
            .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.4))
    }
}

/// Quiet clay-tinted secondary button (Erase a rewritable disc…, Cancel).
struct ClayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Theme.clayText)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Theme.clay.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.clay.opacity(0.4), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Neutral quiet button on the dark chrome (Choose Image…, secondary actions).
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Design-language checkbox (cyan fill, dark check) — Verify Disc.
struct QueimadaCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isOn ? Theme.accent : Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(configuration.isOn ? Color.clear : Theme.hairline, lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: 0x10281F))
                            .opacity(configuration.isOn ? 1 : 0)
                    )
                    .frame(width: 16, height: 16)
                configuration.label
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hairline

/// 1px separator in the design's hairline color.
struct Hairline: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

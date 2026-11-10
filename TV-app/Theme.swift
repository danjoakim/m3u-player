import SwiftUI

/// Farger og stil hentet fra designforslaget.
enum Theme {
    static let bg = Color(hex: 0x0A0C10)
    static let sidebar = Color(hex: 0x11141B)
    static let surface = Color(hex: 0x141820)
    static let surface2 = Color(hex: 0x18202C)
    static let border = Color(hex: 0x222936)
    static let text = Color(hex: 0xF2F4F8)
    static let soft = Color(hex: 0xC3CAD6)
    static let muted = Color(hex: 0x9AA4B5)
    static let accent = Color(hex: 0x5EEAD4)
    static let live = Color(hex: 0xFF5A5F)

    private static let tints: [Color] = [
        Color(hex: 0x2B3A55), Color(hex: 0x3A2B4F), Color(hex: 0x4A3326), Color(hex: 0x24433F),
        Color(hex: 0x4A2B3A), Color(hex: 0x2F4A2B), Color(hex: 0x263449), Color(hex: 0x3A3550)
    ]

    /// Fast farge per navn, slik at samme kanal alltid får samme farge.
    static func tint(for key: String) -> Color {
        var hash: UInt64 = 5381
        for byte in key.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return tints[Int(hash % UInt64(tints.count))]
    }

    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count >= 2 {
            return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.bg)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .background(Theme.accent, in: .rect(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.text)
            .frame(minWidth: 48, minHeight: 48)
            .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x3A4558)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

import AppKit
import SwiftUI

/// Colors of the panel (light and dark): Apple's system palette, one accent (blue).
enum Theme {
    static let page = dynamic(0xF7F9FB, 0x1C1F22)
    static let card = dynamic(0xFFFFFF, 0x2A2A2D)
    static let line = dynamic(0xE2E2E6, 0x3A3A3D)
    static let sub = dynamic(0x6E6E73, 0x98989D)
    static let accent = dynamic(0x0E7FB8, 0x3BA7DE)   // sea blue
    static let accentSoft = dynamic(0xE3F1FA, 0x163447)
    static let green = dynamic(0x248A3D, 0x30D158)
    static let greenSoft = dynamic(0xE8F6EC, 0x1D3524)
    static let greenDot = dynamic(0x34C759, 0x30D158)
    static let amber = dynamic(0xC25E00, 0xFF9F0A)
    static let amberSoft = dynamic(0xFFF4E5, 0x3A2C17)
    static let amberLine = dynamic(0xF5D9B0, 0x5A4220)
    static let badge = dynamic(0xFF3B30, 0xFF453A)
    static let blueText = dynamic(0x0B6A9A, 0x7CC4EA)
    static let neutralSoft = dynamic(0xEDEDF0, 0x3A3A3D)
    static let neutralText = dynamic(0x3C3C43, 0xD1D1D6)
    static let bubbleMine = dynamic(0xDCF5D0, 0x2C4A27)
    static let bubbleTheirs = dynamic(0xF1F1F4, 0x3A3A3D)
    /// Icon tiles in the settings menu, like System Settings.
    static let tileBlue = dynamic(0x007AFF, 0x0A84FF)
    static let tileOrange = dynamic(0xFF9500, 0xFF9F0A)
    static let tileGreen = dynamic(0x34C759, 0x30D158)
    static let tileTeal = dynamic(0x30B0C7, 0x40C8E0)
    static let tileGray = dynamic(0x8E8E93, 0x8E8E93)
    static let tilePurple = dynamic(0xAF52DE, 0xBF5AF2)
    static let tileRed = dynamic(0xFF3B30, 0xFF453A)
    /// The selected segment's thumb.
    static let thumb = dynamic(0xFFFFFF, 0x636366)
    /// The 动态 page's big card: deep sea while running, pale sea when stopped.
    static let heroTop = dynamic(0x1592CF, 0x1C7FB3)
    static let heroBottom = dynamic(0x0B6A9A, 0x0E4F73)
    static let heroIdle = dynamic(0xEAF4FA, 0x1A2A35)
    static let heroInk = dynamic(0x0B4F73, 0xBFE3F7)
    static let corner: CGFloat = 12        // cards
    static let buttonCorner: CGFloat = 8   // buttons; the one big button of a screen uses `corner`

    private static func dynamic(_ light: Int, _ dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// A rounded group with a hairline border, like a group in System Settings.
struct CardBox<Content: View>: View {
    var padding: CGFloat = 14
    var border: Color = .clear
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(border, lineWidth: 0.5))
    }
}

/// The one big action of a screen: filled, rounded, a little darker on hover, pressed in when clicked.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    var height: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        PrimaryLook(configuration: configuration, color: color, height: height)
    }

    struct PrimaryLook: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        let height: CGFloat
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false
        private var radius: CGFloat { height >= 40 ? Theme.corner : Theme.buttonCorner }

        var body: some View {
            configuration.label
                .font(.system(size: height >= 40 ? 15 : 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, height < 40 ? 14 : 0)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.black.opacity(configuration.isPressed ? 0.16 : hover ? 0.07 : 0)))
                .shadow(color: color.opacity(enabled ? 0.25 : 0), radius: hover ? 6 : 3, y: hover ? 2 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(enabled ? 1 : 0.45)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hover)
                .onHover { hover = $0 && enabled }
                .contentShape(Rectangle())
        }
    }
}

/// A quiet secondary action: a light grey fill instead of a border.
struct SoftButtonStyle: ButtonStyle {
    var color: Color = Theme.neutralText
    var height: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        SoftLook(configuration: configuration, color: color, height: height)
    }

    struct SoftLook: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        let height: CGFloat
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .padding(.horizontal, height < 30 ? 10 : 14)
                .frame(minHeight: height)
                .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(Theme.neutralSoft.opacity(configuration.isPressed ? 1 : hover ? 0.85 : 0.6)))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(enabled ? 1 : 0.45)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
                .onHover { hover = $0 && enabled }
                .contentShape(Rectangle())
        }
    }
}

/// A small pale sea-blue capsule (“去回复”, “＋ 添加”).
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.blueText)
            .padding(.horizontal, 12).frame(height: 28)
            .background(Capsule().fill(Theme.accentSoft.opacity(configuration.isPressed ? 0.7 : 1)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// A light grey background while the pointer is over a row, like list rows on the Mac.
struct HoverHighlight: ViewModifier {
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .background(Theme.neutralSoft.opacity(hover ? 0.6 : 0))
            .animation(.easeOut(duration: 0.12), value: hover)
            .onHover { hover = $0 }
    }
}

extension View {
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
}

/// Small rounded label (“预留中”, “想要：水蜜桃”).
struct TagView: View {
    enum Kind { case green, blue, amber, neutral }
    let text: String
    var kind: Kind = .neutral

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(fg)
            .background(Capsule().fill(bg))
    }

    private var fg: Color {
        switch kind {
        case .green: return Theme.green
        case .blue: return Theme.blueText
        case .amber: return Theme.amber
        case .neutral: return Theme.neutralText
        }
    }

    private var bg: Color {
        switch kind {
        case .green: return Theme.greenSoft
        case .blue: return Theme.accentSoft
        case .amber: return Theme.amberSoft
        case .neutral: return Theme.neutralSoft
        }
    }
}

/// Small grey heading above a group.
struct SectionHeader: View {
    let title: String
    @Environment(\.sectionHeadersHidden) private var hidden
    var body: some View {
        if !hidden {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.sub).padding(.leading, 2)
        }
    }
}

/// A settings page with a single card already shows its name as the page title.
private struct SectionHeadersHidden: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var sectionHeadersHidden: Bool {
        get { self[SectionHeadersHidden.self] }
        set { self[SectionHeadersHidden.self] = newValue }
    }
}

/// A customer's avatar: the picture from the chat app when we have it, else their initial.
struct AvatarView: View {
    let name: String
    let image: NSImage?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Text(initial).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.black.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(color)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    /// First character of the name, skipping prefixes like “客户·”.
    private var initial: String {
        let n = name.replacingOccurrences(of: "客户", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "·•. "))
        return String(n.first ?? name.first ?? "?")
    }

    private var color: Color {
        let palette: [Color] = [.orange, .blue, .purple, .teal, .pink, .green, .indigo]
        let i = abs(name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }) % palette.count
        return palette[i].opacity(0.35)
    }
}

/// A settings line: title (and an optional hint) on the left, a control on the right.
struct SettingLine<Control: View>: View {
    let title: String
    var hint: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14))
                if let hint { Text(hint).font(.system(size: 12)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            control
        }
        .frame(minHeight: 30)
    }
}

/// A toggle line in a settings card.
struct ToggleLine: View {
    let title: String
    var hint: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingLine(title: title, hint: hint) {
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }
}

extension Date {
    /// “10:30” today, “昨天”, or “11月3日”.
    var shortLabel: String {
        if Calendar.current.isDateInToday(self) { return formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
        if Calendar.current.isDateInYesterday(self) { return "昨天" }
        return formatted(.dateTime.month().day())
    }
}

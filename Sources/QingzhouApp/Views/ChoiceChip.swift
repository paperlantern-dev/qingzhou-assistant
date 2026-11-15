import SwiftUI

/// One option in a ChoiceChip's panel.
struct ChoiceOption: Identifiable {
    let id: String
    let title: String
    var detail: String = ""
}

/// A small rounded choice on the big card. A click opens our own light panel (not the grey system
/// menu): one row per option, a short line under each, a check mark on the chosen one.
struct ChoiceChip: View {
    let title: String
    var icon: String? = nil
    let onDark: Bool
    let options: [ChoiceOption]
    let selected: String
    let pick: (String) -> Void
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(title)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.7)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(onDark ? Color.white.opacity(0.2) : Theme.card))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) { panel }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(options) { o in
                Button {
                    pick(o.id)
                    open = false
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.primary)
                            if !o.detail.isEmpty {
                                Text(o.detail).font(.system(size: 13)).foregroundStyle(Theme.sub)
                            }
                        }
                        Spacer(minLength: 12)
                        if o.id == selected {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(o.id == selected ? Theme.accentSoft.opacity(0.6) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 250)
    }
}

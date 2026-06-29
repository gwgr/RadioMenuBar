import SwiftUI

struct MenuRow: View {
    let title: String
    var systemImage: String?
    var reservesImageSpace = false
    var shortcutHint: String?

    var body: some View {
        HStack(spacing: 10) {
            if reservesImageSpace {
                if let systemImage {
                    Image(systemName: systemImage)
                        .frame(width: 22)
                } else {
                    Color.clear
                        .frame(width: 22)
                }
            }

            Text(title)
            Spacer()

            if let shortcutHint {
                Text(shortcutHint)
                    .foregroundStyle(.tertiary)
            }
        }
        .menuHover()
    }
}

struct SelectableMenuRow: View {
    let title: String
    let isSelected: Bool
    var selectedSystemImage = "checkmark"
    var shortcutHint: String?

    var body: some View {
        MenuRow(
            title: title,
            systemImage: isSelected ? selectedSystemImage : nil,
            reservesImageSpace: true,
            shortcutHint: shortcutHint
        )
    }
}

struct CommandMenuRow: View {
    let title: String
    var shortcutHint: String?

    var body: some View {
        MenuRow(title: title, shortcutHint: shortcutHint)
    }
}

struct MenuHover: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isHovering {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.selectedContentBackgroundColor).opacity(0.4))
                }
            }
            .onHover { isHovering = $0 }
    }
}

struct OptionalKeyboardShortcut: ViewModifier {
    let key: KeyEquivalent?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key)
        } else {
            content
        }
    }
}

extension View {
    func menuHover() -> some View {
        modifier(MenuHover())
    }

    func optionalKeyboardShortcut(_ key: KeyEquivalent?) -> some View {
        modifier(OptionalKeyboardShortcut(key: key))
    }
}

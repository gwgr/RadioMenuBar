import SwiftUI

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

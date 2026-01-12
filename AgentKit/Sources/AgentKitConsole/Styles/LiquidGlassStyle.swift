import SwiftUI

// MARK: - Liquid Glass Design System

/// macOS Tahoe "Liquid Glass" design system components.
///
/// Liquid Glass is characterized by:
/// - Translucent materials with subtle blur
/// - Smooth, rounded corners
/// - Subtle depth through shadows and highlights
/// - Fluid, springy animations
/// - Content that "floats" above backgrounds

// MARK: - Glass Card

/// A glassmorphic card container
struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 16

    init(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Glass Button Style

/// A glassmorphic button style
struct GlassButtonStyle: ButtonStyle {
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                if isProminent {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.gradient)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(isProminent ? 0.3 : 0.15), lineWidth: 0.5)
            )
            .foregroundStyle(isProminent ? .white : .primary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Glass Pill Button

/// A pill-shaped glassmorphic button (like the Agent panel toggle)
struct GlassPillButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var isActive: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isActive {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.2))
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Sidebar Item

/// A sidebar row with glassmorphic selection state
struct GlassSidebarItem: View {
    let title: String
    let icon: String
    var badge: Int? = nil
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 20)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            Text(title)
                .foregroundStyle(isSelected ? .primary : .secondary)

            Spacer()

            if let badge, badge > 0 {
                Text("\(badge)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.15))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Glass Input Field

/// A glassmorphic text input field
struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
            }

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit {
                    onSubmit?()
                }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Glass Floating Panel

/// A floating panel with glassmorphic styling (for popovers, sheets)
struct GlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Glass Status Badge

/// A small status indicator badge
struct GlassStatusBadge: View {
    let status: StatusType
    var label: String? = nil

    enum StatusType {
        case active, warning, error, idle

        var color: Color {
            switch self {
            case .active: return .green
            case .warning: return .orange
            case .error: return .red
            case .idle: return .secondary
            }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)

            if let label {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - View Extensions

extension View {
    /// Apply glassmorphic card styling
    func glassCard(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    /// Apply subtle hover effect
    func glassHover() -> some View {
        self.modifier(GlassHoverModifier())
    }

    /// Apply spring animation to any value change
    func springAnimation<V: Equatable>(for value: V) -> some View {
        self.animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
    }
}

// MARK: - Glass Hover Modifier

private struct GlassHoverModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .shadow(
                color: .black.opacity(isHovered ? 0.15 : 0.1),
                radius: isHovered ? 12 : 8,
                x: 0,
                y: isHovered ? 6 : 4
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Animation Extensions

extension Animation {
    /// Standard spring animation for Liquid Glass
    static var liquidGlass: Animation {
        .spring(response: 0.35, dampingFraction: 0.75)
    }

    /// Quick spring for micro-interactions
    static var liquidGlassQuick: Animation {
        .spring(response: 0.2, dampingFraction: 0.7)
    }

    /// Slow spring for larger movements
    static var liquidGlassSlow: Animation {
        .spring(response: 0.5, dampingFraction: 0.8)
    }
}

// MARK: - Editor Design Tokens

/// Design tokens specific to the document editor
enum EditorTokens {
    // MARK: Spacing
    enum Spacing {
        static let blockVertical: CGFloat = 2
        static let blockHorizontal: CGFloat = 8
        static let contentPadding: CGFloat = 24
        static let handleWidth: CGFloat = 40
        static let titleBottomPadding: CGFloat = 16
    }

    // MARK: Typography
    enum Typography {
        static let title: Font = .system(size: 32, weight: .bold)
        static let heading1: Font = .system(size: 28, weight: .bold)
        static let heading2: Font = .system(size: 22, weight: .semibold)
        static let heading3: Font = .system(size: 18, weight: .semibold)
        static let code: Font = .system(.body, design: .monospaced)
    }

    // MARK: Colors
    enum Colors {
        static let blockHoverBackground = Color.primary.opacity(0.03)
        static let blockFocusBackground = Color.accentColor.opacity(0.05)
        static let blockFocusBorder = Color.accentColor.opacity(0.2)
        static let agentAccent = Color.purple
        static let agentBackground = Color.purple.opacity(0.05)
        static let agentBorder = Color.purple.opacity(0.3)
        static let codeBackground = Color(.controlBackgroundColor)
        static let menuBackground = Color(.windowBackgroundColor)
    }

    // MARK: Radii
    enum Radii {
        static let block: CGFloat = 8
        static let menu: CGFloat = 12
        static let code: CGFloat = 6
        static let input: CGFloat = 6
    }

    // MARK: Shadows
    enum Shadows {
        static let menuRadius: CGFloat = 16
        static let menuY: CGFloat = 6
        static let menuOpacity: Double = 0.18
    }
}

// MARK: - Editor Block Modifier

/// Applies consistent hover/focus styling to editor blocks
struct EditorBlockModifier: ViewModifier {
    let isHovered: Bool
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.vertical, EditorTokens.Spacing.blockVertical)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: EditorTokens.Radii.block)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: EditorTokens.Radii.block)
                    .stroke(isFocused ? EditorTokens.Colors.blockFocusBorder : Color.clear, lineWidth: 1)
            )
            .animation(.liquidGlassQuick, value: isHovered)
            .animation(.liquidGlassQuick, value: isFocused)
    }

    private var backgroundColor: Color {
        if isFocused {
            return EditorTokens.Colors.blockFocusBackground
        } else if isHovered {
            return EditorTokens.Colors.blockHoverBackground
        }
        return .clear
    }
}

extension View {
    /// Apply editor block styling with hover/focus states
    func editorBlock(isHovered: Bool, isFocused: Bool) -> some View {
        modifier(EditorBlockModifier(isHovered: isHovered, isFocused: isFocused))
    }
}

// MARK: - Glass Menu Style

/// A polished glass menu for slash commands and block type menus
struct GlassMenu<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: EditorTokens.Radii.menu))
            .overlay(
                RoundedRectangle(cornerRadius: EditorTokens.Radii.menu)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(
                color: .black.opacity(EditorTokens.Shadows.menuOpacity),
                radius: EditorTokens.Shadows.menuRadius,
                y: EditorTokens.Shadows.menuY
            )
    }
}

// MARK: - Glass Menu Item

/// A menu item with proper hover state for glass menus
struct GlassMenuItem: View {
    let title: String
    let icon: String
    var subtitle: String? = nil
    var iconColor: Color = .secondary
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

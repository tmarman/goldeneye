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

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
            .padding(.vertical, EditorTokens.Spacing.blockVertical + 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: EditorTokens.Radii.block)
                    .fill(backgroundColor)
                    .shadow(
                        color: shadowColor,
                        radius: shadowRadius,
                        x: 0,
                        y: shadowY
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: EditorTokens.Radii.block)
                    .stroke(borderColor, lineWidth: isFocused ? 1.5 : 0.5)
            )
            .scaleEffect(isHovered && !isFocused ? 1.002 : 1.0)
            .animation(.liquidGlassQuick, value: isHovered)
            .animation(.liquidGlassQuick, value: isFocused)
    }

    private var backgroundColor: Color {
        if isFocused {
            return EditorTokens.Colors.blockFocusBackground
        } else if isHovered {
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        }
        return .clear
    }

    private var borderColor: Color {
        if isFocused {
            return EditorTokens.Colors.blockFocusBorder
        } else if isHovered {
            return Color(nsColor: .separatorColor).opacity(0.3)
        }
        return .clear
    }

    private var shadowColor: Color {
        if isFocused {
            return .black.opacity(0.08)
        } else if isHovered {
            return .black.opacity(0.04)
        }
        return .clear
    }

    private var shadowRadius: CGFloat {
        if isFocused { return 8 }
        if isHovered { return 4 }
        return 0
    }

    private var shadowY: CGFloat {
        if isFocused { return 3 }
        if isHovered { return 2 }
        return 0
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

// MARK: - Shimmer Effect

/// A shimmer loading effect for skeleton UI
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    let animation: Animation

    init(animation: Animation = Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
        self.animation = animation
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.4), location: 0.3),
                            .init(color: .white.opacity(0.5), location: 0.5),
                            .init(color: .white.opacity(0.4), location: 0.7),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(animation) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// Apply shimmer loading effect
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Glass Loading Skeleton

/// A skeleton placeholder with glassmorphic styling
struct GlassSkeleton: View {
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.secondary.opacity(0.15))
            .frame(height: height)
            .shimmer()
    }
}

// MARK: - Rich Empty State

/// A polished empty state with illustration
struct GlassEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            // Icon with animated background
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.accentColor.opacity(0.15), Color.accentColor.opacity(0.03)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: icon)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                    .symbolEffect(.pulse, options: .repeating.speed(0.3))
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.body.weight(.medium))
                }
                .buttonStyle(GlassButtonStyle(isProminent: true))
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pulse Ring Effect

/// An animated pulse ring effect for active states
struct PulseRing: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.5), lineWidth: 2)
            .scaleEffect(animate ? 1.8 : 1.0)
            .opacity(animate ? 0 : 0.8)
            .animation(
                .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                value: animate
            )
            .onAppear { animate = true }
    }
}

// MARK: - Floating Action Button

/// A floating action button with glassmorphic styling
struct GlassFloatingButton: View {
    let icon: String
    let action: () -> Void
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Glow effect
                Circle()
                    .fill(Color.accentColor.opacity(0.3))
                    .blur(radius: 12)
                    .scaleEffect(isHovered ? 1.3 : 1.0)

                // Main button
                Circle()
                    .fill(Color.accentColor.gradient)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(color: Color.accentColor.opacity(0.4), radius: isHovered ? 16 : 10, y: 4)

                Image(systemName: icon)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white)
            }
            .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Progress Ring

/// A circular progress indicator with glassmorphic styling
struct GlassProgressRing: View {
    let progress: Double  // 0.0 to 1.0
    var lineWidth: CGFloat = 4
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.5)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * progress)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.3), value: progress)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Notification Badge

/// A bouncing notification badge for attention
struct GlassNotificationBadge: View {
    let count: Int
    @State private var bounce = false

    var body: some View {
        Text("\(min(count, 99))")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, count > 9 ? 6 : 4)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.red.gradient)
                    .shadow(color: .red.opacity(0.4), radius: 4)
            )
            .scaleEffect(bounce ? 1.2 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: bounce)
            .onAppear {
                bounce = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    bounce = false
                }
            }
    }
}

// MARK: - Notes-Style Components
// Inspired by Apple Notes' clean, minimal aesthetic

/// A Notes-style toolbar button (minimal, icon-only with hover state)
struct NotesToolbarButton: View {
    let icon: String
    let action: () -> Void
    var isActive: Bool = false
    var help: String? = nil
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isActive ? Color.accentColor : (isHovered ? .primary : .secondary))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help ?? "")
    }
}

/// A Notes-style search field (inline, minimal)
struct NotesSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFocused ? Color.primary.opacity(0.08) : Color.primary.opacity(0.05))
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

/// A Notes-style list item (document preview style)
struct NotesListItem: View {
    let title: String
    var subtitle: String? = nil
    var date: Date? = nil
    var isSelected: Bool = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(spacing: 0) {
                if let date {
                    Text(formattedDate(date))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if let subtitle, !subtitle.isEmpty {
                    Text("  ")
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.05) : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "M/d/yy"
        }
        return formatter.string(from: date)
    }
}

/// A Notes-style section header
struct NotesSectionHeader: View {
    let title: String
    var isCollapsible: Bool = false
    var isCollapsed: Bool = false
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if isCollapsible {
                Button(action: { onToggle?() }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }

            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// A Notes-style unified toolbar (combines sidebar toggle, title, and actions)
struct NotesToolbar<LeadingContent: View, TrailingContent: View>: View {
    let title: String
    var subtitle: String? = nil
    let leadingContent: LeadingContent
    let trailingContent: TrailingContent

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> LeadingContent,
        @ViewBuilder trailing: () -> TrailingContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leadingContent = leading()
        self.trailingContent = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            leadingContent

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            trailingContent
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor).opacity(0.95))
    }
}

/// A Notes-style divider (thinner, more subtle)
struct NotesDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
    }
}

// MARK: - Combined Notes + Craft Styles

/// A hybrid card that combines Notes cleanliness with Craft's subtle glass
struct HybridCard<Content: View>: View {
    let content: Content
    var isSelected: Bool = false
    @State private var isHovered = false

    init(isSelected: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.isSelected = isSelected
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.3) : (isHovered ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06)),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: .black.opacity(isHovered ? 0.08 : 0.04),
                radius: isHovered ? 8 : 4,
                y: isHovered ? 3 : 1
            )
            .scaleEffect(isHovered ? 1.005 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .onHover { isHovered = $0 }
    }
}

/// A subtle icon button used throughout both styles
struct IconButton: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = 20
    var tint: Color = .secondary
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.7, weight: .medium))
                .foregroundStyle(isHovered ? .primary : tint)
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Date display like Notes uses
struct DateDisplay: View {
    let date: Date

    var body: some View {
        Text(formattedDate)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Craft-Style Inline Formatting Toolbar

/// A floating inline formatting toolbar that appears on text selection (Craft-like)
struct InlineFormattingToolbar: View {
    let onBold: () -> Void
    let onItalic: () -> Void
    let onStrikethrough: () -> Void
    let onCode: () -> Void
    let onLink: () -> Void
    let onHighlight: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            FormatButton(icon: "bold", help: "Bold (⌘B)", action: onBold)
            FormatButton(icon: "italic", help: "Italic (⌘I)", action: onItalic)
            FormatButton(icon: "strikethrough", help: "Strikethrough", action: onStrikethrough)

            ToolbarDivider()

            FormatButton(icon: "chevron.left.forwardslash.chevron.right", help: "Code", action: onCode)
            FormatButton(icon: "link", help: "Link (⌘K)", action: onLink)
            FormatButton(icon: "highlighter", help: "Highlight", action: onHighlight)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

/// Individual format button for the inline toolbar
private struct FormatButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovered ? Color.primary.opacity(0.1) : .clear)
                )
                .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .help(help)
    }
}

/// Small vertical divider for toolbar sections
private struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }
}

// MARK: - Enhanced Block Handle (Craft-style)

/// A Craft-style drag handle with grip dots pattern
struct CraftBlockHandle: View {
    let isVisible: Bool
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 3, height: 3)
                    Circle()
                        .fill(dotColor)
                        .frame(width: 3, height: 3)
                }
            }
        }
        .frame(width: 18, height: 20)
        .contentShape(Rectangle())
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(.liquidGlassQuick, value: isVisible)
        .animation(.liquidGlassQuick, value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var dotColor: Color {
        if isHovered {
            return .primary.opacity(0.5)
        }
        return .secondary.opacity(0.4)
    }
}

// MARK: - Craft-Style Add Block Button

/// A minimal "+" button that appears between blocks on hover (Craft-style)
struct CraftAddBlockButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Left line
                Rectangle()
                    .fill(Color.primary.opacity(isHovered ? 0.15 : 0.08))
                    .frame(height: 1)

                // Center plus button
                ZStack {
                    Circle()
                        .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                        .frame(width: 20, height: 20)

                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                }
                .scaleEffect(isHovered ? 1.1 : 1.0)

                // Right line
                Rectangle()
                    .fill(Color.primary.opacity(isHovered ? 0.15 : 0.08))
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .frame(height: 20)
        .opacity(isHovered ? 1 : 0.5)
        .animation(.liquidGlassQuick, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Craft-Style Block Type Picker

/// A more visual block type picker with icons and descriptions (like Craft's "/" menu)
struct CraftBlockTypePicker: View {
    let query: String
    let onSelect: (CraftBlockType) -> Void
    let onDismiss: () -> Void
    @State private var selectedIndex = 0

    private var filteredTypes: [CraftBlockType] {
        if query.isEmpty {
            return CraftBlockType.allCases
        }
        return CraftBlockType.allCases.filter { type in
            type.displayName.localizedCaseInsensitiveContains(query) ||
            type.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("Turn into")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("esc to close")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()
                .opacity(0.5)

            if filteredTypes.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.quaternary)
                    Text("No blocks found")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                // Block types grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(Array(filteredTypes.enumerated()), id: \.element) { index, type in
                            BlockTypeCard(
                                type: type,
                                isSelected: index == selectedIndex,
                                action: { onSelect(type) }
                            )
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
    }
}

/// Individual block type card in the picker
private struct BlockTypeCard: View {
    let type: CraftBlockType
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(type.iconBackgroundColor.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: type.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(type.iconBackgroundColor)
                }

                Text(type.displayName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill((isHovered || isSelected) ? Color.accentColor.opacity(0.1) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Block types for the Craft-style picker
enum CraftBlockType: String, CaseIterable, Identifiable {
    case text, heading1, heading2, heading3
    case bulletList, numberedList, todo, toggle
    case code, quote, callout, divider
    case image, agent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .bulletList: return "Bullet List"
        case .numberedList: return "Numbered"
        case .todo: return "To-do"
        case .toggle: return "Toggle"
        case .code: return "Code"
        case .quote: return "Quote"
        case .callout: return "Callout"
        case .divider: return "Divider"
        case .image: return "Image"
        case .agent: return "Agent"
        }
    }

    var icon: String {
        switch self {
        case .text: return "text.alignleft"
        case .heading1: return "textformat.size.larger"
        case .heading2: return "textformat.size"
        case .heading3: return "textformat.size.smaller"
        case .bulletList: return "list.bullet"
        case .numberedList: return "list.number"
        case .todo: return "checkmark.square"
        case .toggle: return "chevron.right.circle"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .quote: return "text.quote"
        case .callout: return "exclamationmark.circle"
        case .divider: return "minus"
        case .image: return "photo"
        case .agent: return "sparkles"
        }
    }

    var iconBackgroundColor: Color {
        switch self {
        case .text, .heading1, .heading2, .heading3: return .blue
        case .bulletList, .numberedList, .todo: return .green
        case .toggle: return .orange
        case .code: return .orange
        case .quote: return .purple
        case .callout: return .yellow
        case .divider: return .secondary
        case .image: return .pink
        case .agent: return EditorTokens.Colors.agentAccent
        }
    }

    var keywords: [String] {
        switch self {
        case .text: return ["text", "paragraph", "p"]
        case .heading1: return ["h1", "heading", "title"]
        case .heading2: return ["h2", "subheading"]
        case .heading3: return ["h3"]
        case .bulletList: return ["bullet", "list", "ul", "-"]
        case .numberedList: return ["number", "ol", "1."]
        case .todo: return ["todo", "task", "checkbox", "[]"]
        case .toggle: return ["toggle", "collapse", "expand"]
        case .code: return ["code", "```", "programming"]
        case .quote: return ["quote", "blockquote", ">"]
        case .callout: return ["callout", "note", "tip", "warning"]
        case .divider: return ["divider", "hr", "---", "line"]
        case .image: return ["image", "img", "photo", "picture"]
        case .agent: return ["agent", "ai", "sparkle", "assistant"]
        }
    }
}

// MARK: - Block Insertion Indicator

/// A visual indicator showing where a dragged block will be inserted
struct BlockInsertionIndicator: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)

            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
        }
        .shadow(color: Color.accentColor.opacity(0.3), radius: 4)
    }
}

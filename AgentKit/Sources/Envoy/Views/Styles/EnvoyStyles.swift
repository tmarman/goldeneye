//
//  EnvoyStyles.swift
//  Envoy
//
//  Beautiful, consistent UI styles for the Envoy app.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Platform Color Alias

#if os(macOS)
typealias PlatformColor = NSColor
#else
typealias PlatformColor = UIColor
#endif

// MARK: - Color Extensions

extension Color {
    /// Initialize color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Window background color for the current platform
    static var windowBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    /// Text background color for the current platform
    static var textBackground: Color {
        #if os(macOS)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    /// Control background color for the current platform
    static var controlBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }

    /// Subtle button background - light in light mode, darker in dark mode
    static var buttonBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor).opacity(0.8)
        #else
        return Color(uiColor: .systemGray6)
        #endif
    }

    /// Hover state background
    static var hoverBackground: Color {
        Color.primary.opacity(0.08)
    }

    /// Card background with subtle elevation
    static var cardBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

// MARK: - Button Styles

/// Subtle opacity reduction on press
struct ReducedOpacityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Rounded rectangle button with hover state
struct RoundedButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(configuration.isPressed ? Color.hoverBackground : Color.buttonBackground)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Floating action button style
struct FloatingButtonStyle: ButtonStyle {
    var size: CGFloat = 36
    var iconSize: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: iconSize))
            .foregroundColor(.primary)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color.hoverBackground : Color.buttonBackground)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Pill-shaped button style (for tags and chips)
struct PillButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    var selectedColor: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? selectedColor : Color.buttonBackground)
            )
            .foregroundColor(isSelected ? .white : .primary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Menu Styles

/// Rounded rectangle menu style
struct RoundedMenuStyle: MenuStyle {
    var backgroundColor: Color = .buttonBackground
    var foregroundColor: Color = .primary
    var cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .menuStyle(.borderlessButton)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension MenuStyle where Self == RoundedMenuStyle {
    static func rounded(
        backgroundColor: Color = .buttonBackground,
        foregroundColor: Color = .primary,
        cornerRadius: CGFloat = 10
    ) -> RoundedMenuStyle {
        RoundedMenuStyle(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            cornerRadius: cornerRadius
        )
    }
}

// MARK: - Text Field Styles

/// Rounded text field with optional icon and clear button
struct RoundedTextFieldStyle: TextFieldStyle {
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = 10
    var icon: String? = nil
    var showClearButton: Bool = false
    @Binding var text: String

    #if os(macOS)
    var backgroundColor: Color = Color(.controlBackgroundColor)
    #else
    var backgroundColor: Color = Color(.systemBackground)
    #endif

    func _body(configuration: TextField<Self._Label>) -> some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            }

            configuration
                #if os(macOS)
                .textFieldStyle(.plain)
                #endif

            if showClearButton && !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(padding)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Card Styles

/// A card container with rounded corners and subtle shadow
struct CardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = 16
    var showBorder: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(showBorder ? Color.secondary.opacity(0.1) : Color.clear, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle(
        cornerRadius: CGFloat = 12,
        padding: CGFloat = 16,
        showBorder: Bool = true
    ) -> some View {
        modifier(CardModifier(
            cornerRadius: cornerRadius,
            padding: padding,
            showBorder: showBorder
        ))
    }
}

/// Hoverable card with highlight effect
struct HoverableCardModifier: ViewModifier {
    @State private var isHovered = false
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isHovered ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func hoverableCardStyle(
        cornerRadius: CGFloat = 12,
        padding: CGFloat = 16
    ) -> some View {
        modifier(HoverableCardModifier(
            cornerRadius: cornerRadius,
            padding: padding
        ))
    }
}

// MARK: - Input Field Button Style

/// Consistent styling for buttons in input fields
struct InputFieldButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 28)
            .background(Color.buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .fixedSize()
    }
}

extension View {
    func inputFieldButtonStyle() -> some View {
        modifier(InputFieldButtonModifier())
    }
}

// MARK: - Status Indicator

/// A colored status indicator dot
struct StatusIndicator: View {
    enum Status {
        case success
        case warning
        case error
        case inactive
        case loading

        var color: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            case .inactive: return .secondary
            case .loading: return .accentColor
            }
        }
    }

    let status: Status
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
    }
}

// MARK: - Badge Style

/// A small badge for counts or status
struct BadgeModifier: ViewModifier {
    var color: Color = .accentColor

    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

extension View {
    func badgeStyle(color: Color = .accentColor) -> some View {
        modifier(BadgeModifier(color: color))
    }
}

// NOTE: ShimmerModifier is defined in LiquidGlassStyle.swift

// MARK: - Search Field

/// A beautiful search field with icon and clear button
struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var cornerRadius: CGFloat = 12

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            TextField(placeholder, text: $text)
                #if os(macOS)
                .textFieldStyle(.plain)
                #endif

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Section Header

/// A consistent section header with optional action button
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil

    var body: some View {
        HStack {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let action = action, let actionLabel = actionLabel {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Info Banner

/// An informational banner with icon, title, and description
struct InfoBanner: View {
    let title: String
    let description: String
    var systemImage: String = "info.circle"
    var color: Color = .blue
    @State private var isExpanded = true

    var body: some View {
        if isExpanded {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    withAnimation {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - Feature Pills

/// Horizontal scrolling feature badges
struct FeaturePills: View {
    let features: [(String, String, Color)] // (label, icon, color)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(features, id: \.0) { feature in
                    HStack(spacing: 4) {
                        Image(systemName: feature.1)
                            .font(.caption2)
                        Text(feature.0)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(feature.2.opacity(0.15))
                    .foregroundStyle(feature.2)
                    .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Loading Overlay

/// A loading overlay with optional message
struct LoadingOverlay: View {
    var message: String? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)

                if let message = message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

// MARK: - Styled Empty State

/// A beautiful empty state view with action button support
struct StyledEmptyState: View {
    let systemImage: String
    let title: String
    let description: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(description)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Previews

#Preview("Button Styles") {
    VStack(spacing: 20) {
        Button("Reduced Opacity") {}
            .buttonStyle(ReducedOpacityButtonStyle())

        Button {
        } label: {
            Label("Rounded Button", systemImage: "star")
        }
        .buttonStyle(RoundedButtonStyle())

        Button {
        } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(FloatingButtonStyle())

        HStack {
            Button("Selected") {}
                .buttonStyle(PillButtonStyle(isSelected: true))
            Button("Not Selected") {}
                .buttonStyle(PillButtonStyle(isSelected: false))
        }
    }
    .padding()
}

#Preview("Card Styles") {
    VStack(spacing: 20) {
        Text("Standard Card")
            .cardStyle()

        Text("Hoverable Card")
            .hoverableCardStyle()

        HStack {
            Text("5")
                .badgeStyle(color: .blue)
            Text("New")
                .badgeStyle(color: .green)
            Text("Error")
                .badgeStyle(color: .red)
        }
    }
    .padding()
}

#Preview("Status Indicators") {
    HStack(spacing: 16) {
        StatusIndicator(status: .success)
        StatusIndicator(status: .warning)
        StatusIndicator(status: .error)
        StatusIndicator(status: .inactive)
        StatusIndicator(status: .loading)
    }
    .padding()
}

#Preview("Search Field") {
    @Previewable @State var searchText = ""
    VStack(spacing: 16) {
        SearchField(text: $searchText)
        SearchField(text: .constant("hello world"), placeholder: "Filter models...")
    }
    .padding()
}

#Preview("Section Header") {
    VStack(spacing: 16) {
        SectionHeader(title: "Model Families")
        SectionHeader(title: "Storage", subtitle: "Manage downloaded models")
        SectionHeader(
            title: "Providers",
            systemImage: "server.rack",
            action: {},
            actionLabel: "Add New"
        )
    }
    .padding()
}

#Preview("Info Banner") {
    VStack(spacing: 16) {
        InfoBanner(
            title: "On-Device AI",
            description: "Run powerful AI models locally on Apple Silicon with complete privacy.",
            systemImage: "apple.logo",
            color: .blue
        )
        InfoBanner(
            title: "API Key Required",
            description: "Enter your API key to use this provider.",
            systemImage: "key.fill",
            color: .orange
        )
    }
    .padding()
}

#Preview("Feature Pills") {
    FeaturePills(features: [
        ("Privacy", "lock.shield.fill", .green),
        ("Offline", "wifi.slash", .blue),
        ("No API Costs", "dollarsign.circle.fill", .orange)
    ])
    .padding()
}

#Preview("Styled Empty State") {
    VStack(spacing: 32) {
        StyledEmptyState(
            systemImage: "server.rack",
            title: "No Providers",
            description: "Add a provider to start using AI models",
            actionTitle: "Add Provider",
            action: {}
        )
        StyledEmptyState(
            systemImage: "magnifyingglass",
            title: "No Results",
            description: "Try a different search term"
        )
    }
}

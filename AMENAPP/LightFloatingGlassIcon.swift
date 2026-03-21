import SwiftUI

// MARK: - Light Glass Icon
// Matches: white frosted bubble + vivid 3D accent on soft gray/white bg
// Use for: onboarding, empty states, feature headers in light mode screens

struct LightFloatingGlassIcon: View {
    let personality: LightIconPersonality
    var size: CGFloat = 100

    @State private var floating = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Soft drop shadow pool beneath
            Ellipse()
                .fill(accentColor.opacity(0.12))
                .frame(width: size * 1.3, height: size * 0.28)
                .blur(radius: 10)
                .offset(y: size * 0.56)
                .opacity(appeared ? 1 : 0)

            ZStack(alignment: .bottomTrailing) {
                // White frosted bubble (left)
                lightBubble
                    .frame(width: size * 0.80, height: size * 0.50)
                    .offset(x: -size * 0.08, y: size * 0.08)

                // Vivid 3D accent (right, overlapping)
                accentShape
                    .frame(width: size * 0.54, height: size * 0.54)
                    .offset(x: size * 0.05, y: -size * 0.02)
            }
            .frame(width: size, height: size)
            .offset(y: floating ? -6 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.70)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
    }

    // MARK: White Glass Bubble

    private var lightBubble: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.82))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )

            // Subtle blue tint from accent bleeding in
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.06),
                            Color.clear
                        ],
                        startPoint: .bottomTrailing,
                        endPoint: .topLeading
                    )
                )

            // Top-left inner highlight
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.90), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .init(x: 0.5, y: 0.4)
                    )
                )

            // Three dots
            HStack(spacing: size * 0.058) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(dotFill(i))
                        .frame(width: size * 0.072, height: size * 0.072)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        .shadow(color: accentColor.opacity(0.08), radius: 8, x: 2, y: 4)
    }

    private func dotFill(_ i: Int) -> Color {
        switch i {
        case 0: return Color(white: 0.76)
        case 1: return Color(white: 0.82)
        default: return accentColor.opacity(0.75)
        }
    }

    // MARK: Accent Shape (per personality)

    @ViewBuilder
    private var accentShape: some View {
        switch personality {
        case .berean:    LightMagGlass(size: size, accent: accentColor)
        case .covenant:  LightBarChart(size: size, accent: accentColor)
        case .shepherds: LightShield(size: size, accent: accentColor)
        case .prayer:    LightHands(size: size, accent: accentColor)
        case .testimony: LightQuote(size: size, accent: accentColor)
        case .living:    LightSparkle(size: size, accent: accentColor)
        }
    }

    private var accentColor: Color {
        switch personality {
        case .berean:    return Color(red: 0.20, green: 0.42, blue: 0.98)
        case .covenant:  return Color(red: 0.08, green: 0.62, blue: 0.92)
        case .shepherds: return Color(red: 0.20, green: 0.72, blue: 0.54)
        case .prayer:    return Color(red: 0.46, green: 0.28, blue: 0.95)
        case .testimony: return Color(red: 0.95, green: 0.55, blue: 0.18)
        case .living:    return Color(red: 0.55, green: 0.28, blue: 0.95)
        }
    }
}

// MARK: - Personality

enum LightIconPersonality {
    case berean, covenant, shepherds, prayer, testimony, living
}

// MARK: - Individual Accent Icons

private struct LightMagGlass: View {
    let size: CGFloat; let accent: Color
    var body: some View {
        ZStack {
            // Glow base
            Circle()
                .fill(accent.opacity(0.12))
                .frame(width: size * 0.52, height: size * 0.52)
                .blur(radius: 6)

            // Ring
            Circle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.25), accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.36, height: size * 0.36)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .frame(width: size * 0.22, height: size * 0.22)
                )
                .offset(x: -size * 0.04, y: -size * 0.04)

            // Handle
            RoundedRectangle(cornerRadius: size * 0.04)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.10, height: size * 0.22)
                .rotationEffect(.degrees(45))
                .offset(x: size * 0.14, y: size * 0.14)
        }
        .shadow(color: accent.opacity(0.30), radius: 10, x: 0, y: 5)
    }
}

private struct LightBarChart: View {
    let size: CGFloat; let accent: Color
    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.10))
                .frame(width: size * 0.52, height: size * 0.52)
                .blur(radius: 6)

            RoundedRectangle(cornerRadius: size * 0.08)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.85), accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.44, height: size * 0.44)
                .overlay(
                    HStack(alignment: .bottom, spacing: size * 0.032) {
                        ForEach([0.38, 0.60, 1.0, 0.72], id: \.self) { h in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.5 + h * 0.5))
                                .frame(width: size * 0.058, height: size * 0.22 * h)
                        }
                    }
                )
        }
        .shadow(color: accent.opacity(0.28), radius: 10, x: 0, y: 5)
    }
}

private struct LightShield: View {
    let size: CGFloat; let accent: Color
    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.10))
                .frame(width: size * 0.52, height: size * 0.52)
                .blur(radius: 6)

            ShieldShapeLight()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.85), accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.38, height: size * 0.43)
                .overlay(
                    Path { p in
                        let s = size * 0.42
                        p.move(to: CGPoint(x: s * 0.28, y: s * 0.52))
                        p.addLine(to: CGPoint(x: s * 0.44, y: s * 0.68))
                        p.addLine(to: CGPoint(x: s * 0.72, y: s * 0.36))
                    }
                    .stroke(Color.white.opacity(0.95),
                            style: StrokeStyle(lineWidth: size * 0.042, lineCap: .round, lineJoin: .round))
                )
        }
        .shadow(color: accent.opacity(0.28), radius: 10, x: 0, y: 5)
    }
}

private struct LightHands: View {
    let size: CGFloat; let accent: Color
    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.10))
                .frame(width: size * 0.52, height: size * 0.52)
                .blur(radius: 6)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.85), accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.44, height: size * 0.44)
                .overlay(
                    Image(systemName: "hands.sparkles.fill")
                        .font(.system(size: size * 0.20))
                        .foregroundColor(.white.opacity(0.95))
                )
        }
        .shadow(color: accent.opacity(0.30), radius: 10, x: 0, y: 5)
    }
}

private struct LightQuote: View {
    let size: CGFloat; let accent: Color
    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.10))
                .frame(width: size * 0.52, height: size * 0.52)
                .blur(radius: 6)

            RoundedRectangle(cornerRadius: size * 0.10)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.85), accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.44, height: size * 0.44)
                .overlay(
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: size * 0.22))
                        .foregroundColor(.white.opacity(0.95))
                )
        }
        .shadow(color: accent.opacity(0.28), radius: 10, x: 0, y: 5)
    }
}

private struct LightSparkle: View {
    let size: CGFloat; let accent: Color
    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.10))
                .frame(width: size * 0.52, height: size * 0.52)
                .blur(radius: 6)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.80), accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.44, height: size * 0.44)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.20))
                        .foregroundColor(.white.opacity(0.95))
                )
        }
        .shadow(color: accent.opacity(0.28), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Shield Path (light)

private struct ShieldShapeLight: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width; let h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addLine(to: CGPoint(x: w, y: h * 0.22))
        p.addLine(to: CGPoint(x: w, y: h * 0.55))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h),
                   control1: CGPoint(x: w, y: h * 0.85),
                   control2: CGPoint(x: w * 0.75, y: h))
        p.addCurve(to: CGPoint(x: 0, y: h * 0.55),
                   control1: CGPoint(x: w * 0.25, y: h),
                   control2: CGPoint(x: 0, y: h * 0.85))
        p.addLine(to: CGPoint(x: 0, y: h * 0.22))
        p.closeSubpath()
        return p
    }
}

// MARK: - Light Empty State

struct LightCreatorEmptyState: View {
    let personality: LightIconPersonality
    let title: String
    let subtitle: String
    var actionLabel: String? = nil
    var onAction: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            LightFloatingGlassIcon(personality: personality, size: 108)
                .padding(.bottom, 32)

            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundColor(Color(white: 0.10))
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text(subtitle)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(Color(white: 0.50))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 36)

            if let label = actionLabel, let action = onAction {
                Button(action: action) {
                    Text(label)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 13)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.20, green: 0.42, blue: 0.98))
                        )
                        .shadow(color: Color(red: 0.20, green: 0.42, blue: 0.98).opacity(0.30),
                                radius: 12, x: 0, y: 5)
                }
                .padding(.top, 28)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
        .background(Color(red: 0.95, green: 0.96, blue: 0.98))
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.95)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.76).delay(0.08)) {
                appeared = true
            }
        }
    }
}

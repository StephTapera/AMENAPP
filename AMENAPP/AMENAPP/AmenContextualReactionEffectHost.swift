import SwiftUI

struct AmenContextualReactionEffectHost: View {
    let presentation: AmenContextualReactionPresentation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let presentation {
            ZStack {
                effect(for: presentation.result)
                VStack {
                    AmenContextualReactionChip(text: presentation.result.microcopy)
                    Spacer()
                }
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func effect(for result: AmenContextualReactionResult) -> some View {
        switch result.effectType {
        case .amenPulse, .heartMorph, .seasonalIconMorph:
            AmenPulseEffect(reduceMotion: reduceMotion)
        case .prayerGlow:
            PrayerGlowEffect(reduceMotion: reduceMotion)
        case .scriptureShimmer:
            ScriptureShimmerEffect(reduceMotion: reduceMotion)
        case .gratitudeBloom:
            GratitudeBloomEffect(reduceMotion: reduceMotion)
        case .shareWithCareChip, .saveForStudyChip:
            EmptyView()
        case .hiddenReactionRing, .softFirework, .none:
            EmptyView()
        }
    }
}

private struct AmenContextualReactionChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.black.opacity(0.84))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).fill(Color.white.opacity(0.9)))
            )
            .overlay(Capsule(style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 0.8))
            .padding(.top, 10)
    }
}

private struct AmenPulseEffect: View {
    let reduceMotion: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.08), lineWidth: 16)
                .scaleEffect(animate && !reduceMotion ? 1.22 : 0.7)
                .opacity(animate ? 0 : 0.85)
                .frame(width: 116, height: 116)

            Text("Amen")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.7))
                .offset(y: animate && !reduceMotion ? -22 : 0)
                .opacity(animate ? 0 : 1)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.9)) {
                animate = true
            }
        }
    }
}

private struct PrayerGlowEffect: View {
    let reduceMotion: Bool
    @State private var glow = false

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.04))
                .frame(width: 176, height: 68)
                .shadow(color: Color.black.opacity(glow ? 0.12 : 0.03), radius: glow ? 18 : 8, y: 0)

            if reduceMotion {
                Text("Prayer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.55))
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.black.opacity(0.16))
                            .frame(width: 8, height: 8)
                            .offset(y: glow ? -18 : 10)
                            .opacity(glow ? 0 : 1)
                            .animation(.easeOut(duration: 0.9).delay(Double(index) * 0.08), value: glow)
                    }
                }
            }
        }
        .onAppear { glow = true }
    }
}

private struct ScriptureShimmerEffect: View {
    let reduceMotion: Bool
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.clear)
                .overlay(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.92), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: reduceMotion ? 28 : 84)
                    .offset(x: phase * proxy.size.width)
                )
                .mask(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: reduceMotion ? 0.3 : 0.9)) {
                phase = 1
            }
        }
    }
}

private struct GratitudeBloomEffect: View {
    let reduceMotion: Bool
    @State private var bloom = false

    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [Color.black.opacity(bloom ? 0.05 : 0.01), .clear],
                    center: .center,
                    startRadius: 8,
                    endRadius: bloom ? (reduceMotion ? 88 : 160) : 40
                )
            )
            .onAppear {
                withAnimation(.easeOut(duration: reduceMotion ? 0.25 : 0.8)) {
                    bloom = true
                }
            }
    }
}

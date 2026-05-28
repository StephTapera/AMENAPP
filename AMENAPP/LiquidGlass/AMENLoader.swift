import SwiftUI

// MARK: - AMENLoader
// Lemniscate-of-Bernoulli particle loader — the AMEN design system's single
// animated indeterminate indicator. N dots orbit the figure-eight path with a
// comet-trail effect: leading dot is fullest/largest; tail fades. Driven by one
// TimelineView + Canvas redraw per display frame — no per-particle withAnimation calls.
//
// Default tint is Color.primary (black in light mode, white in dark mode).
// Pass a brand override (AmenTheme.Colors.amenGold, etc.) when the surface calls for it.

struct AMENLoader: View {

    // MARK: - Configuration

    var particleCount: Int = 24
    /// Overall bounding width. Height is ~40% of this value to match the lemniscate's natural 2.5:1 aspect ratio.
    var size: CGFloat = 80
    /// Particle color. Defaults to Color.primary — adaptive to color scheme.
    var tint: Color = .primary
    var speed: Double = 1.0
    var caption: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 10) {
            if reduceMotion {
                pulseVariant
            } else {
                lemniscateCanvas
            }
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(caption ?? "Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Lemniscate Canvas

    // Single Canvas pass driven by TimelineView — N particles, one redraw per frame.
    private var lemniscateCanvas: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, canvasSize in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate * speed
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2
                // Scale 'a' so the widest reach (±a) fits within the frame with a small pad.
                let a = canvasSize.width * 0.44

                for i in 0..<particleCount {
                    // Each particle has its own t offset; elapsed advances the whole comet.
                    let t = (Double(i) / Double(particleCount)) * (2 * .pi) + elapsed
                    let pt = lemniscate(t: t, a: a, cx: cx, cy: cy)

                    // i=0 → comet head (full brightness + size). Higher i → fainter + smaller tail.
                    let trail = Double(i) / Double(particleCount)
                    let opacity = max(0.06, 1.0 - trail * 0.94)
                    let r = max(1.5, (1.0 - trail * 0.65) * maxRadius)

                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    context.fill(Circle().path(in: rect), with: .color(tint.opacity(opacity)))
                }
            }
            // Natural lemniscate aspect ≈ 2.5:1 (width:height). Add vertical pad → 0.42× factor.
            .frame(width: size, height: size * 0.42)
        }
    }

    /// Max dot radius for the head of the comet; tail dots scale down from this.
    private var maxRadius: CGFloat { max(2.5, size / 17) }

    // Lemniscate of Bernoulli parametric form:
    //   x(t) = a·cos(t) / (1 + sin²t)
    //   y(t) = a·sin(t)·cos(t) / (1 + sin²t)
    private func lemniscate(t: Double, a: Double, cx: Double, cy: Double) -> CGPoint {
        let s = sin(t), c = cos(t)
        let d = 1.0 + s * s
        return CGPoint(x: cx + a * c / d, y: cy + a * s * c / d)
    }

    // MARK: - Reduce Motion fallback: three calm pulsing dots

    private var pulseVariant: some View {
        HStack(spacing: size / 10) {
            ForEach(0..<3, id: \.self) { i in
                AMENLoaderPulsingDot(tint: tint, radius: maxRadius, delay: Double(i) * 0.22)
            }
        }
        .frame(width: size, height: size * 0.42, alignment: .center)
    }
}

// MARK: - AMENLoaderPulsingDot (Reduce Motion fallback only)

private struct AMENLoaderPulsingDot: View {
    let tint: Color
    let radius: CGFloat
    let delay: Double

    @State private var pulsed = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(pulsed ? 1.0 : 0.5)
            .opacity(pulsed ? 1.0 : 0.3)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.65)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    pulsed = true
                }
            }
    }
}

// MARK: - AMENLoader convenience variants
//
// Call sites stay one-liners:
//   AMENLoader.fullScreen()
//   AMENLoader.fullScreen(caption: "loading")
//   AMENLoader.inline
//   AMENLoader.button
//   .amenLoadingOverlay(isVisible: isProcessing, caption: "processing")

extension AMENLoader {

    // Full-screen blocking loader.
    // Adaptive background: Color(.systemBackground) → white in light mode, near-black in dark.
    // Uses the full safe-area inset; put this at the ZStack root, not inside a VStack.
    static func fullScreen(caption: String = "loading") -> some View {
        ZStack {
            Color(.systemBackground)
            AMENLoader(size: 100, caption: caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    /// Small inline indicator for rows, section footers, and pagination tails.
    static var inline: AMENLoader {
        AMENLoader(particleCount: 18, size: 44)
    }

    /// Button-sized: swap this in for a button label while a request is in flight.
    static var button: AMENLoader {
        AMENLoader(particleCount: 12, size: 34)
    }
}

// MARK: - AMENLoaderOverlay
// Overlay variant: sits on top of existing content over an ultraThinMaterial scrim.
// Blocks all interaction behind it. Degrades to a solid semi-opaque fill when
// Reduce Transparency is on (the material itself would already be opaque, but
// this guarantees a clearly visible backing even on older rendering paths).
//
// Preferred usage: .amenLoadingOverlay(isVisible:caption:) view modifier below.
// Direct usage is also fine for ZStack-based screens.

struct AMENLoaderOverlay: View {
    var caption: String? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // Scrim layer — blocks taps on content behind.
            Group {
                if reduceTransparency {
                    Color(.systemBackground).opacity(0.90)
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(true)

            AMENLoader(size: 80, caption: caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(caption ?? "Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - amenLoadingOverlay view modifier
//
// Usage:
//   myView
//     .amenLoadingOverlay(isVisible: isProcessing, caption: "processing")
//
// The overlay is guaranteed to appear and disappear on BOTH success and failure paths
// as long as the binding is cleared on all exit paths of the calling view.

extension View {
    func amenLoadingOverlay(isVisible: Bool, caption: String? = nil) -> some View {
        overlay {
            if isVisible {
                AMENLoaderOverlay(caption: caption)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: LiquidGlassTokens.motionFast), value: isVisible)
    }
}

// MARK: - Previews

#Preview("Light mode — all variants") {
    ScrollView {
        VStack(spacing: 40) {
            Group {
                Text("Default (size 80)").font(.caption).foregroundStyle(.secondary)
                AMENLoader(size: 80, caption: "loading")
            }

            Group {
                Text("Brand tint — amenGold").font(.caption).foregroundStyle(.secondary)
                AMENLoader(size: 80, tint: AmenTheme.Colors.amenGold, caption: "thinking...")
            }

            Group {
                Text("Inline (size 44, no caption)").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text("More posts")
                    AMENLoader.inline
                }
            }

            Group {
                Text("Button (size 34)").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Text("Submitting")
                    AMENLoader.button
                }
            }

            Group {
                Text("Large (size 120)").font(.caption).foregroundStyle(.secondary)
                AMENLoader(size: 120, caption: "loading")
            }
        }
        .padding(32)
    }
    .preferredColorScheme(.light)
}

#Preview("Dark mode — all variants") {
    ScrollView {
        VStack(spacing: 40) {
            Group {
                Text("Default (size 80)").font(.caption).foregroundStyle(.secondary)
                AMENLoader(size: 80, caption: "loading")
            }

            Group {
                Text("Brand tint — amenGold").font(.caption).foregroundStyle(.secondary)
                AMENLoader(size: 80, tint: AmenTheme.Colors.amenGold, caption: "thinking...")
            }

            Group {
                Text("Inline").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text("More posts")
                    AMENLoader.inline
                }
            }

            Group {
                Text("Button").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Text("Submitting")
                    AMENLoader.button
                }
            }
        }
        .padding(32)
    }
    .preferredColorScheme(.dark)
}

#Preview("Full screen — light") {
    AMENLoader.fullScreen(caption: "loading")
        .preferredColorScheme(.light)
}

#Preview("Full screen — dark") {
    AMENLoader.fullScreen(caption: "loading")
        .preferredColorScheme(.dark)
}

#Preview("Overlay — dark") {
    ZStack {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16).fill(Color.blue.opacity(0.25)).frame(height: 120)
            RoundedRectangle(cornerRadius: 16).fill(Color.purple.opacity(0.25)).frame(height: 80)
            Text("Content behind overlay").font(.headline)
        }
        .padding()
        .amenLoadingOverlay(isVisible: true, caption: "processing")
    }
    .preferredColorScheme(.dark)
}

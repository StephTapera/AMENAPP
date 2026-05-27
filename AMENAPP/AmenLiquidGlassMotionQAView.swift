import SwiftUI

struct AmenLiquidGlassMotionQAView: View {
    @State private var trustState: AmenTrustMotionState = .verified
    @State private var density: CGFloat = 0.55
    @State private var activePresence = true
    @State private var unsafeContent = false
    @State private var expanded = false

    private var signals: AmenMotionSignals {
        var trustSignals = trustState.signals
        trustSignals.contentDensity = density
        trustSignals.activeUserCount = activePresence ? 4 : 0
        trustSignals.typingUserCount = activePresence ? 1 : 0
        trustSignals.prayingUserCount = activePresence ? 2 : 0
        trustSignals.viewerCount = activePresence ? 7 : 0
        trustSignals.hasUnsafeContent = unsafeContent || trustSignals.hasUnsafeContent
        trustSignals.glassSurfaceCount = density > 0.8 ? 14 : 6
        return trustSignals
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    controls

                    AmenLiquidGlassMorphContainer(spacing: 18) { namespace in
                        VStack(alignment: .leading, spacing: 14) {
                            qaCard(
                                title: "Navigation",
                                subtitle: "Scroll-aware liquid navigation chrome",
                                role: .navigation,
                                namespace: namespace,
                                id: "navigation"
                            )

                            qaCard(
                                title: "Feed Card",
                                subtitle: "Lift, safety de-emphasis, and density fallback",
                                role: .feedCard,
                                namespace: namespace,
                                id: "feed"
                            )

                            qaCard(
                                title: "Presence",
                                subtitle: "Active, typing, praying, and viewing signals",
                                role: .presenceCluster,
                                namespace: namespace,
                                id: "presence"
                            )

                            qaCard(
                                title: "Prayer Circle",
                                subtitle: "Calm repeating motion when allowed",
                                role: .prayerCircle,
                                namespace: namespace,
                                id: "prayer"
                            )

                            qaCard(
                                title: "Safety Badge",
                                subtitle: "Verified, review, and unsafe trust states",
                                role: .safetyBadge,
                                namespace: namespace,
                                id: "safety"
                            )
                        }
                    }
                }
                .padding(20)
            }
            .amenMotionSignals(signals)
            .amenRuntimeMotionMonitored()
            .navigationTitle("Liquid Glass QA")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Trust", selection: $trustState) {
                Text("Verified").tag(AmenTrustMotionState.verified)
                Text("Review").tag(AmenTrustMotionState.needsReview)
                Text("Unsafe").tag(AmenTrustMotionState.unsafe)
            }
            .pickerStyle(.segmented)

            Toggle("Presence", isOn: $activePresence)
            Toggle("Unsafe content", isOn: $unsafeContent)
            Toggle("Expanded state", isOn: $expanded)

            Slider(value: $density, in: 0...1) {
                Text("Density")
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .amenLiquidGlassSocialMotion(.aiSummary, context: AmenLiquidGlassSocialMotionContext(isActive: true, isExpanded: true))
    }

    private func qaCard(
        title: String,
        subtitle: String,
        role: AmenLiquidGlassSurfaceRole,
        namespace: Namespace.ID,
        id: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .amenGlassMorphID(id, namespace: namespace, role: role)
        .amenLiquidGlassSocialMotion(
            role,
            context: AmenLiquidGlassSocialMotionContext(
                contentDensity: density,
                emotionalIntensity: activePresence ? 0.35 : 0,
                isActive: activePresence,
                isSafe: !unsafeContent && trustState != .unsafe,
                isExpanded: expanded
            )
        )
    }
}

#Preview {
    AmenLiquidGlassMotionQAView()
}

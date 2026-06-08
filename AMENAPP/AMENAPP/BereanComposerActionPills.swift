import SwiftUI
import FirebaseAnalytics

// MARK: - Composer Action Pill Row
//
// Shows 0–2 contextual floating pills above the Berean composer.
// Pills appear only when the classifier detects a relevant signal.
// Sensitive topics suppress all pills.

struct BereanComposerActionPillRow: View {
    let pills: [BereanComposerPill]
    let onTap: (BereanComposerPill) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var appeared = false

    var body: some View {
        if pills.isEmpty { EmptyView() } else {
            HStack(spacing: 8) {
                ForEach(pills) { pill in
                    pillButton(pill)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .onAppear {
                withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.78).delay(0.05)) {
                    appeared = true
                }
                Analytics.logEvent("berean_summary_pill_shown", parameters: [
                    "pill_count": pills.count,
                    "pills": pills.map(\.rawValue).joined(separator: ",")
                ])
            }
            .onDisappear { appeared = false }
        }
    }

    private func pillButton(_ pill: BereanComposerPill) -> some View {
        Button {
            Analytics.logEvent(pill.analyticsKey, parameters: ["pill": pill.rawValue])
            onTap(pill)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: pill.icon)
                    .font(.systemScaled(12, weight: .medium))
                Text(pill.rawValue)
                    .font(.systemScaled(13, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Shadow before glass so it renders under the specular rim.
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
            .background { if reduceTransparency { Capsule().fill(Color(.systemBackground)) } }
            .amenGlassEffect(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pill.rawValue)
        .accessibilityHint("Double tap to use this suggestion")
    }
}

// MARK: - Thinking State Banner

struct BereanThinkingStateBanner: View {
    let step: BereanThinkingStep
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 8) {
            if !reduceMotion {
                BereanThinkingDots()
            } else {
                Image(systemName: "ellipsis")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(step.rawValue)
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: step)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Solid fallback when user has opted out of transparency
        .background {
            if reduceTransparency {
                Capsule(style: .continuous)
                    .fill(Color(.systemBackground))
            }
        }
        // Shadow before glass so it renders under the specular rim.
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .amenGlassEffect(in: Capsule())
        .accessibilityLabel(step.rawValue)
    }
}

// MARK: - Three-dot animated thinking indicator

struct BereanThinkingDots: View {
    @State private var phases: [Double] = [0, 0.33, 0.66]
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 5, height: 5)
                    .scaleEffect(1.0 + 0.4 * sin(phases[i] * .pi * 2))
                    .opacity(0.5 + 0.5 * sin(phases[i] * .pi * 2))
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                for i in 0..<3 {
                    phases[i] = fmod(phases[i] + 0.12, 1.0)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Simplified Prompt Preview (Flow 2)

struct BereanSimplifiedPromptPreview: View {
    let simplified: BereanSimplifiedPrompt
    let onAskBerean: () -> Void
    let onEdit: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Original collapsed
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Original question")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(simplified.originalText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    Divider()

                    // Simplified
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Simplified")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(simplified.simplifiedText)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }

                    // Key themes
                    if !simplified.keyThemes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Key themes")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            PillsFlowLayout(spacing: 8) {
                                ForEach(simplified.keyThemes, id: \.self) { theme in
                                    Text(theme)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.black.opacity(0.06), in: Capsule())
                                }
                            }
                        }
                    }

                    // Study angles
                    if !simplified.studyAngles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Study angles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(simplified.studyAngles, id: \.self) { angle in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 2)
                                    Text(angle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Actions
                    VStack(spacing: 10) {
                        Button {
                            onAskBerean()
                            dismiss()
                        } label: {
                            Label("Ask Berean", systemImage: "checkmark.shield")
                                .font(.body.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)

                        HStack(spacing: 12) {
                            Button("Edit summary") { onEdit(); dismiss() }
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Button("Cancel") { onCancel(); dismiss() }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .navigationTitle("Before you ask…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onAskBerean(); dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(reduceTransparency ? .thickMaterial : .regularMaterial)
    }
}

// MARK: - Simple flow layout for chips

struct PillsFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

import SwiftUI
import FirebaseAnalytics

// MARK: - Sunday Rest Mode Sheet
// Displayed when a user taps a restricted route during Lord's Day Mode.
// Liquid Glass design: white background, black text, thin blur material, capsule buttons.
// No shame language, no warning colours. Calm and worship-centered.

struct SundayRestModeSheet: View {

    @ObservedObject private var gate = RestModeGate.shared

    var onFindChurch: () -> Void
    var onChurchNotes: () -> Void
    var onDailyVerse: () -> Void
    var onPrayerRequest: () -> Void
    var onDismiss: () -> Void

    @State private var showOverrideFlow = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 32)
                        .padding(.bottom, 24)

                    availableActions
                        .padding(.horizontal, 24)

                    Divider()
                        .padding(.vertical, 24)
                        .padding(.horizontal, 24)

                    pausedSection
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                    if gate.policy?.allowTemporaryOverride == true {
                        overrideButton
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        .sheet(isPresented: $showOverrideFlow) {
            RestModeOverrideFlowSheet(onOverrideGranted: onDismiss)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .onAppear {
            Analytics.logEvent("rest_mode_home_viewed", parameters: [:])
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars")
                .font(.systemScaled(36, weight: .light))
                .foregroundStyle(.primary)

            Text(gate.activeName)
                .font(AMENFont.semiBold(22))
                .foregroundStyle(.primary)

            Text("Amen is simplified today to help you\nfocus on worship, rest, and reflection.")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
    }

    private var availableActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available today")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .kerning(0.6)

            RestModeActionRow(
                icon: "mappin.and.ellipse",
                title: "Find a Church",
                subtitle: "Discover services near you"
            ) {
                Analytics.logEvent("find_church_opened_from_rest_mode", parameters: [:])
                onFindChurch()
                onDismiss()
            }

            RestModeActionRow(
                icon: "note.text",
                title: "Church Notes",
                subtitle: "Capture today's sermon"
            ) {
                Analytics.logEvent("church_notes_opened_from_rest_mode", parameters: [:])
                onChurchNotes()
                onDismiss()
            }

            RestModeActionRow(
                icon: "book.closed",
                title: "Today's Verse",
                subtitle: "Read and reflect"
            ) {
                onDailyVerse()
                onDismiss()
            }

            RestModeActionRow(
                icon: "hands.sparkles",
                title: "Prayer",
                subtitle: "Share a request or pray for others"
            ) {
                onPrayerRequest()
                onDismiss()
            }
        }
    }

    private var pausedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paused until tomorrow")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .kerning(0.6)

            SundayRestFlowLayout(spacing: 8) {
                ForEach(pausedLabels, id: \.self) { label in
                    Text(label)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(.systemGray6))
                        )
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Paused: \(pausedLabels.joined(separator: ", "))")
        }
    }

    private var pausedLabels: [String] {
        ["Feed", "Posting", "Comments", "Likes", "Trending", "Social notifications"]
    }

    private var overrideButton: some View {
        Button {
            gate.logOverrideRequested()
            showOverrideFlow = true
        } label: {
            Text("I still need access for a few minutes")
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Row

private struct RestModeActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.systemScaled(20, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Override Flow Sheet

struct RestModeOverrideFlowSheet: View {

    @ObservedObject private var gate = RestModeGate.shared
    var onOverrideGranted: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 20)

            Text("Why do you need access?")
                .font(AMENFont.semiBold(18))
                .padding(.bottom, 6)

            Text("Amen will open for \(gate.policy?.overrideDurationMinutes ?? 15) minutes.\nNo judgment — just checking in.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)

            VStack(spacing: 10) {
                ForEach(RestModeOverrideReason.allCases) { reason in
                    OverrideReasonButton(reason: reason) {
                        gate.activateOverride(reason: reason)
                        dismiss()
                        onOverrideGranted()
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button("Cancel") { dismiss() }
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .padding(.bottom, 32)
        }
    }
}

private struct OverrideReasonButton: View {
    let reason: RestModeOverrideReason
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: reason.icon)
                    .font(.systemScaled(18))
                    .foregroundStyle(.primary)
                    .frame(width: 28)

                Text(reason.displayText)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(
                Capsule()
                    .fill(Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FlowLayout (simple wrapping HStack)

private struct SundayRestFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#Preview {
    SundayRestModeSheet(
        onFindChurch: {},
        onChurchNotes: {},
        onDailyVerse: {},
        onPrayerRequest: {},
        onDismiss: {}
    )
}

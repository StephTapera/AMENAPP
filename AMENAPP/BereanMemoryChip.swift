// BereanMemoryChip.swift
// AMENAPP
//
// Agent F — BereanUI Rebuild, 2026-05-27
//
// Glass chip that shimmers when prior memory is shaping the active response.
// Tapping it opens a sheet listing exactly what was pulled in.
//
// Design rules:
//  - Inactive: plain glass capsule, textTertiary label, brain SF Symbol
//  - Active: amenGold/amenPurple shimmer loop, amenGold pulsing border, textSecondary
//  - Shimmer and pulse border are gated on accessibilityReduceMotion
//  - ultraThinMaterial background gated on accessibilityReduceTransparency
//  - All tap targets ≥ 44×44pt via .contentShape(Rectangle())
//  - All springs use approved presets only

import SwiftUI

// MARK: - Local color constants
// amenPurple is not yet in a global Color extension;
// value matches BereanComposerTray.swift / CreatorSpacesHub.swift.
private extension Color {
    static let _memoryPurple = Color(red: 0.42, green: 0.28, blue: 1.00)
}

// MARK: - BereanMemoryDisplayEntry

/// UI display model for a persisted memory item in BereanMemoryChip.
/// Distinct from BereanContextMemoryService.BereanMemoryDisplayEntry (service/persistence model).
struct BereanMemoryDisplayEntry: Identifiable {
    let id: UUID
    let title: String
    let body: String
    let savedAt: Date
    var usedInCurrentResponse: Bool = false
}

// MARK: - BereanMemoryChip

/// Small glass chip in the composer or microstate area.
/// - `isActive`: true while memory is actively shaping the current Berean response
/// - `entries`: the full list of stored memory items (used to populate the detail sheet)
/// - `onOpenSettings`: optional callback wired to the Memory Settings link in the sheet
struct BereanMemoryChip: View {

    let isActive: Bool
    let entries: [BereanMemoryDisplayEntry]
    var onOpenSettings: (() -> Void)? = nil

    // MARK: State

    @State private var showSheet    = false
    @State private var shimmerPhase: CGFloat = 0.0
    @State private var borderPulse  = false

    // MARK: Accessibility

    @Environment(\.accessibilityReduceMotion)      private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Named springs

    /// Fast spring — interactive tap feedback
    private let fastSpring    = Animation.spring(response: 0.28, dampingFraction: 0.88)
    /// Capsule spring — chip active/inactive transition
    private let capsuleSpring = Animation.spring(response: 0.42, dampingFraction: 0.82)

    // MARK: Body

    var body: some View {
        Button {
            showSheet = true
        } label: {
            chipLabel
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(isActive ? "Berean memory active" : "Berean memory")
        .accessibilityHint("Double-tap to see what Berean remembered")
        .sheet(isPresented: $showSheet) {
            BereanMemoryDetailSheet(
                entries: entries,
                onOpenSettings: onOpenSettings,
                isPresented: $showSheet
            )
        }
        .onChange(of: isActive) { _, active in
            handleActiveChange(active)
        }
        .onAppear {
            if isActive { handleActiveChange(true) }
        }
    }

    // MARK: - Chip label

    private var chipLabel: some View {
        ZStack {
            // Background capsule
            Capsule()
                .fill(reduceTransparency
                    ? AmenTheme.Colors.surfaceChip
                    : .ultraThinMaterial
                )

            if !reduceTransparency {
                Capsule()
                    .fill(AmenTheme.Colors.glassFill)
            }

            // Shimmer gradient overlay (active + !reduceMotion)
            if isActive && !reduceMotion {
                shimmerLayer
            }

            // Pulsing gold border (active)
            Capsule()
                .strokeBorder(
                    Color.amenGold.opacity(isActive ? (reduceMotion ? 0.40 : (borderPulse ? 0.50 : 0.20)) : 0.0),
                    lineWidth: 0.75
                )
                .animation(
                    reduceMotion ? .none : capsuleSpring,
                    value: borderPulse
                )
                .animation(capsuleSpring, value: isActive)

            // Chip content
            HStack(spacing: 5) {
                Image(systemName: "brain")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(isActive
                        ? (reduceMotion ? BereanColor.textSecondary : Color.amenGold)
                        : BereanColor.textTertiary
                    )

                Text("Memory")
                    .font(AMENFont.medium(12))
                    .foregroundStyle(isActive
                        ? BereanColor.textSecondary
                        : BereanColor.textTertiary
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .fixedSize()
        .animation(capsuleSpring, value: isActive)
    }

    // MARK: - Shimmer layer

    /// Sweeping gold→purple→gold gradient, 1.4s loop.
    private var shimmerLayer: some View {
        GeometryReader { geo in
            LinearGradient(
                stops: [
                    .init(color: Color.amenGold.opacity(0.18),           location: 0.0),
                    .init(color: Color.amenGold.opacity(0.0),            location: max(0, shimmerPhase - 0.25)),
                    .init(color: Color.amenGold.opacity(0.18),           location: shimmerPhase),
                    .init(color: Color._memoryPurple.opacity(0.12),      location: min(1, shimmerPhase + 0.14)),
                    .init(color: Color.amenGold.opacity(0.18),           location: min(1, shimmerPhase + 0.28)),
                    .init(color: Color.amenGold.opacity(0.18),           location: 1.0),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
    }

    // MARK: - Animation helpers

    private func handleActiveChange(_ active: Bool) {
        guard !reduceMotion else { return }
        if active {
            startShimmer()
            startBorderPulse()
        } else {
            stopAnimations()
        }
    }

    private func startShimmer() {
        shimmerPhase = 0.0
        withAnimation(
            .linear(duration: 1.4)
            .repeatForever(autoreverses: false)
        ) {
            shimmerPhase = 1.3
        }
    }

    private func startBorderPulse() {
        borderPulse = false
        withAnimation(
            .easeInOut(duration: 1.1)
            .repeatForever(autoreverses: true)
        ) {
            borderPulse = true
        }
    }

    private func stopAnimations() {
        shimmerPhase = 0.0
        borderPulse  = false
    }
}

// MARK: - BereanMemoryDetailSheet

/// Presented when the user taps BereanMemoryChip.
/// Lists all memory entries; highlights those used in the current response.
struct BereanMemoryDetailSheet: View {

    let entries: [BereanMemoryDisplayEntry]
    var onOpenSettings: (() -> Void)?
    @Binding var isPresented: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection

                    // Entry list
                    if entries.isEmpty {
                        emptyState
                    } else {
                        entriesList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(BereanColor.textPrimary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Dismiss memory sheet")
                    .accessibilityHint("Closes the memory detail view")
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .font(.systemScaled(20, weight: .medium))
                    .foregroundStyle(Color.amenGold)

                Text("What Berean remembered")
                    .font(AMENFont.semiBold(20))
                    .foregroundStyle(BereanColor.textPrimary)
            }
            .padding(.top, 20)

            Text("Berean only uses memory you've shared")
                .font(AMENFont.regular(14))
                .foregroundStyle(BereanColor.textSecondary)

            if let openSettings = onOpenSettings {
                Button(action: openSettings) {
                    HStack(spacing: 4) {
                        Text("Memory settings")
                            .font(AMENFont.medium(14))
                        Image(systemName: "arrow.right")
                            .font(.systemScaled(12, weight: .medium))
                    }
                    .foregroundStyle(Color.amenGold)
                }
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityLabel("Open memory settings")
                .accessibilityHint("Opens settings to manage your memory")
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.systemScaled(32, weight: .light))
                .foregroundStyle(BereanColor.textTertiary)
            Text("No memory saved yet")
                .font(AMENFont.medium(16))
                .foregroundStyle(BereanColor.textSecondary)
            Text("Berean builds memory as you study and pray together.")
                .font(AMENFont.regular(14))
                .foregroundStyle(BereanColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Entry list

    private var entriesList: some View {
        VStack(spacing: 12) {
            ForEach(entries) { entry in
                entryRow(entry)
            }
        }
    }

    private func entryRow(_ entry: BereanMemoryDisplayEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(BereanColor.textPrimary)
                        .lineLimit(2)

                    Text(entry.body)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(BereanColor.textSecondary)
                        .lineLimit(3)
                }

                Spacer()

                if entry.usedInCurrentResponse {
                    usedBadge
                }
            }

            Text(dateFormatter.string(from: entry.savedAt))
                .font(AMENFont.regular(11))
                .foregroundStyle(BereanColor.textTertiary)
        }
        .padding(14)
        .bereanGlassCard(cornerRadius: 14, shadowRadius: 8, shadowY: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.title). \(entry.body). Saved \(dateFormatter.string(from: entry.savedAt))."
            + (entry.usedInCurrentResponse ? " Used in this response." : "")
        )
    }

    private var usedBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.amenGold)
                .frame(width: 6, height: 6)
            Text("Used")
                .font(AMENFont.medium(11))
                .foregroundStyle(Color.amenGold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.amenGold.opacity(0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.amenGold.opacity(0.30), lineWidth: 0.75)
                )
        )
        .accessibilityHidden(true)  // parent accessibilityLabel already conveys "Used in this response"
    }
}

// MARK: - Previews

#Preview("Memory Chip — inactive") {
    VStack(spacing: 24) {
        BereanMemoryChip(isActive: false, entries: [])
        BereanMemoryChip(
            isActive: false,
            entries: [
                BereanMemoryDisplayEntry(
                    id: UUID(),
                    title: "Favorite verse",
                    body: "John 3:16 — God so loved the world…",
                    savedAt: Date(),
                    usedInCurrentResponse: false
                )
            ]
        )
    }
    .padding()
    .background(Color(uiColor: .systemBackground))
}

#Preview("Memory Chip — active shimmer") {
    VStack(spacing: 24) {
        let sampleEntries: [BereanMemoryDisplayEntry] = [
            BereanMemoryDisplayEntry(
                id: UUID(),
                title: "Prayer focus this week",
                body: "I've been praying through Romans 8 and asking for help with anxiety.",
                savedAt: Date().addingTimeInterval(-86400 * 3),
                usedInCurrentResponse: true
            ),
            BereanMemoryDisplayEntry(
                id: UUID(),
                title: "Home church",
                body: "I attend Grace Church in Austin, TX.",
                savedAt: Date().addingTimeInterval(-86400 * 14),
                usedInCurrentResponse: false
            ),
            BereanMemoryDisplayEntry(
                id: UUID(),
                title: "Study preference",
                body: "I prefer ESV translation with cross-references.",
                savedAt: Date().addingTimeInterval(-86400 * 7),
                usedInCurrentResponse: true
            ),
        ]

        BereanMemoryChip(
            isActive: true,
            entries: sampleEntries,
            onOpenSettings: {}
        )
    }
    .padding()
    .background(Color(uiColor: .systemBackground))
}

#Preview("Memory Detail Sheet") {
    let sampleEntries: [BereanMemoryDisplayEntry] = [
        BereanMemoryDisplayEntry(
            id: UUID(),
            title: "Prayer focus this week",
            body: "I've been praying through Romans 8 and asking for help with anxiety.",
            savedAt: Date().addingTimeInterval(-86400 * 3),
            usedInCurrentResponse: true
        ),
        BereanMemoryDisplayEntry(
            id: UUID(),
            title: "Home church",
            body: "I attend Grace Church in Austin, TX.",
            savedAt: Date().addingTimeInterval(-86400 * 14),
            usedInCurrentResponse: false
        ),
        BereanMemoryDisplayEntry(
            id: UUID(),
            title: "Study preference",
            body: "I prefer ESV translation with cross-references.",
            savedAt: Date().addingTimeInterval(-86400 * 7),
            usedInCurrentResponse: true
        ),
    ]

    BereanMemoryDetailSheet(
        entries: sampleEntries,
        onOpenSettings: {},
        isPresented: .constant(true)
    )
}

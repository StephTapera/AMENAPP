import SwiftUI
import FirebaseAuth

struct SpiritualInboxView: View {
    @StateObject private var unsentService = UnsentThoughtsService.shared
    @StateObject private var silenceService = SilenceIntelligenceService.shared
    @StateObject private var driftService = ScriptureDriftService.shared
    @StateObject private var gravityService = RelationalGravityService.shared
    @StateObject private var eternalService = EternalWeightService.shared
    @StateObject private var momentService = MomentInterceptionService.shared

    @State private var selectedFilter: InboxFilter = .all
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum InboxFilter: String, CaseIterable {
        case all = "All"
        case urgent = "Urgent"
        case relational = "Relational"
        case patterns = "Patterns"
        case eternal = "Eternal"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        filterBar

                        if hasNoSignals {
                            emptyStateCard
                        } else {
                            signalSections
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Spiritual Inbox")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Close Spiritual Inbox")
                }
            }
        }
        .task {
            unsentService.startListening()
            silenceService.startListening()
            driftService.startListening()
            gravityService.startListening()
            eternalService.startListening()
        }
    }

    private var hasNoSignals: Bool {
        unsentService.activeThoughts.isEmpty &&
        silenceService.silenceSignals.isEmpty &&
        driftService.driftSignals.isEmpty &&
        gravityService.nodes.filter { $0.currentState != .peaceful }.isEmpty
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InboxFilter.allCases, id: \.self) { filter in
                    filterPill(filter)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func filterPill(_ filter: InboxFilter) -> some View {
        Button(action: { withAnimation(.spring(response: 0.3)) { selectedFilter = filter } }) {
            Text(filter.rawValue)
                .font(.subheadline)
                .fontWeight(selectedFilter == filter ? .semibold : .regular)
                .foregroundStyle(selectedFilter == filter ? Color.primary : Color.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if selectedFilter == filter {
                        Capsule().fill(Color.primary.opacity(0.08))
                    } else {
                        Capsule().fill(Color.clear)
                    }
                }
                .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
        }
        .accessibilityLabel("\(filter.rawValue) filter")
        .accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])
    }

    @ViewBuilder
    private var signalSections: some View {
        if !unsentService.activeThoughts.isEmpty && (selectedFilter == .all || selectedFilter == .urgent) {
            SpiritualInboxSectionCard(title: "Unprocessed Thoughts", icon: "bubble.left.and.text.bubble.right", count: unsentService.activeThoughts.count) {
                VStack(spacing: 10) {
                    ForEach(unsentService.activeThoughts.prefix(3)) { thought in
                        SpiritualInboxThreadRow(
                            title: String((thought.draftText.prefix(60))) + "...",
                            subtitle: "Saved from \(thought.sourceSurface)",
                            flags: thought.riskFlags
                        )
                    }
                }
            }
        }

        if !silenceService.silenceSignals.isEmpty && (selectedFilter == .all || selectedFilter == .patterns) {
            SpiritualInboxSectionCard(title: "Quiet Patterns", icon: "moon.stars", count: silenceService.silenceSignals.count) {
                VStack(spacing: 10) {
                    ForEach(silenceService.silenceSignals.prefix(3)) { signal in
                        SilenceInsightCard(signal: signal)
                    }
                }
            }
        }

        if !driftService.driftSignals.isEmpty && (selectedFilter == .all || selectedFilter == .patterns) {
            SpiritualInboxSectionCard(title: "Scripture Patterns", icon: "book.closed", count: driftService.driftSignals.count) {
                VStack(spacing: 10) {
                    ForEach(driftService.driftSignals.prefix(2)) { signal in
                        ScriptureDriftInsightCard(signal: signal)
                    }
                }
            }
        }

        let tensionNodes = gravityService.nodes.filter {
            $0.currentState == .tense || $0.currentState == .unresolved || $0.currentState == .needsPrayer
        }
        if !tensionNodes.isEmpty && (selectedFilter == .all || selectedFilter == .relational) {
            SpiritualInboxSectionCard(title: "Relationships", icon: "person.2", count: tensionNodes.count) {
                VStack(spacing: 10) {
                    ForEach(tensionNodes.prefix(3)) { node in
                        RelationshipStateCard(node: node, compact: true)
                    }
                }
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 40))
                .foregroundStyle(Color.secondary)
            Text("Your spiritual inbox is clear.")
                .font(.headline)
                .foregroundStyle(Color.primary)
            Text("Keep walking forward.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section Card Wrapper

struct SpiritualInboxSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let count: Int
    @ViewBuilder let content: Content
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: { withAnimation(.spring(response: 0.35)) { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            .accessibilityLabel("\(title), \(count) items, \(isExpanded ? "expanded" : "collapsed")")

            if isExpanded {
                content
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 5)
    }
}

// MARK: - Thread Row

struct SpiritualInboxThreadRow: View {
    let title: String
    let subtitle: String
    let flags: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.3))
                .frame(width: 3, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

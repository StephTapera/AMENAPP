import SwiftUI

struct BereanCommunicationHubView: View {
    var onOpenThread: ((String) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedScope: CommunicationScope = .all
    @State private var searchText = ""
    @State private var selectedThreadID: String?

    private let threads = CommunicationThreadPreview.samples
    private let presences = PresencePreview.samples
    private let digest = DigestPreview.sample

    private var filteredThreads: [CommunicationThreadPreview] {
        threads.filter { thread in
            (selectedScope == .all || thread.scope == selectedScope) &&
            (searchText.isEmpty || thread.title.localizedCaseInsensitiveContains(searchText) || thread.preview.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                background

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        presenceRail
                        digestCard
                        commandPalettePreview
                        threadsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 130)
                }

                composerBar
            }
            .navigationTitle("Communion")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.98, blue: 0.96),
                Color(red: 0.94, green: 0.95, blue: 0.92),
                Color(red: 0.90, green: 0.93, blue: 0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.38))
                .frame(width: 220, height: 220)
                .blur(radius: 50)
                .offset(x: 70, y: -20)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Communication that remembers where prayer, study, and care left off.")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text("A calm operating layer for threads, prayer follow-up, retrieval, and sacred collaboration.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Find that prayer from last month…", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
            }
        }
    }

    private var presenceRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Presence")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(presences) { presence in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(presence.tint)
                                    .frame(width: 9, height: 9)
                                Text(presence.name)
                                    .font(.subheadline.weight(.semibold))
                            }

                            Text(presence.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(14)
                        .frame(width: 158, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
        }
    }

    private var digestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Today’s Digest")
                Spacer()
                Text("2 unresolved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }

            Text(digest.headline)
                .font(.headline)

            ForEach(digest.highlights, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.86, green: 0.62, blue: 0.24))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                digestAction("Catch up")
                digestAction("Summarize prayer rooms", emphasized: false)
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 0.8)
        }
    }

    private var commandPalettePreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Quick Actions")

            VStack(alignment: .leading, spacing: 10) {
                commandRow(icon: "command", title: "Jump to threads", subtitle: "Recent rooms, prayer chains, saved studies")
                commandRow(icon: "book.pages", title: "Search scripture", subtitle: "Query by passage, theme, or remembered wording")
                commandRow(icon: "brain.head.profile", title: "Ask Berean deeper", subtitle: "Context-aware study and recap actions")
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var threadsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Threads")
                Spacer()
            }

            scopeRail

            ForEach(filteredThreads) { thread in
                Button {
                    withAnimation(animation) {
                        selectedThreadID = selectedThreadID == thread.id ? nil : thread.id
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(thread.tint.opacity(0.16))
                                .frame(width: 42, height: 42)
                                .overlay {
                                    Image(systemName: thread.icon)
                                        .foregroundStyle(thread.tint)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(thread.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(thread.timeLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text(thread.preview)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(selectedThreadID == thread.id ? 4 : 2)
                            }
                        }

                        HStack(spacing: 8) {
                            threadPill(thread.presenceLabel, tint: thread.tint)
                            threadPill("\(thread.replyCount) replies", tint: .gray)
                            if thread.needsFollowUp {
                                threadPill("Follow-up", tint: .orange)
                            }
                        }

                        if selectedThreadID == thread.id {
                            VStack(alignment: .leading, spacing: 10) {
                                Divider()
                                Text(thread.expandedSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    threadAction("Reply in thread")
                                    threadAction("Save to prayer")
                                    threadAction("Turn into journal")
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.48), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var scopeRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CommunicationScope.allCases) { scope in
                    Button {
                        withAnimation(animation) {
                            selectedScope = scope
                        }
                    } label: {
                        Text(scope.title)
                            .font(.subheadline.weight(selectedScope == scope ? .semibold : .regular))
                            .foregroundStyle(selectedScope == scope ? .primary : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(selectedScope == scope ? Color.white.opacity(0.85) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var composerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Continue this study later")
                    .font(.subheadline.weight(.semibold))
                Text("Drafts, branches, and prayer follow-ups persist across devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Resume") { }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.primary, in: Capsule())
                .foregroundStyle(Color(uiColor: .systemBackground))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.65), lineWidth: 0.8)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }

    private func digestAction(_ title: String, emphasized: Bool = true) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(emphasized ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(emphasized ? Color.white.opacity(0.78) : Color.clear, in: Capsule())
    }

    private func commandRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func threadPill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint == .gray ? .secondary : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(tint == .gray ? 0.08 : 0.12), in: Capsule())
    }

    private func threadAction(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.78), in: Capsule())
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.32, dampingFraction: 0.82)
    }
}

private struct PresencePreview: Identifiable {
    let id: String
    let name: String
    let detail: String
    let tint: Color

    static let samples: [PresencePreview] = [
        .init(id: "1", name: "Praying", detail: "Quiet mode until 8:15 PM", tint: .orange),
        .init(id: "2", name: "Deep study", detail: "In Romans study branch", tint: .blue),
        .init(id: "3", name: "Available", detail: "Open for prayer requests", tint: .green)
    ]
}

private struct DigestPreview {
    let headline: String
    let highlights: [String]

    static let sample = DigestPreview(
        headline: "Berean noticed a few threads worth your attention before the day closes.",
        highlights: [
            "A prayer request from Ava still has no follow-up after yesterday evening.",
            "Your James 1 study branch now has three unresolved scripture replies.",
            "Two saved reflections can be turned into journal entries."
        ]
    )
}

private struct CommunicationThreadPreview: Identifiable {
    let id: String
    let title: String
    let preview: String
    let expandedSummary: String
    let timeLabel: String
    let replyCount: Int
    let needsFollowUp: Bool
    let icon: String
    let tint: Color
    let scope: CommunicationScope
    let presenceLabel: String

    static let samples: [CommunicationThreadPreview] = [
        .init(
            id: "t1",
            title: "Ava’s prayer chain",
            preview: "Please keep praying for peace before tomorrow’s oncology appointment.",
            expandedSummary: "Sensitive prayer thread with two supporters active, one pending follow-up, and a saved care reminder set for tomorrow morning.",
            timeLabel: "8m",
            replyCount: 12,
            needsFollowUp: true,
            icon: "hands.and.sparkles",
            tint: .orange,
            scope: .prayer,
            presenceLabel: "Prayer"
        ),
        .init(
            id: "t2",
            title: "Romans 8 study room",
            preview: "Nested reflection on suffering, adoption, and how hope should be framed pastorally.",
            expandedSummary: "The branch includes quoted scripture replies, one AI recap, and a continuation point so the discussion can resume later without losing context.",
            timeLabel: "24m",
            replyCount: 18,
            needsFollowUp: false,
            icon: "book.pages",
            tint: .blue,
            scope: .study,
            presenceLabel: "Studying"
        ),
        .init(
            id: "t3",
            title: "Remembered prayer about anxiety",
            preview: "Semantic memory linked Philippians 4:6, a church note, and a saved Berean reflection from last month.",
            expandedSummary: "This memory cluster ranks high because it combines explicit saves, repeated recall, and a recent prayer request from the same person.",
            timeLabel: "1h",
            replyCount: 3,
            needsFollowUp: false,
            icon: "brain.head.profile",
            tint: .purple,
            scope: .memory,
            presenceLabel: "Recall"
        ),
        .init(
            id: "t4",
            title: "Jordan direct reflection",
            preview: "Thank you for staying with me in that conversation. I needed the reminder not to isolate.",
            expandedSummary: "Direct reflection thread with one pinned message, scheduled send enabled for the next check-in, and no unresolved moderation flags.",
            timeLabel: "3h",
            replyCount: 6,
            needsFollowUp: false,
            icon: "message",
            tint: .green,
            scope: .direct,
            presenceLabel: "Available"
        )
    ]
}

#Preview {
    BereanCommunicationHubView()
}

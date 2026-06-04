import SwiftUI

struct BereanCommunicationHubView: View {
    @StateObject private var viewModel = BereanCommunicationHubViewModel()
    @StateObject private var commFlags = CommunicationOSFeatureFlags.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var selectedScope: CommunicationScope = .all
    @State private var searchText = ""
    @State private var selectedThreadID: String?
    @State private var showingAttachmentMenu = false

    private var filteredThreads: [CommunicationThreadItem] {
        viewModel.threads.filter { thread in
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

                VStack(spacing: 0) {
                    if commFlags.smartMessageContextEnabled {
                        SmartMessageInsightCard(
                            detectedItems: [],
                            onAction: { _ in },
                            onDismiss: { _ in }
                        )
                        .padding(.bottom, 4)
                    }
                    composerBar
                }
            }
            .navigationTitle("Communion")
            .sheet(isPresented: $showingAttachmentMenu) {
                SmartMessageActionMenu(
                    onAction: { _ in },
                    onDismiss: { showingAttachmentMenu = false }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { viewModel.load() }
            .onDisappear { viewModel.cleanup() }
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
                    ForEach(viewModel.presenceItems) { presence in
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
                if viewModel.unresolvedCount > 0 {
                    Text("\(viewModel.unresolvedCount) unresolved")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }

            Text(viewModel.digestHeadline)
                .font(.headline)

            ForEach(viewModel.digestHighlights, id: \.self) { item in
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

            switch viewModel.loadingState {
            case .loading:
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 32)
                    Spacer()
                }
            case .empty:
                Text("No threads yet. Start a prayer or study session with Berean.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            case .error(let message):
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 24)
            default:
                EmptyView()
            }

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
            if commFlags.smartAttachmentMenuEnabled {
                Button {
                    showingAttachmentMenu = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Attachment menu")
            }

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
                .accessibilityLabel("Resume study session")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // Solid opaque fallback honours the user's reduce-transparency preference
        .background {
            if reduceTransparency {
                Capsule(style: .continuous)
                    .fill(Color(.systemBackground))
            }
        }
        // Shadow applied before the glass surface so it renders beneath it.
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .glassEffect(reduceTransparency ? .identity : GlassEffectStyle.regular, in: Capsule(style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
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

#Preview {
    BereanCommunicationHubView()
}

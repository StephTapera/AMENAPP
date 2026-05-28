// CommunityNotesFeedView.swift
// AMENAPP — Community Notes main feed
//
// Structural pattern: Apple News "Today" (date heading + category pills + hero + list).
// AMEN identity applied throughout — amenGold, amenPurple, amenBlue, amenBlack ONLY.
// Faith-native labels: "Top Notes", "Continue Reading", "Saved Notes".
// Reuses AMENGlassCard, SpaceRailView, ChurchBadgeChip, AMENGlassPillButton
// from SpacesDesignSystem.swift — no duplicates.

import SwiftUI

@MainActor
struct CommunityNotesFeedView: View {

    /// Optional initial category filter passed from Browse tap.
    var initialCategory: NoteCategory? = nil

    @StateObject private var service = CommunityNotesService.shared
    @State private var selectedCategory: NoteCategory?
    @State private var topNotes: [CommunityNote] = []
    @State private var recentNotes: [CommunityNote] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var showPublishSheet = false

    init(initialCategory: NoteCategory? = nil) {
        self.initialCategory = initialCategory
        _selectedCategory = State(initialValue: initialCategory)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    dateHeading
                    categoryPillRow
                    if isLoading {
                        loadingState
                    } else if let err = loadError {
                        errorState(message: err)
                    } else {
                        topNotesSection
                        recentNotesSection
                    }
                }
                .padding(.bottom, 100) // FAB clearance
            }

            publishFAB
        }
        .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
        .sheet(isPresented: $showPublishSheet) {
            CommunityNotePublishSheet(isPresented: $showPublishSheet)
        }
        .task(id: selectedCategory?.rawValue ?? "all") {
            await loadNotes()
        }
    }

    // MARK: - Date Heading

    private var dateHeading: some View {
        Text(formattedDate)
            .font(.largeTitle.bold())
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Category Pill Row

    private var categoryPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // "All" pill
                allPill

                // Category pills
                ForEach(NoteCategory.allCases) { cat in
                    categoryPill(cat)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var allPill: some View {
        let isActive = selectedCategory == nil
        Button {
            withAnimation(Motion.popToggle) { selectedCategory = nil }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.caption2.weight(.semibold))
                Text("All")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? AmenTheme.Colors.amenBlack : AmenTheme.Colors.textPrimary)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background {
                if isActive {
                    Capsule(style: .continuous).fill(AmenTheme.Colors.amenGold)
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay { Capsule(style: .continuous).fill(AmenTheme.Colors.glassFill) }
                        .overlay { Capsule(style: .continuous).strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75) }
                }
            }
            .shadow(color: AmenTheme.Colors.shadowCard, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .amenPress(scale: 0.96)
        .accessibilityLabel("All categories")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private func categoryPill(_ cat: NoteCategory) -> some View {
        let isActive = selectedCategory == cat
        Button {
            withAnimation(Motion.popToggle) {
                selectedCategory = (selectedCategory == cat) ? nil : cat
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: cat.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isActive ? AmenTheme.Colors.amenBlack : cat.tint)
                Text(cat.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? AmenTheme.Colors.amenBlack : AmenTheme.Colors.textPrimary)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background {
                if isActive {
                    Capsule(style: .continuous).fill(AmenTheme.Colors.amenGold)
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay { Capsule(style: .continuous).fill(cat.tint.opacity(0.08)) }
                        .overlay { Capsule(style: .continuous).strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75) }
                }
            }
            .shadow(color: AmenTheme.Colors.shadowCard, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .amenPress(scale: 0.96)
        .accessibilityLabel(cat.displayName)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Top Notes Section

    @ViewBuilder
    private var topNotesSection: some View {
        if !topNotes.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                // Section header
                sectionHeader(title: "Top Notes", destination: {})

                // Hero note card (first item)
                if let hero = topNotes.first {
                    heroCard(note: hero)
                        .padding(.horizontal, 20)
                }

                // Horizontal rail of remaining top notes
                if topNotes.count > 1 {
                    SpaceRailView(
                        title: "Continue Reading",
                        items: Array(topNotes.dropFirst())
                    ) { note in
                        NavigationLink(destination: CommunityNoteDetailPlaceholder(note: note)) {
                            AMENGlassCard(width: 200, height: 140, tintColor: note.category.tint) {
                                railCardContent(note: note)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 28)
        }
    }

    // MARK: - Recent Notes Section

    @ViewBuilder
    private var recentNotesSection: some View {
        if !recentNotes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "Recent", destination: {})

                LazyVStack(spacing: 12) {
                    ForEach(Array(recentNotes.enumerated()), id: \.element.id) { index, note in
                        NavigationLink(destination: CommunityNoteDetailPlaceholder(note: note)) {
                            CommunityNoteCardView(note: note)
                                .padding(.horizontal, 20)
                        }
                        .buttonStyle(.plain)
                        .staggeredReveal(index: index, baseDelay: 0.04, maxDelay: 0.20)
                    }
                }
            }
            .padding(.bottom, 20)
        } else if !isLoading {
            emptyState
        }
    }

    // MARK: - Hero Card

    private func heroCard(note: CommunityNote) -> some View {
        NavigationLink(destination: CommunityNoteDetailPlaceholder(note: note)) {
            AMENGlassCard(
                width: UIScreen.main.bounds.width - 40,
                height: 180,
                tintColor: note.category.tint
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    // Author + category chip row
                    HStack(spacing: 8) {
                        authorAvatar(initial: note.authorInitial, color: note.authorSwiftUIColor, size: 28)
                        Text(note.authorName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        ChurchBadgeChip(badge: ChurchBadgeChip.Badge(
                            icon: note.category.icon,
                            label: note.category.displayName,
                            tint: note.category.tint
                        ))
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)

                    // Title
                    Text(note.title)
                        .font(.title3.bold())
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(2)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)

                    Spacer()

                    // Scripture ref chips
                    if !note.scriptureRefStrings.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(note.scriptureRefStrings.prefix(3), id: \.self) { ref in
                                    ChurchBadgeChip(badge: ChurchBadgeChip.Badge(
                                        icon: "book.closed.fill",
                                        label: ref,
                                        tint: AmenTheme.Colors.amenGold
                                    ))
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                        .padding(.bottom, 8)
                    }

                    // Footer: like + comment counts
                    HStack(spacing: 14) {
                        Label("\(note.likeCount)", systemImage: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(AmenTheme.Colors.amenGold)
                        Label("\(note.commentCount)", systemImage: "bubble.fill")
                            .font(.caption2)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                        Spacer()
                        Text(note.createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rail Card Content

    private func railCardContent(note: CommunityNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: note.category.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(note.category.tint)
                .padding(.top, 14)
                .padding(.leading, 12)
            Text(note.title)
                .font(.subheadline.bold())
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(3)
                .padding(.horizontal, 12)
            Spacer()
            Label("\(note.likeCount)", systemImage: "heart.fill")
                .font(.caption2)
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, destination: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: destination) {
                Text("See All ›")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all \(title)")
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Author Avatar

    private func authorAvatar(initial: String, color: Color, size: CGFloat) -> some View {
        Text(initial)
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .accessibilityHidden(true)
    }

    // MARK: - FAB

    private var publishFAB: some View {
        Button {
            showPublishSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                Text("Share Note")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(AmenTheme.Colors.amenBlack)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(
                Capsule(style: .continuous).fill(AmenTheme.Colors.amenGold)
            )
            .shadow(
                color: AmenTheme.Colors.amenGold.opacity(0.35),
                radius: 12, x: 0, y: 6
            )
        }
        .buttonStyle(.plain)
        .amenPress(scale: 0.96)
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .accessibilityLabel("Share a note")
        .accessibilityHint("Opens the note publishing sheet.")
    }

    // MARK: - Loading / Error / Empty States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(height: 96)
                    .padding(.horizontal, 20)
                    .amenSkeleton()
            }
        }
        .padding(.top, 12)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(AmenTheme.Colors.amenGold)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await loadNotes() } }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.largeTitle)
                .foregroundStyle(AmenTheme.Colors.amenGold.opacity(0.6))
            Text("Be the first to share what God is speaking to you")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.top, 60)
    }

    // MARK: - Data loading

    private func loadNotes() async {
        isLoading = true
        loadError = nil
        do {
            async let top    = service.fetchTopNotes(category: selectedCategory)
            async let recent = service.fetchRecentNotes(category: selectedCategory)
            let (t, r) = try await (top, recent)
            topNotes    = t
            recentNotes = r
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }
}

// MARK: - Detail Placeholder
// Temporary destination so NavigationLinks compile.
// Replace with the real CommunityNoteDetailView once built.

private struct CommunityNoteDetailPlaceholder: View {
    let note: CommunityNote
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(note.title)
                    .font(.title2.bold())
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .padding(.horizontal, 20)
                Text(note.body)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 20)
        }
        .navigationTitle(note.category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
    }
}

// MARK: - Preview

#if DEBUG
#Preview("CommunityNotesFeedView") {
    NavigationStack {
        CommunityNotesFeedView()
    }
}
#endif

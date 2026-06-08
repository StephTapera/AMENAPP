import SwiftUI

struct LivingEntriesHomeView: View {
    enum SourceFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case churchNotes = "Church Notes"
        case findChurch = "Find Church"
        case berean = "Berean"
        case home = "Home"
        case feed = "Feed"

        var id: String { rawValue }

        var sourceSurface: LivingEntrySourceSurface? {
            switch self {
            case .all:
                return nil
            case .churchNotes:
                return .churchNotes
            case .findChurch:
                return .findChurch
            case .berean:
                return .berean
            case .home:
                return .home
            case .feed:
                return .feed
            }
        }
    }

    @StateObject private var viewModel = LivingEntryViewModel()
    @State private var selectedFilter: SourceFilter
    @State private var composerExpanded = false
    @State private var reflectingEntry: LivingEntry?
    @State private var editingEntry: LivingEntry?
    @State private var scrollOffset: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(initialFilter: SourceFilter = .all) {
        _selectedFilter = State(initialValue: initialFilter)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    GeometryReader { geometry in
                        Color.clear
                            .preference(key: LivingEntriesScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("livingEntriesScroll")).minY)
                    }
                    .frame(height: 0)

                    VStack(alignment: .leading, spacing: 22) {
                        header
                        sourceFilterRow
                        if viewModel.isLoading && viewModel.sections.values.allSatisfy({ $0.isEmpty }) {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(.top, 40)
                                Spacer()
                            }
                        }
                        ForEach(LivingEntrySection.allCases) { section in
                            LiquidGlassEntryStackView(
                                title: section.title,
                                entries: filteredEntries(for: section),
                                triggerReason: triggerReason(for:),
                                stackDepth: stackDepth(for: section)
                            ) { entry in
                                Task {
                                    if entry.state == .needsReflection {
                                        reflectingEntry = entry
                                    } else {
                                        await viewModel.complete(entry)
                                    }
                                }
                            } onTap: { entry in
                                if entry.state == .needsReflection {
                                    reflectingEntry = entry
                                } else if entry.type == .note || entry.type == .reflection || entry.type == .sermonInsight {
                                    editingEntry = entry
                                }
                            }
                        }
                    }
                    .animation(LivingLiquidGlassMotion.normal(reduceMotion), value: selectedFilter)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
                .coordinateSpace(name: "livingEntriesScroll")
                .onPreferenceChange(LivingEntriesScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }

                LiquidGlassComposerBar(
                    text: $viewModel.composerText,
                    isExpanded: $composerExpanded,
                    placeholder: placeholder
                ) { type, text in
                    Task {
                        await viewModel.createQuickEntry(type: type, title: text, sourceSurface: composerSurface)
                    }
                } onAskBerean: {
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Living Entries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(20))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Close Living Entries")
                }
            }
        }
        .task {
            viewModel.loadEntries()
        }
        .refreshable {
            viewModel.loadEntries()
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(item: $reflectingEntry) { entry in
            LivingEntryReflectionSheet(entry: entry) { answer, helpfulness in
                try? await LivingEntryService.shared.addReflection(entry: entry, answer: answer, helpfulness: helpfulness)
            }
        }
        .sheet(item: $editingEntry) { entry in
            AmenLivingNotesBlockEditor(entry: entry) {
                viewModel.loadEntries()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Living Entries")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(primaryTextColor)
            Text("Notes, reminders, prayer, and church follow-up that stay context-aware.")
                .font(.subheadline)
                .foregroundStyle(primaryTextColor.opacity(0.7))
            if selectedFilter != .all {
                Text("Showing \(selectedFilter.rawValue.lowercased()) first, with reflection and trigger reasons intact.")
                    .font(.footnote)
                    .foregroundStyle(primaryTextColor.opacity(0.58))
            }
        }
    }

    private var sourceFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SourceFilter.allCases) { filter in
                    Button {
                        withAnimation(LivingLiquidGlassMotion.fast(reduceMotion)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedFilter == filter ? primaryTextColor : primaryTextColor.opacity(0.68))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background {
                                Capsule()
                                    .fill(selectedFilter == filter ? Color.white.opacity(colorScheme == .dark ? 0.16 : 0.88) : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.52))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter by \(filter.rawValue)")
                }
            }
            .padding(6)
            .livingGlassMaterial(tint: tintForFilter, elevated: scrollOffset < -40)
            .clipShape(Capsule())
        }
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.black, Color(red: 0.09, green: 0.1, blue: 0.12)]
                : [Color.white, Color(red: 0.97, green: 0.97, blue: 0.95)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var composerSurface: LivingEntrySourceSurface {
        selectedFilter.sourceSurface ?? .home
    }

    private var tintForFilter: Color? {
        switch selectedFilter {
        case .all:
            return Color.black.opacity(0.08)
        case .churchNotes:
            return .orange
        case .findChurch:
            return .blue
        case .berean:
            return .mint
        case .home:
            return .gray
        case .feed:
            return .pink
        }
    }

    private var placeholder: String {
        if selectedFilter == .churchNotes {
            return "Remember this from church..."
        }
        if selectedFilter == .findChurch {
            return "Follow up after service..."
        }
        if selectedFilter == .berean {
            return "Ask Berean to organize this..."
        }
        if Calendar.current.component(.weekday, from: Date()) == 1 {
            return "Follow up after service..."
        }
        return "Ask Berean to organize this..."
    }

    private func filteredEntries(for section: LivingEntrySection) -> [LivingEntry] {
        let entries = viewModel.sections[section] ?? []
        guard let source = selectedFilter.sourceSurface else { return entries }
        return entries.filter { $0.contextSnapshot.sourceSurface == source }
    }

    private func stackDepth(for section: LivingEntrySection) -> CGFloat {
        let sectionIndex = CGFloat(LivingEntrySection.allCases.firstIndex(of: section) ?? 0)
        let travelDepth = min(max(-scrollOffset / 180, 0), 4)
        return sectionIndex + travelDepth
    }

    private func triggerReason(for entry: LivingEntry) -> String? {
        let reasons = LivingEntryContextEngine.evaluate(entry: entry, context: .current()).matchedReasons
        return reasons.first
    }
}

private struct LivingEntriesScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

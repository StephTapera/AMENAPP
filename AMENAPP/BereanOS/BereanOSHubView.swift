// BereanOSHubView.swift
// AMENAPP — Berean OS
//
// Main entry point for the Berean Wisdom Operating System.
// All sections are feature-flag gated; falls back to ContentUnavailableView
// when all flags are off.

import SwiftUI
import FirebaseAuth

// MARK: - BereanOSHubView

struct BereanOSHubView: View {
    @StateObject private var projectService = BereanProjectService.shared
    @StateObject private var feedService = BereanKnowledgeFeedService.shared
    @StateObject private var advisoryService = BereanAdvisoryBoardService.shared
    @StateObject private var flags = AMENFeatureFlags.shared
    @State private var searchQuery = ""
    @State private var showSearch = false

    // MARK: - Feature Visibility Helpers

    private var anyFeatureEnabled: Bool {
        flags.bereanOSProjectsEnabled ||
        flags.bereanOSResearchEngineEnabled ||
        flags.bereanOSWisdomEngineEnabled ||
        flags.bereanOSMultiPerspectiveEnabled ||
        flags.bereanOSDebateEngineEnabled ||
        flags.bereanOSSocialKnowledgeFeedEnabled ||
        flags.bereanOSAdvisoryBoardsEnabled ||
        flags.bereanOSMentorOSEnabled ||
        flags.bereanOSKnowledgeGraphEnabled
    }

    private var anyQuickActionEnabled: Bool {
        flags.bereanOSResearchEngineEnabled ||
        flags.bereanOSWisdomEngineEnabled ||
        flags.bereanOSMultiPerspectiveEnabled ||
        flags.bereanOSDebateEngineEnabled
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                if anyFeatureEnabled {
                    LazyVStack(spacing: 20, pinnedViews: []) {
                        if anyQuickActionEnabled {
                            quickActionsSection
                        }
                        if flags.bereanOSProjectsEnabled {
                            projectsSection
                        }
                        if flags.bereanOSSocialKnowledgeFeedEnabled {
                            knowledgeFeedSection
                        }
                        if flags.bereanOSAdvisoryBoardsEnabled {
                            advisoryBoardsSection
                        }
                        if flags.bereanOSMentorOSEnabled {
                            mentorshipSection
                        }
                        if flags.bereanOSKnowledgeGraphEnabled {
                            knowledgeGraphSection
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                } else {
                    ContentUnavailableView(
                        "Berean OS",
                        systemImage: "brain.head.profile",
                        description: Text("Your personal wisdom operating system is coming soon.")
                    )
                    .padding(.top, 60)
                }
            }
            .navigationTitle("Berean OS")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSearch.toggle() } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search Berean OS")
                }
            }
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .sheet(isPresented: $showSearch) {
                BereanOSSearchSheet()
            }
            .task {
                async let _ = try? projectService.fetchProjects()
                async let _ = try? feedService.loadFeed()
                async let _ = try? advisoryService.fetchBoards()
            }
        }
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Quick Actions", destination: nil as AnyView?)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if flags.bereanOSResearchEngineEnabled {
                        NavigationLink {
                            BereanResearchView(projectId: nil)
                        } label: {
                            BereanOSHubQuickActionChip(icon: "scope", label: "Research")
                        }
                        .buttonStyle(.plain)
                    }
                    if flags.bereanOSWisdomEngineEnabled {
                        NavigationLink {
                            BereanWisdomAnalysisView(projectId: nil)
                        } label: {
                            BereanOSHubQuickActionChip(icon: "brain.head.profile", label: "Wisdom")
                        }
                        .buttonStyle(.plain)
                    }
                    if flags.bereanOSMultiPerspectiveEnabled {
                        NavigationLink {
                            BereanPerspectiveView(projectId: nil)
                        } label: {
                            BereanOSHubQuickActionChip(icon: "person.3.fill", label: "Perspectives")
                        }
                        .buttonStyle(.plain)
                    }
                    if flags.bereanOSDebateEngineEnabled {
                        NavigationLink {
                            BereanDebateView(projectId: nil)
                        } label: {
                            BereanOSHubQuickActionChip(icon: "bubble.left.and.bubble.right.fill", label: "Debate")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Projects Section

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "My Projects",
                destination: AnyView(BereanProjectDashboardView())
            )
            if projectService.projects.isEmpty {
                emptyProjectsState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(projectService.projects.prefix(4)) { project in
                            BereanProjectCardView(project: project)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var emptyProjectsState: some View {
        HStack {
            Text("Start your first project")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            NavigationLink("Create Project") {
                BereanProjectDashboardView()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal)
    }

    // MARK: - Knowledge Feed Section

    private var knowledgeFeedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Knowledge Feed",
                destination: AnyView(BereanKnowledgeFeedView())
            )
            if feedService.feedItems.isEmpty {
                Text("No knowledge updates yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    ForEach(feedService.feedItems.prefix(3)) { item in
                        feedItemRow(item)
                    }
                }
            }
        }
    }

    private func feedItemRow(_ item: BereanFeedItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(item.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Advisory Boards Section

    private var advisoryBoardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Advisory Boards",
                destination: AnyView(BereanAdvisoryBoardView())
            )
            NavigationLink {
                BereanAdvisoryBoardView()
            } label: {
                listRow(icon: "person.2.badge.gearshape.fill", label: "Advisory Boards")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Mentorship Section

    private var mentorshipSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                BereanMentorDashboardView()
            } label: {
                listRow(icon: "person.2.fill", label: "Mentorship")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Knowledge Graph Section

    private var knowledgeGraphSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                BereanKnowledgeGraphView()
            } label: {
                listRow(icon: "network", label: "Knowledge Graph")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Reusable Helpers

    private func sectionHeader(title: String, destination: AnyView?) -> some View {
        HStack {
            Text(title)
                .font(.title3.bold())
            Spacer()
            if let destination {
                NavigationLink("See All") { destination }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func listRow(icon: String, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.accent)
                .font(.title3)
                .frame(width: 28)
            Text(label)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - BereanOSHubQuickActionChip

private struct BereanOSHubQuickActionChip: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 50, height: 50)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            Text(label)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .frame(width: 70)
    }
}

// MARK: - BereanOSSearchSheet (inline, lightweight)

private struct BereanOSSearchSheet: View {
    @StateObject private var searchService = BereanOSSearchService.shared
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if searchService.isSearching {
                    HStack {
                        ProgressView()
                        Text("Searching\u{2026}")
                            .foregroundStyle(.secondary)
                    }
                } else if !searchService.results.projects.isEmpty {
                    Section("Projects") {
                        ForEach(searchService.results.projects) { project in
                            VStack(alignment: .leading) {
                                Text(project.title).font(.headline)
                                Text(project.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                } else if !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, prompt: "Search projects, knowledge, notes\u{2026}")
            .onChange(of: query) { _, newValue in
                searchService.search(newValue)
            }
            .navigationTitle("Search Berean OS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

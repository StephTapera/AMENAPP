// AmenCreatorWorkspaceView.swift
// AMENAPP
// Creator workspace hub: draft queue, content performance summary,
// and quick-launch for Universal Create.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AmenCreatorWorkspaceViewModel: ObservableObject {
    @Published var drafts: [AmenCreationDraft] = []
    @Published var recentPostStats: [PostPerformanceStat] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private let draftStore = AmenCreationDraftStore.shared

    struct PostPerformanceStat: Identifiable {
        let id: String
        let title: String
        let impressions: Int
        let reactions: Int
        let comments: Int
        let publishedAt: Date
    }

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }

        // Load recent published posts for performance summary
        do {
            let snap = try await db.collection("posts")
                .whereField("authorId", isEqualTo: uid)
                .order(by: "createdAt", descending: true)
                .limit(to: 10)
                .getDocuments()
            recentPostStats = snap.documents.compactMap { doc -> PostPerformanceStat? in
                let d = doc.data()
                guard let ts = (d["createdAt"] as? Timestamp)?.dateValue() else { return nil }
                let text = d["text"] as? String ?? ""
                return PostPerformanceStat(
                    id: doc.documentID,
                    title: String(text.prefix(50)).isEmpty ? "Untitled" : String(text.prefix(50)),
                    impressions: d["impressionCount"] as? Int ?? 0,
                    reactions: d["reactionCount"] as? Int ?? 0,
                    comments: d["commentCount"] as? Int ?? 0,
                    publishedAt: ts
                )
            }
        } catch {
            dlog("[AmenCreatorWorkspaceViewModel] load error: \(error)")
        }
    }
}

// MARK: - View

struct AmenCreatorWorkspaceView: View {
    @StateObject private var vm = AmenCreatorWorkspaceViewModel()
    @StateObject private var scheduler = AmenCreationSchedulerService.shared
    @State private var showComposer = false
    @State private var showTemplates = false
    @State private var selectedIntent: AmenCreationIntent = .textPost

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Action row: Create or From Template
                    actionRow

                    // Quick create grid
                    quickCreateSection

                    // Scheduled posts badge
                    if !scheduler.scheduledPosts.isEmpty {
                        scheduledPostsBadge
                    }

                    // Recent performance
                    if !vm.recentPostStats.isEmpty {
                        performanceSection
                    }

                    if vm.isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .navigationTitle("Creator Workspace")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await vm.load()
                scheduler.startObserving()
            }
            .onDisappear { scheduler.stopObserving() }
            .sheet(isPresented: $showComposer) {
                NavigationStack {
                    AmenAdaptiveComposerView(intent: selectedIntent)
                }
            }
            .sheet(isPresented: $showTemplates) {
                AmenCreationTemplateLibraryView { template in
                    selectedIntent = template.intent
                    showTemplates = false
                    showComposer = true
                } onDismiss: {
                    showTemplates = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AmenScheduledPostsView()
                    } label: {
                        Label("Scheduled", systemImage: "calendar.badge.clock")
                    }
                }
            }
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                selectedIntent = .textPost
                showComposer = true
            } label: {
                Label("Create", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                showTemplates = true
            } label: {
                Label("Templates", systemImage: "rectangle.grid.2x2")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Scheduled Posts Badge

    private var scheduledPostsBadge: some View {
        NavigationLink {
            AmenScheduledPostsView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(Color.accentColor)
                Text("\(scheduler.scheduledPosts.count) post\(scheduler.scheduledPosts.count == 1 ? "" : "s") scheduled")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Create

    private var quickCreateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(AmenCreationIntent.allCases) { intent in
                    Button {
                        selectedIntent = intent
                        showComposer = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: intent.icon)
                                .font(.systemScaled(16, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                            Text(intent.displayName)
                                .font(.systemScaled(14, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Performance

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Performance")
                .font(.headline)

            ForEach(vm.recentPostStats.prefix(5)) { stat in
                performanceRow(stat)
                if stat.id != vm.recentPostStats.prefix(5).last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func performanceRow(_ stat: AmenCreatorWorkspaceViewModel.PostPerformanceStat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(stat.title)
                .font(.systemScaled(14, weight: .medium))
                .lineLimit(1)

            HStack(spacing: 16) {
                statPill(icon: "eye", value: stat.impressions, label: "views")
                statPill(icon: "heart", value: stat.reactions, label: "reactions")
                statPill(icon: "bubble.left", value: stat.comments, label: "comments")
                Spacer()
                Text(stat.publishedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statPill(icon: String, value: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.systemScaled(11))
                .foregroundStyle(.secondary)
            Text(formatCount(value))
                .font(.systemScaled(12, weight: .medium))
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

// MARK: - AmenCreationIntent icon

private extension AmenCreationIntent {
    var icon: String {
        switch self {
        case .textPost:        return "text.alignleft"
        case .photoPost:       return "photo"
        case .videoPost:       return "video"
        case .carousel:        return "rectangle.stack"
        case .note:            return "note.text"
        case .selahReflection: return "sparkles"
        case .churchNote:      return "building.columns"
        case .designCard:      return "paintbrush"
        case .discussionPrompt: return "bubble.left.and.bubble.right"
        }
    }
}

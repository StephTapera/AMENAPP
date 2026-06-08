// BookCommunityModule.swift
// AMEN App — Community Around Content OS
//
// Models, services, and views for book-type ContentObjects.
// Depends on CommunityOSContracts.swift — do NOT redefine types from that file.

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - BookMetadata

struct BookMetadata: Codable, Equatable {
    var authorName: String
    var publisher: String?
    var publicationYear: Int?
    var isbn: String?
    var pageCount: Int?
    var chapterCount: Int?
    var genre: String
}

// MARK: - ReadingPlan

struct ReadingPlan: Identifiable, Codable {
    var id: String
    var title: String
    var contentObjectId: String
    var totalDays: Int
    var dailyPageTarget: Int?
    var communityId: String?
    var createdByUserId: String
    var createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, title, contentObjectId, totalDays, dailyPageTarget, communityId, createdByUserId, createdAt
    }

    init(id: String, title: String, contentObjectId: String, totalDays: Int,
         dailyPageTarget: Int? = nil, communityId: String? = nil,
         createdByUserId: String, createdAt: Date) {
        self.id = id; self.title = title; self.contentObjectId = contentObjectId
        self.totalDays = totalDays; self.dailyPageTarget = dailyPageTarget
        self.communityId = communityId; self.createdByUserId = createdByUserId
        self.createdAt = createdAt
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        contentObjectId = try c.decode(String.self, forKey: .contentObjectId)
        totalDays = try c.decode(Int.self, forKey: .totalDays)
        dailyPageTarget = try c.decodeIfPresent(Int.self, forKey: .dailyPageTarget)
        communityId = try c.decodeIfPresent(String.self, forKey: .communityId)
        createdByUserId = try c.decode(String.self, forKey: .createdByUserId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(contentObjectId, forKey: .contentObjectId)
        try c.encode(totalDays, forKey: .totalDays)
        try c.encodeIfPresent(dailyPageTarget, forKey: .dailyPageTarget)
        try c.encodeIfPresent(communityId, forKey: .communityId)
        try c.encode(createdByUserId, forKey: .createdByUserId)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - BookCommunityService

actor BookCommunityService {

    private let db = Firestore.firestore()

    // MARK: Reading Plans

    /// Creates a new reading plan and persists it to Firestore.
    func createReadingPlan(
        for contentObjectId: String,
        days: Int,
        communityId: String?
    ) async throws -> ReadingPlan {
        let planId = UUID().uuidString
        let plan = ReadingPlan(
            id: planId,
            title: "\(days)-Day Reading Plan",
            contentObjectId: contentObjectId,
            totalDays: days,
            dailyPageTarget: nil,
            communityId: communityId,
            createdByUserId: "",   // Caller injects the authenticated user ID in production.
            createdAt: Date()
        )

        let encoder = Firestore.Encoder()
        let data = try encoder.encode(plan)
        try await db
            .collection("contentObjects")
            .document(contentObjectId)
            .collection("readingPlans")
            .document(planId)
            .setData(data)

        dlog("[BookCommunityService] Reading plan \(planId) created for \(contentObjectId)")
        return plan
    }

    /// Returns all reading plans associated with a book, ordered newest first.
    func fetchReadingPlans(for contentObjectId: String) async throws -> [ReadingPlan] {
        let snaps = try await db
            .collection("contentObjects")
            .document(contentObjectId)
            .collection("readingPlans")
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let decoder = Firestore.Decoder()
        return snaps.documents.compactMap { doc in
            try? decoder.decode(ReadingPlan.self, from: doc.data())
        }
    }

    /// Records a user's intention to join a reading plan.
    func joinReadingPlan(_ planId: String, userId: String) async throws {
        let payload: [String: Any] = [
            "userId": userId,
            "joinedAt": FieldValue.serverTimestamp()
        ]
        // We need the contentObjectId to build the full path.
        // The plan document contains it; locate via collection group for simplicity.
        let snaps = try await db
            .collectionGroup("readingPlans")
            .whereField("id", isEqualTo: planId)
            .limit(to: 1)
            .getDocuments()

        guard let planDoc = snaps.documents.first else {
            dlog("[BookCommunityService] joinReadingPlan: plan \(planId) not found")
            return
        }

        try await planDoc.reference
            .collection("members")
            .document(userId)
            .setData(payload)

        dlog("[BookCommunityService] User \(userId) joined plan \(planId)")
    }
}

// MARK: - BookCommunityHubView

struct BookCommunityHubView: View {

    let contentObject: ContentObject

    @State private var readingPlans: [ReadingPlan] = []
    @State private var showCreatePlanSheet = false
    @State private var isLoading = false

    private let service = BookCommunityService()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                // About
                aboutSection

                // Reading Groups
                readingGroupsSection

                // Chapter Discussion placeholder
                chapterDiscussionSection

                // Reading Plans
                readingPlansSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showCreatePlanSheet) {
            CreateReadingPlanSheet(
                contentObject: contentObject,
                service: service,
                onCreated: { plan in
                    readingPlans.insert(plan, at: 0)
                }
            )
        }
        .task { await loadPlans() }
    }

    // MARK: About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "About")

            Text(contentObject.title)
                .font(.headline)
                .foregroundStyle(Color(.label))

            if let subtitle = contentObject.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
            }

            if !contentObject.themes.isEmpty {
                HStack {
                    ForEach(contentObject.themes.prefix(3), id: \.self) { theme in
                        ThemeChipView(theme: theme)
                    }
                }
            }
        }
    }

    // MARK: Reading Groups Section

    private var readingGroupsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Reading Groups")

            Text("Connect with others reading this book.")
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))

            CommunityStatsBlockView(
                memberCount: 0,
                discussionCount: contentObject.discussionCount
            )
        }
    }

    // MARK: Chapter Discussion Section

    private var chapterDiscussionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderView(title: "Chapter Discussion")
            Text("Discussions organized by chapter will appear here.")
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
        }
    }

    // MARK: Reading Plans Section

    private var readingPlansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeaderView(title: "Reading Plans")
                Spacer()
                Button("Start a Reading Plan") {
                    showCreatePlanSheet = true
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.label))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .amenGlassEffect(in: Capsule())
                .accessibilityHint("Create a new reading plan for this book")
            }

            if readingPlans.isEmpty && !isLoading {
                Text("No reading plans yet. Start one!")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.vertical, 8)
            } else {
                ForEach(readingPlans) { plan in
                    ReadingPlanRowView(plan: plan)
                }
            }
        }
    }

    // MARK: Data loading

    private func loadPlans() async {
        isLoading = true
        defer { isLoading = false }
        readingPlans = (try? await service.fetchReadingPlans(for: contentObject.id)) ?? []
        dlog("[BookCommunityHub] Loaded \(readingPlans.count) plans for \(contentObject.id)")
    }
}

// MARK: - CreateReadingPlanSheet

private struct CreateReadingPlanSheet: View {

    let contentObject: ContentObject
    let service: BookCommunityService
    let onCreated: (ReadingPlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDays: Int = 30
    @State private var isSaving = false

    private let dayOptions = [7, 14, 21, 30, 60, 90]

    var body: some View {
        NavigationStack {
            Form {
                Section("Duration") {
                    Picker("Days", selection: $selectedDays) {
                        ForEach(dayOptions, id: \.self) { d in
                            Text("\(d) days").tag(d)
                        }
                    }
                    .pickerStyle(.wheel)
                }

                Section {
                    Button(isSaving ? "Creating…" : "Create Plan") {
                        Task { await createPlan() }
                    }
                    .disabled(isSaving)
                    .amenGlassEffect(in: Capsule())
                }
            }
            .navigationTitle("New Reading Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func createPlan() async {
        isSaving = true
        defer { isSaving = false }
        if let plan = try? await service.createReadingPlan(
            for: contentObject.id,
            days: selectedDays,
            communityId: nil
        ) {
            onCreated(plan)
            dismiss()
        }
    }
}

// MARK: - ReadingPlanRowView

private struct ReadingPlanRowView: View {
    let plan: ReadingPlan

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.label))
                Text("\(plan.totalDays) days")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Shared sub-views (private to this file)

private struct SectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color(.label))
    }
}

private struct ThemeChipView: View {
    let theme: String

    var body: some View {
        Text(theme)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color(.secondaryLabel))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.secondaryLabel).opacity(0.10))
            .clipShape(Capsule())
    }
}

private struct CommunityStatsBlockView: View {
    let memberCount: Int
    let discussionCount: Int

    var body: some View {
        HStack(spacing: 20) {
            VStack {
                Text("\(memberCount)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(.label))
                Text("Reading")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            VStack {
                Text("\(discussionCount)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(.label))
                Text("Discussions")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
    }
}

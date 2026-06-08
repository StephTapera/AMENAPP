// OpportunityHubView.swift
// AMEN Community OS — Opportunity OS (A10)
//
// Scrollable feed of opportunities from an org/church, or platform-wide if orgId is nil.
// Thin wrapper over the IntegrationOS/Career/OpportunityFeedView pattern,
// adding: provenance context, capability section wiring, and Community OS feature flag.
//
// Feature-gated by communityOSOpportunityEnabled (default false).
//
// Filter chips: All, Volunteer, Jobs, Mentorship
// Uses native Picker-style chip row for segmented filtering.
//
// Design rules (C3): system colors only, Color.accentColor for interactive,
// white cards, no amenGold/amenPurple/hex.

import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseAuth

// MARK: - OpportunityHubView

struct OpportunityHubView: View {

    /// When non-nil, scopes the feed to a specific org/church.
    /// When nil, shows all visible opportunities platform-wide.
    let orgId: String?

    // MARK: Feature flag

    @AppStorage("community_os_opportunity_enabled")
    private var featureEnabled: Bool = false

    // MARK: State

    @State private var opportunities: [OpportunityPost] = []
    @State private var selectedFilter: OpportunityFilter = .all
    @State private var isLoading = false
    @State private var showComposer = false
    @State private var alertMessage: String? = nil
    @State private var showAlert = false
    @State private var applyingToPost: OpportunityPost? = nil
    @State private var showContactFlow = false
    @State private var savedIds: Set<String> = []

    private let db = Firestore.firestore()

    private var currentUserId: String { Auth.auth().currentUser?.uid ?? "" }

    // MARK: Filter enum

    enum OpportunityFilter: String, CaseIterable, Identifiable {
        case all        = "All"
        case volunteer  = "Volunteer"
        case jobs       = "Jobs"
        case mentorship = "Mentorship"

        var id: String { rawValue }

        var opportunityTypes: [CommunityOpportunityType]? {
            switch self {
            case .all:        return nil
            case .volunteer:  return [.volunteer]
            case .jobs:       return [.fullTime, .partTime, .internship]
            case .mentorship: return [.mentorship]
            }
        }
    }

    // MARK: Filtered list

    private var filteredOpportunities: [OpportunityPost] {
        var list = opportunities.filter { $0.scamRiskLevel != .flagged }
        if let types = selectedFilter.opportunityTypes {
            list = list.filter { types.contains($0.type) }
        }
        return list
    }

    // MARK: Body

    var body: some View {
        if featureEnabled {
            mainContent
        } else {
            featureGatedFallback
        }
    }

    // MARK: Feature Gated Fallback

    private var featureGatedFallback: some View {
        VStack(spacing: 16) {
            Image(systemName: "briefcase")
                .font(.largeTitle)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text("Opportunities coming soon")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            filterChipRow
                .padding(.top, 8)

            Divider()

            if isLoading {
                loadingView
            } else if filteredOpportunities.isEmpty {
                emptyState
            } else {
                opportunityList
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(orgId != nil ? "Opportunities" : "All Opportunities")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showComposer = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Post a new opportunity")
            }
        }
        .sheet(isPresented: $showComposer) {
            OpportunityComposerView { newPost in
                Task { await submitPost(newPost) }
            }
        }
        .sheet(isPresented: $showContactFlow) {
            if let post = applyingToPost {
                SafeContactFlow(
                    opportunityId: post.id,
                    opportunityTitle: post.title,
                    orgName: post.organizationName,
                    isPresented: $showContactFlow
                )
            }
        }
        .alert("Notice", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .task { await loadOpportunities() }
        .task { await loadSavedIds() }
    }

    // MARK: Filter Chip Row

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(OpportunityFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func filterChip(_ filter: OpportunityFilter) -> some View {
        let isSelected = selectedFilter == filter
        return Button {
            withAnimation(.spring(response: 0.3)) {
                selectedFilter = filter
            }
        } label: {
            Text(filter.rawValue)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected
                              ? Color(uiColor: .label).opacity(0.10)
                              : Color(uiColor: .secondarySystemFill))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.rawValue) filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text("Loading opportunities...")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "briefcase")
                .font(.systemScaled(44))
                .foregroundStyle(Color(uiColor: .quaternaryLabel))
            Text("No opportunities found")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            Text("Try a different filter, or post an opportunity to help others.")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Post an Opportunity") { showComposer = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Opportunity List

    private var opportunityList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 14) {
                ForEach(filteredOpportunities) { post in
                    OpportunityCard(
                        post: post,
                        onApply: {
                            applyingToPost = post
                            showContactFlow = true
                        },
                        onSave: { Task { await toggleSave(post) } }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: Data Loading

    private func loadOpportunities() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var query = db.collection("opportunities")
                .whereField("hidden", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)

            if let orgId {
                query = db.collection("opportunities")
                    .whereField("orgId", isEqualTo: orgId)
                    .whereField("hidden", isEqualTo: false)
                    .order(by: "createdAt", descending: true)
                    .limit(to: 50)
            }

            let snapshot = try await query.getDocuments()
            let decoder = Firestore.Decoder()
            let loaded = snapshot.documents.compactMap { doc -> OpportunityPost? in
                var data = doc.data()
                data["id"] = doc.documentID
                return try? decoder.decode(OpportunityPost.self, from: data)
            }
            await MainActor.run { opportunities = loaded }
        } catch {
            print("⚠️ [OpportunityHubView] loadOpportunities failed: \(error)")
            await MainActor.run {
                alertMessage = "Couldn't load opportunities. Please try again."
                showAlert = true
            }
        }
    }

    private func toggleSave(_ post: OpportunityPost) async {
        guard !currentUserId.isEmpty else { return }
        let ref = db.collection("users").document(currentUserId)
            .collection("savedOpportunities").document(post.id)
        if savedIds.contains(post.id) {
            try? await ref.delete()
            savedIds.remove(post.id)
        } else {
            try? await ref.setData([
                "opportunityId": post.id,
                "savedAt": FieldValue.serverTimestamp(),
                "title": post.title,
                "orgName": post.organizationName
            ])
            savedIds.insert(post.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func loadSavedIds() async {
        guard !currentUserId.isEmpty else { return }
        guard let snap = try? await db.collection("users").document(currentUserId)
            .collection("savedOpportunities").getDocuments() else { return }
        savedIds = Set(snap.documents.map { $0.documentID })
    }

    private func submitPost(_ post: OpportunityPost) async {
        do {
            let encoder = Firestore.Encoder()
            let data = try encoder.encode(post)
            try await db.collection("opportunities").document(post.id).setData(data)
            await loadOpportunities()
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Opportunity Hub — Org Scoped") {
    NavigationStack {
        OpportunityHubView(orgId: "org_preview_01")
    }
    .onAppear {
        UserDefaults.standard.set(true, forKey: "community_os_opportunity_enabled")
    }
}

#Preview("Opportunity Hub — Platform Wide") {
    NavigationStack {
        OpportunityHubView(orgId: nil)
    }
    .onAppear {
        UserDefaults.standard.set(true, forKey: "community_os_opportunity_enabled")
    }
}

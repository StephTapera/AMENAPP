// AmenOpportunityFeedView.swift
// AMEN CommunityOS — Opportunity OS (A10)
//
// Phase 3 Agent A10: Feed view for jobs, volunteer positions, and mentorship requests.
// Three-way Picker segmented by AmenOpportunityCategory.
// isFilled items are hidden by AmenOpportunityService; minors are blocked at Firestore rules layer.
//
// Design rules (C3):
//   - White cards + systemGroupedBackground page
//   - Color.accentColor for interactive affordances only
//   - No hex colors, no amenGold, no amenPurple
//   - System Dynamic Type throughout

import SwiftUI

// MARK: - AmenOpportunityFeedView

struct AmenOpportunityFeedView: View {

    @StateObject private var service = AmenOpportunityService()
    @State private var selectedCategory: AmenOpportunityCategory = .job
    @State private var showPostSheet = false
    @State private var applyingToJobId: String?
    @State private var applyingToJobTitle: String?
    @State private var applyingToOrgName: String?
    @State private var showContactFlow = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryPicker
                    .padding(.horizontal)
                    .padding(.top, 8)

                Divider()
                    .padding(.top, 4)

                contentBody
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Opportunities")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showPostSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Post a new opportunity")
                }
            }
            .sheet(isPresented: $showPostSheet) {
                OpportunityComposerView()
            }
            .sheet(isPresented: $showContactFlow) {
                if let id = applyingToJobId,
                   let title = applyingToJobTitle,
                   let org = applyingToOrgName {
                    SafeContactFlow(
                        opportunityId: id,
                        opportunityTitle: title,
                        orgName: org,
                        isPresented: $showContactFlow
                    )
                }
            }
            .task { await loadCurrentCategory() }
            .onChange(of: selectedCategory) {
                Task { await loadCurrentCategory() }
            }
        }
    }

    // MARK: Category Picker

    private var categoryPicker: some View {
        Picker("Category", selection: $selectedCategory) {
            Text("Jobs").tag(AmenOpportunityCategory.job)
            Text("Volunteer").tag(AmenOpportunityCategory.volunteerPosition)
            Text("Mentorship").tag(AmenOpportunityCategory.mentorship)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Filter opportunities by type")
    }

    // MARK: Content Body

    @ViewBuilder
    private var contentBody: some View {
        if service.isLoading {
            loadingView
        } else if isEmpty {
            emptyState
        } else {
            feedList
        }
    }

    private var isEmpty: Bool {
        switch selectedCategory {
        case .job, .internship, .referral:
            return service.jobs.isEmpty
        case .volunteerPosition, .projectCollaboration:
            return service.volunteerOpps.isEmpty
        case .mentorship:
            return service.mentorshipRequests.isEmpty
        }
    }

    // MARK: Feed List

    private var feedList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 12) {
                switch selectedCategory {
                case .job, .internship, .referral:
                    ForEach(service.jobs) { job in
                        NavigationLink {
                            AmenJobDetailView(job: job)
                        } label: {
                            AmenJobCard(job: job)
                        }
                        .buttonStyle(.plain)
                    }
                case .volunteerPosition, .projectCollaboration:
                    ForEach(service.volunteerOpps) { opp in
                        AmenVolunteerCard(opp: opp) {
                            applyingToJobId = opp.id
                            applyingToJobTitle = opp.title
                            applyingToOrgName = opp.orgName
                            showContactFlow = true
                        }
                    }
                case .mentorship:
                    ForEach(service.mentorshipRequests) { req in
                        AmenMentorshipCard(request: req) {
                            applyingToJobId = req.id
                            applyingToJobTitle = req.topic
                            applyingToOrgName = "Mentorship Request"
                            showContactFlow = true
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text("Loading opportunities\u{2026}")
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
            Image(systemName: selectedCategory.systemImage)
                .font(.system(size: 44))
                .foregroundStyle(Color(uiColor: .quaternaryLabel))
                .accessibilityHidden(true)
            Text("No \(selectedCategory.displayName) Opportunities")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            Text("Check back soon, or post one to help others.")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Post an Opportunity") { showPostSheet = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Data Loading

    private func loadCurrentCategory() async {
        try? await service.loadOpportunities(
            orgId: nil,
            category: selectedCategory,
            query: nil
        )
    }
}

// MARK: - AmenJobCard

struct AmenJobCard: View {
    let job: AmenJobPost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title)
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .label))
                        .multilineTextAlignment(.leading)
                    Text(job.organization)
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                Spacer()
                Image(systemName: "briefcase.fill")
                    .font(.body)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }

            HStack(spacing: 6) {
                Text(job.jobType.rawValue
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized)
                    .amenPillLabel()
                if job.isRemote {
                    Text("Remote").amenPillLabel()
                } else if let loc = job.location, !loc.isEmpty {
                    Text(loc).amenPillLabel()
                }
                if let salary = job.salaryRange {
                    Text(salary).amenPillLabel()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let locationPart = job.isRemote ? "Remote" : (job.location ?? "")
        let salaryPart = job.salaryRange.map { ". \($0)" } ?? ""
        return "\(job.title). \(job.organization). \(job.jobType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized). \(locationPart)\(salaryPart)."
    }
}

// MARK: - AmenVolunteerCard

struct AmenVolunteerCard: View {
    let opp: AmenVolunteerPost
    var onApply: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(opp.title)
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .label))
                        .multilineTextAlignment(.leading)
                    Text(opp.orgName)
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                Spacer()
                Image(systemName: "figure.wave")
                    .font(.body)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }

            Text(opp.description)
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .lineLimit(2)

            HStack(spacing: 6) {
                if !opp.commitment.isEmpty {
                    Text(opp.commitment).amenPillLabel()
                }
                if let loc = opp.location, !loc.isEmpty {
                    Text(loc).amenPillLabel()
                }
            }

            if let onApply {
                Button(action: onApply) {
                    Label("Apply via Amen", systemImage: "envelope")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apply to \(opp.title) via Amen Inbox")
                .accessibilityHint("No email or phone number is shown.")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - AmenMentorshipCard

struct AmenMentorshipCard: View {
    let request: AmenMentorshipPost
    var onConnect: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.topic)
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .label))
                        .multilineTextAlignment(.leading)
                    Text("Looking for a mentor")
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                Spacer()
                Image(systemName: "person.2.fill")
                    .font(.body)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }

            Text(request.description)
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .lineLimit(2)

            HStack(spacing: 6) {
                if !request.desiredFrequency.isEmpty {
                    Text(request.desiredFrequency).amenPillLabel()
                }
                Text(request.status.displayName).amenPillLabel()
            }

            if let onConnect {
                Button(action: onConnect) {
                    Label("Offer Mentorship via Amen", systemImage: "envelope")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Offer mentorship via Amen Inbox")
                .accessibilityHint("Contact goes through Amen \u{2014} no personal info is shared.")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - amenPillLabel View Extension

extension View {
    /// Applies the canonical pill/chip label style:
    /// caption weight medium, secondary foreground, horizontal padding, secondarySystemFill capsule.
    func amenPillLabel() -> some View {
        self
            .font(.caption.weight(.medium))
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(uiColor: .secondarySystemFill), in: Capsule())
    }
}

// MARK: - Preview

#Preview("Opportunity Feed") {
    AmenOpportunityFeedView()
        .onAppear {
            UserDefaults.standard.set(true, forKey: "community_os_opportunity_enabled")
        }
}

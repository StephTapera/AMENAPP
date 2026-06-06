// AmenOpportunityDetailView.swift
// AMEN CommunityOS — Opportunity OS (A10)
//
// Phase 3 Agent A10: Detail views for AmenJobPost, AmenVolunteerPost, and AmenMentorshipPost.
//
// CRITICAL: No raw email, phone, or external contact is ever shown.
// The "Apply" button routes exclusively through SafeContactFlow (Amen inbox).
//
// Design rules (C3):
//   - White content, systemGroupedBackground page background
//   - Color.accentColor for interactive elements only
//   - No hex colors, no amenGold, no custom brand colors

import SwiftUI
import FirebaseAuth

// MARK: - AmenJobDetailView

struct AmenJobDetailView: View {

    let job: AmenJobPost
    @StateObject private var service = AmenOpportunityService()
    @State private var showApplySheet = false
    @State private var isSaved = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                headerSection
                Divider()
                descriptionSection

                if !job.requirements.isEmpty {
                    requirementsSection
                }

                if !job.tags.isEmpty {
                    tagsRow(tags: job.tags)
                }

                metaSection
                applyCTA

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Job Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.spring(response: 0.3)) { isSaved.toggle() }
                    Task {
                        try? await service.saveOpportunity(
                            opportunityId: job.id,
                            category: .job,
                            userId: Auth.auth().currentUser?.uid ?? ""
                        )
                    }
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(isSaved ? Color.accentColor : Color(uiColor: .secondaryLabel))
                }
                .accessibilityLabel(isSaved ? "Saved" : "Save this job")
            }
        }
        .sheet(isPresented: $showApplySheet) {
            SafeContactFlow(
                opportunityId: job.id,
                opportunityTitle: job.title,
                orgName: job.organization,
                isPresented: $showApplySheet
            )
        }
    }

    // MARK: Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(job.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color(uiColor: .label))
                .fixedSize(horizontal: false, vertical: true)

            Text(job.organization)
                .font(.headline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))

            HStack(spacing: 8) {
                Label(
                    job.jobType.rawValue
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized,
                    systemImage: "briefcase"
                )
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))

                if job.isRemote {
                    Label("Remote", systemImage: "wifi")
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                } else if let loc = job.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.circle")
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }

            if let salary = job.salaryRange {
                Label(salary, systemImage: "dollarsign.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(uiColor: .label))
            }
        }
    }

    // MARK: Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About This Role")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            Text(job.description)
                .font(.body)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Requirements Section

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Requirements")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            ForEach(job.requirements, id: \.self) { req in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    Text(req)
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Meta Section

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let deadline = job.applicationDeadline {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .accessibilityHidden(true)
                    Text("Apply by \(deadline.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            // Privacy assurance — contactRef is never shown as raw PII
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
                Text("Applications are handled through Amen Inbox \u{2014} your contact info is never shared.")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
        }
    }

    // MARK: Apply CTA

    private var applyCTA: some View {
        Button {
            showApplySheet = true
        } label: {
            Label("Apply via Amen", systemImage: "envelope.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply to \(job.title) via Amen Inbox")
        .accessibilityHint("No email or phone number will be shared with the employer.")
    }
}

// MARK: - AmenVolunteerDetailView

struct AmenVolunteerDetailView: View {

    let opp: AmenVolunteerPost
    @StateObject private var service = AmenOpportunityService()
    @State private var showApplySheet = false
    @State private var isSaved = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                volunteerHeader
                Divider()
                volunteerDescription

                if !opp.skills.isEmpty {
                    volunteerSkills
                }

                if !opp.tags.isEmpty {
                    tagsRow(tags: opp.tags)
                }

                volunteerMeta
                volunteerApplyCTA

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Volunteer Opportunity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.spring(response: 0.3)) { isSaved.toggle() }
                    Task {
                        try? await service.saveOpportunity(
                            opportunityId: opp.id,
                            category: .volunteerPosition,
                            userId: Auth.auth().currentUser?.uid ?? ""
                        )
                    }
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(isSaved ? Color.accentColor : Color(uiColor: .secondaryLabel))
                }
                .accessibilityLabel(isSaved ? "Saved" : "Save this opportunity")
            }
        }
        .sheet(isPresented: $showApplySheet) {
            SafeContactFlow(
                opportunityId: opp.id,
                opportunityTitle: opp.title,
                orgName: opp.orgName,
                isPresented: $showApplySheet
            )
        }
    }

    private var volunteerHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(opp.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color(uiColor: .label))
            Text(opp.orgName)
                .font(.headline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            HStack(spacing: 8) {
                if !opp.commitment.isEmpty {
                    Label(opp.commitment, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                if let loc = opp.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.circle")
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
        }
    }

    private var volunteerDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About This Opportunity")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            Text(opp.description)
                .font(.body)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var volunteerSkills: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Skills Helpful")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            AmenFlowLayout(spacing: 6) {
                ForEach(opp.skills, id: \.self) { skill in
                    Text(skill).amenPillLabel()
                }
            }
        }
    }

    private var volunteerMeta: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let start = opp.startDate {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .accessibilityHidden(true)
                    Text("Starts \(start.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
                Text("Applications are handled through Amen Inbox \u{2014} your contact info is never shared.")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
        }
    }

    private var volunteerApplyCTA: some View {
        Button {
            showApplySheet = true
        } label: {
            Label("Apply via Amen", systemImage: "envelope.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply to \(opp.title) via Amen Inbox")
        .accessibilityHint("No email or phone number will be shared.")
    }
}

// MARK: - AmenMentorshipDetailView

struct AmenMentorshipDetailView: View {

    let request: AmenMentorshipPost
    @StateObject private var service = AmenOpportunityService()
    @State private var showContactSheet = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                mentorshipHeader
                Divider()
                mentorshipDescription

                if !request.skills.isEmpty {
                    mentorshipTopics
                }

                mentorshipMeta
                mentorshipOfferCTA

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Mentorship Request")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showContactSheet) {
            SafeContactFlow(
                opportunityId: request.id,
                opportunityTitle: request.topic,
                orgName: "Mentorship Request",
                isPresented: $showContactSheet
            )
        }
    }

    private var mentorshipHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.topic)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color(uiColor: .label))
            Text("Looking for a mentor")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            HStack(spacing: 8) {
                if !request.desiredFrequency.isEmpty {
                    Label(request.desiredFrequency, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                Text(request.status.displayName).amenPillLabel()
            }
        }
    }

    private var mentorshipDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What They're Looking For")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            Text(request.description)
                .font(.body)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var mentorshipTopics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Topics")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            AmenFlowLayout(spacing: 6) {
                ForEach(request.skills, id: \.self) { skill in
                    Text(skill).amenPillLabel()
                }
            }
        }
    }

    private var mentorshipMeta: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.caption)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
            Text("All contact goes through Amen Inbox \u{2014} your personal info is never shared.")
                .font(.caption)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
    }

    private var mentorshipOfferCTA: some View {
        Button {
            showContactSheet = true
        } label: {
            Label("Offer Mentorship via Amen", systemImage: "envelope.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Offer to mentor via Amen Inbox")
        .accessibilityHint("No email or phone number will be shared.")
    }
}

// MARK: - Shared Tag Row Helper

private func tagsRow(tags: [String]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text("Tags")
            .font(.headline)
            .foregroundStyle(Color(uiColor: .label))
        AmenFlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag).amenPillLabel()
            }
        }
    }
}

// AmenFlowLayout is defined in SpiritualOS/Discovery/AmenChurchHeroCard.swift (canonical).

// MARK: - Previews

#Preview("Job Detail") {
    NavigationStack {
        AmenJobDetailView(
            job: AmenJobPost(
                id: "job_preview",
                title: "Communications Director",
                organization: "Restoring Hope Foundation",
                orgId: "org_001",
                description: "Lead digital communications and social media strategy for a growing faith-based nonprofit.",
                requirements: ["3+ years communications experience", "Social media strategy", "Strong written communication"],
                jobType: .fullTime,
                experienceLevel: .midLevel,
                location: "Austin, TX",
                isRemote: false,
                salaryRange: "$55k\u{2013}$70k",
                applicationDeadline: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
                tags: ["Communications", "Nonprofit", "Faith-Based"],
                contactRef: "inbox://thread/preview",
                applicationUrl: nil,
                provenance: nil,
                postedBy: "uid_poster",
                createdAt: Date(),
                updatedAt: Date(),
                isDeleted: false,
                isFilled: false
            )
        )
    }
}

#Preview("Volunteer Detail") {
    NavigationStack {
        AmenVolunteerDetailView(
            opp: AmenVolunteerPost(
                id: "vol_preview",
                title: "Youth Group Volunteer Leader",
                orgId: "org_001",
                orgName: "Grace Community Church",
                description: "Join our team as a youth group leader. Help mentor teens through weekly Bible studies and community events.",
                commitment: "2 hours/week",
                skills: ["Leadership", "Youth Ministry", "Bible Study"],
                location: "Austin, TX",
                startDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
                tags: ["Youth", "Ministry", "Volunteer"],
                contactRef: "inbox://thread/preview",
                provenance: nil,
                postedBy: "uid_poster",
                createdAt: Date(),
                updatedAt: Date(),
                isDeleted: false,
                isFilled: false
            )
        )
    }
}

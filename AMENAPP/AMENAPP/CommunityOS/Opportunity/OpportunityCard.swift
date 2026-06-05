// OpportunityCard.swift
// AMEN Community OS — Opportunity OS (A10)
//
// Card for volunteer opportunities, jobs, and mentorships.
// "Apply via Amen" always routes through the Amen inbox — never shows raw contact info.
//
// Design rules (C3):
//   - White card + shadow(color: .black.opacity(0.07), radius: 24, x:0, y:5) + cornerRadius(28, .continuous)
//   - Color.accentColor for interactive only
//   - No amenGold / amenPurple / hex colors

import SwiftUI

// MARK: - OpportunityCard

struct OpportunityCard: View {

    let post: OpportunityPost

    /// Called when the user taps "Apply via Amen". Caller opens SafeContactFlow.
    var onApply: (() -> Void)?

    /// Called when the user taps the bookmark save button.
    var onSave: (() -> Void)?

    // MARK: State

    @State private var isSaved = false
    @State private var showFlagMenu = false

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Scam warning banner (if applicable)
            if post.scamRiskLevel == .medium || post.scamRiskLevel == .high {
                scamBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }

            // Main card body
            VStack(alignment: .leading, spacing: 10) {
                headerRow
                titleSection
                descriptionSection
                actionRow
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.07), radius: 24, x: 0, y: 5)
        )
        .confirmationDialog(
            "Report this Opportunity",
            isPresented: $showFlagMenu,
            titleVisibility: .visible
        ) {
            ForEach(ScamFlag.allCases, id: \.rawValue) { flag in
                Button(flag.displayLabel, role: .destructive) {
                    // Flag reporting routes through OpportunityService
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Header Row

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            // Org logo placeholder (32pt circle)
            ZStack {
                Circle()
                    .fill(Color(uiColor: .secondarySystemFill))
                Image(systemName: post.type.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.organizationName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(1)

                // Org verified badge
                if post.orgId != nil {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 10).weight(.medium))
                        .foregroundStyle(.mint)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                // Type badge
                typeBadge

                // Save bookmark
                Button {
                    withAnimation(.spring(response: 0.3)) { isSaved.toggle() }
                    onSave?()
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16))
                        .foregroundStyle(isSaved ? Color.accentColor : Color(uiColor: .secondaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSaved ? "Saved" : "Save opportunity")
            }
        }
    }

    // MARK: Type Badge

    private var typeBadge: some View {
        Label(post.type.rawValue, systemImage: post.type.icon)
            .font(.system(size: 10).weight(.semibold))
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
            )
    }

    // MARK: Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(post.title)
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(2)

            HStack(spacing: 4) {
                Image(systemName: post.isRemote ? "wifi" : "mappin.circle")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                Text(post.isRemote ? "Remote" : post.location)
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
    }

    // MARK: Description Section

    private var descriptionSection: some View {
        Text(post.description)
            .font(.callout)
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    // MARK: Action Row

    private var actionRow: some View {
        HStack(spacing: 10) {
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
                .accessibilityLabel("Apply via Amen Inbox")
                .accessibilityHint("Opens the Amen inbox application flow. No email or phone number is shown.")
            }

            // Flag / report button
            Button {
                showFlagMenu = true
            } label: {
                Image(systemName: "flag")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color(uiColor: .secondarySystemFill))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Report this opportunity")
        }
    }

    // MARK: Scam Banner

    @ViewBuilder
    private var scamBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: post.scamRiskLevel == .high
                  ? "exclamationmark.octagon.fill"
                  : "exclamationmark.triangle.fill")
                .foregroundStyle(post.scamRiskLevel == .high ? Color.red : Color.yellow)
                .font(.caption)
            Text(post.scamRiskLevel == .high
                 ? "This post has been flagged and is under review."
                 : "Review carefully — this post has some patterns we flag for caution.")
                .font(.caption)
                .foregroundStyle(
                    post.scamRiskLevel == .high
                    ? Color.red
                    : Color(uiColor: .secondaryLabel)
                )
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 8)
    }

    // MARK: Accessibility

    private var accessibilityDescription: String {
        "\(post.title). \(post.type.rawValue). \(post.organizationName). " +
        "\(post.isRemote ? "Remote" : post.location). " +
        "\(post.description.prefix(80)). " +
        "Apply via Amen Inbox."
    }
}

// MARK: - Preview

#Preview("Opportunity Card") {
    VStack(spacing: 16) {
        OpportunityCard(
            post: OpportunityPost(
                id: "opp_001",
                title: "Youth Group Volunteer Leader",
                description: "Join our team as a youth group leader. Help mentor teens through weekly Bible studies and community events.",
                type: .volunteer,
                organizationName: "Grace Community Church",
                orgId: "org_001",
                location: "Austin, TX",
                isRemote: false,
                compensationRange: nil,
                skillTags: ["Leadership", "Youth Ministry", "Bible Study"],
                postedByUserId: "uid_poster",
                contactMethod: .amenInboxOnly,
                createdAt: Date(),
                updatedAt: Date(),
                scamRiskLevel: .low
            ),
            onApply: { print("Apply tapped") },
            onSave: { print("Save tapped") }
        )

        OpportunityCard(
            post: OpportunityPost(
                id: "opp_002",
                title: "Communications Director",
                description: "Lead digital communications and social media strategy for a growing nonprofit.",
                type: .fullTime,
                organizationName: "Restoring Hope Foundation",
                orgId: "org_002",
                location: "",
                isRemote: true,
                compensationRange: "$55k–$70k",
                skillTags: ["Communications", "Social Media"],
                postedByUserId: "uid_poster2",
                contactMethod: .amenInboxOnly,
                createdAt: Date(),
                updatedAt: Date(),
                scamRiskLevel: .medium
            ),
            onApply: nil,
            onSave: nil
        )
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

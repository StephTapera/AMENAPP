// ApprovalSheetView.swift
// AMENAPP — ContentFlowOS
// The core approval sheet. Every share/forward action passes through here.
// Writes every decision to the audit log.

import SwiftUI

struct ApprovalSheetView: View {
    let card: ContentCard
    let proposedAction: ContentAction
    let requestorIsCreator: Bool
    let requestorIsSpaceAdmin: Bool
    let requestorIsChurchAdmin: Bool
    let requestorIsTrustedMember: Bool
    let targetSurface: ContentSurface
    let onApproved: (ContentAction, Bool) -> Void  // action, isAnonymous
    let onDenied: (String) -> Void
    let onDismiss: () -> Void

    @State private var selectedOption: ApprovalOption = .allowWithAttribution
    @State private var isAnonymous = false
    @State private var showingDenyConfirm = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var outcome: ContentPermissionOutcome {
        ContentPermissionEngine.evaluate(
            action: proposedAction,
            card: card,
            requestorIsCreator: requestorIsCreator,
            requestorIsSpaceAdmin: requestorIsSpaceAdmin,
            requestorIsChurchAdmin: requestorIsChurchAdmin,
            requestorIsTrustedMember: requestorIsTrustedMember,
            targetSurface: targetSurface
        )
    }

    private var redactionSuggestions: [ContentRedactionSuggestion] {
        ContentPermissionEngine.redactionSuggestions(for: card)
    }

    enum ApprovalOption: String, CaseIterable {
        case allowWithAttribution  = "Allow with Attribution"
        case allowAnonymously      = "Allow Anonymously"
        case allowExcerptOnly      = "Allow Excerpt Only"
        case allowThisChurchOnly   = "Allow This Church Only"
        case allowThisSpaceOnly    = "Allow This Space Only"
        case askCreator            = "Ask Creator First"
        case deny                  = "Deny"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Content preview
                    contentPreviewCard

                    // Outcome banner
                    outcomeBanner

                    // Redaction suggestions
                    if !redactionSuggestions.isEmpty {
                        redactionSection
                    }

                    // Approval options
                    if outcome.canProceed {
                        approvalOptions
                    }

                    // Action buttons
                    actionButtons
                }
                .padding(16)
            }
            .navigationTitle("Review Before Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .background(reduceTransparency ? Color(.systemBackground) : Color(.systemBackground))
        }
    }

    // MARK: - Sub-views

    private var contentPreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(card.sourceType.displayName, systemImage: card.sourceType.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(card.title)
                .font(.headline)
            if !card.body.isEmpty {
                Text(card.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            HStack(spacing: 6) {
                Image(systemName: audienceIcon)
                    .font(.caption)
                Text("Originally for: \(card.originalAudience.displayName)")
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var outcomeBanner: some View {
        let (bannerColor, bannerIcon): (Color, String) = {
            if case .denied = outcome { return (.red, "xmark.shield.fill") }
            if outcome.requiresApproval { return (.orange, "lock.fill") }
            return (.green, "checkmark.shield.fill")
        }()

        HStack(spacing: 10) {
            Image(systemName: bannerIcon)
                .font(.title3)
                .foregroundStyle(bannerColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.displayTitle)
                    .font(.subheadline.weight(.semibold))
                if outcome.requiresApproval {
                    Text("This action requires approval from the creator or an admin before proceeding.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(bannerColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var redactionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested Privacy Steps")
                .font(.subheadline.weight(.semibold))
            ForEach(redactionSuggestions) { suggestion in
                HStack(spacing: 8) {
                    Image(systemName: suggestion.type.icon)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)
                    Text(suggestion.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var approvalOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to share")
                .font(.subheadline.weight(.semibold))
            ForEach([ApprovalOption.allowWithAttribution, .allowAnonymously, .allowExcerptOnly], id: \.self) { opt in
                Button {
                    selectedOption = opt
                    isAnonymous = opt == .allowAnonymously
                } label: {
                    HStack {
                        Image(systemName: selectedOption == opt ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedOption == opt ? Color.accentColor : .secondary)
                        Text(opt.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 10) {
            if outcome.canProceed {
                Button {
                    ContentAuditLogger.log(
                        contentId: card.id,
                        contentType: card.sourceType.rawValue,
                        actorId: "current-user",
                        action: "approved",
                        destination: targetSurface.rawValue,
                        isExternal: proposedAction == .shareExternal,
                        wasAnonymous: isAnonymous,
                        approvalOutcome: selectedOption.rawValue
                    )
                    onApproved(proposedAction, isAnonymous)
                } label: {
                    Text("Confirm & Share")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            Button {
                showingDenyConfirm = true
            } label: {
                Text(outcome.canProceed ? "Deny" : "Close")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .confirmationDialog("Deny this share request?", isPresented: $showingDenyConfirm) {
                Button("Deny", role: .destructive) {
                    ContentAuditLogger.log(
                        contentId: card.id,
                        contentType: card.sourceType.rawValue,
                        actorId: "current-user",
                        action: "denied",
                        destination: targetSurface.rawValue,
                        isExternal: proposedAction == .shareExternal,
                        wasAnonymous: false,
                        approvalOutcome: "denied"
                    )
                    onDenied("Request denied.")
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var audienceIcon: String {
        switch card.originalAudience {
        case .private:       return "lock.fill"
        case .trustedCircle: return "person.3.fill"
        case .smallGroup:    return "person.2.fill"
        case .churchOnly:    return "building.columns.fill"
        case .spaceMembers:  return "rectangle.3.group.fill"
        case .paidMembers:   return "star.fill"
        case .publicFeed:    return "globe"
        }
    }
}

// MARK: - Preview

#Preview {
    ApprovalSheetView(
        card: ContentCard(
            id: "c1", title: "A prayer from our group",
            body: "Please pray for our friend going through a difficult season.",
            sourceType: .prayerRequest, sourceSurface: .space, sourceId: "s1",
            originalAudience: .smallGroup, creatorId: "u1", creatorDisplayName: "Jane D.",
            sensitivityScore: 0.6, hasPrayerContent: true, hasChildContent: false,
            hasLocationData: false, hasMinors: false, isAnonymous: false,
            isPaidContent: false, isDM: false, isChurchInternal: false,
            createdAt: Date(), expiresAt: nil, moderationState: .safe,
            discussionStatus: .open,
            attributionRules: ContentAttributionRules(requiresAttribution: true, allowsAnonymous: true, allowsQuoteOnly: false, expiresAfterDays: nil)
        ),
        proposedAction: .discussInSpace,
        requestorIsCreator: false,
        requestorIsSpaceAdmin: false,
        requestorIsChurchAdmin: false,
        requestorIsTrustedMember: true,
        targetSurface: .space,
        onApproved: { _, _ in },
        onDenied: { _ in },
        onDismiss: {}
    )
}

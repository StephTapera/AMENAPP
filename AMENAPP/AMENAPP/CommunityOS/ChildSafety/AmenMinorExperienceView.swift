// AmenMinorExperienceView.swift
// AMENAPP — CommunityOS/ChildSafety
//
// Phase 4 Agent TS-c — Child Safety
//
// The restricted experience shown to minor users when they attempt to access
// a blocked or restricted capability. Uses the white Liquid Glass design system.
//
// Accessibility: All interactive elements have explicit accessibilityLabel.
// White LG design: .ultraThinMaterial background, system-grouped background.
//
// Phase 4 Agent TS-c
// C5 §4c / MinorProtectionConfig.blockedCapabilities

import SwiftUI
import FirebaseFirestore

// MARK: - AmenMinorExperienceView

/// The restricted experience shown to minor users when they try to access
/// a feature blocked by MinorProtectionConfig.blockedCapabilities.
///
/// Shows a friendly explanation and an optional guardian contact button
/// if the user has a linked guardian account.
struct AmenMinorExperienceView: View {

    let userId: String

    /// The internal capability key that was attempted (e.g. "sendDM", "viewJobs").
    let blockedFeature: String

    @State private var guardianLinked: Bool = false
    @State private var isCheckingGuardian: Bool = true

    // MARK: - Computed

    private var featureDisplayName: String {
        switch blockedFeature {
        case "sendDM":           return "Direct Messages"
        case "viewJobs":         return "Job Listings"
        case "postPublicly":     return "Public Posting"
        case "joinOpenSpaces":   return "Open Spaces"
        case "shareLocation":    return "Location Sharing"
        case "createLiveRoom":   return "Live Rooms"
        case "viewAnalytics":    return "Analytics"
        case "purchasePremium":  return "Premium Features"
        case "viewAdultContent": return "This Content"
        default:                 return "This Feature"
        }
    }

    private var bodyMessage: String {
        switch blockedFeature {
        case "sendDM":
            return "Direct messages are available once a parent or guardian approves your account for messaging."
        case "viewJobs":
            return "Job listings are available to members 18 and older."
        case "purchasePremium":
            return "Premium features require a parent or guardian to complete the purchase."
        case "createLiveRoom":
            return "Live broadcasting is available to members 18 and older."
        case "viewAdultContent":
            return "This content is available to members 18 and older."
        default:
            return "Some features are restricted for accounts under 18. Ask a parent or guardian to unlock this."
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Shield icon
            Image(systemName: "person.badge.shield.checkmark")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(Color.secondary)
                .accessibilityHidden(true)
                .padding(.bottom, 4)

            // Title
            Text("\(featureDisplayName) isn't available yet")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            // Body message
            Text(bodyMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            // Guardian contact button — only shown if guardian is linked
            if !isCheckingGuardian && guardianLinked {
                Button {
                    contactGuardian()
                } label: {
                    Label("Contact guardian", systemImage: "envelope")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(uiColor: .systemBlue))
                .accessibilityLabel("Contact your guardian to request access to \(featureDisplayName)")
            }

            // Learn more link
            Button {
                // Opens the in-app minor safety guide (navigation handled by parent)
            } label: {
                Text("Learn about account settings")
                    .font(.footnote)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Learn about account settings for under-18 accounts")

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await checkGuardianLink()
        }
    }

    // MARK: - Private

    private func checkGuardianLink() async {
        defer { isCheckingGuardian = false }
        do {
            let db = Firestore.firestore()
            let doc = try await db
                .collection("guardianLinkRequests")
                .whereField("minorId", isEqualTo: userId)
                .whereField("status", isEqualTo: "verified")
                .limit(to: 1)
                .getDocuments()
            guardianLinked = !doc.documents.isEmpty
        } catch {
            // If we can't check, assume no guardian is linked — conservative UI.
            guardianLinked = false
        }
    }

    private func contactGuardian() {
        // Triggers a push notification to the linked guardian's device via CF.
        // The guardian receives an in-app notification linking to the minor's
        // settings where they can approve/deny the request.
        // This is a CF-mediated action; the iOS client writes a contact request
        // and the CF delivers it — no direct contact info is exchanged.
        Task {
            let db = Firestore.firestore()
            let request: [String: Any] = [
                "minorId": userId,
                "blockedFeature": blockedFeature,
                "requestType": "guardian_unlock_request",
                "createdAt": FieldValue.serverTimestamp()
            ]
            try? await db.collection("guardianContactRequests").addDocument(data: request)
        }
    }
}

// MARK: - AmenMinorExperienceBanner

/// Compact inline banner variant for use within list rows or feature tiles.
/// Shows a shield badge + short message instead of a full-screen view.
struct AmenMinorExperienceBanner: View {

    let blockedFeature: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.badge.shield.checkmark")
                .font(.system(size: 18))
                .foregroundStyle(Color.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Restricted for under-18")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("Ask a parent or guardian to enable this feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Restricted for under-18 accounts. Ask a parent or guardian to enable \(blockedFeature).")
    }
}

// MARK: - Preview

#Preview("Full screen") {
    AmenMinorExperienceView(userId: "preview-minor", blockedFeature: "sendDM")
}

#Preview("Banner") {
    AmenMinorExperienceBanner(blockedFeature: "viewJobs")
        .padding()
}

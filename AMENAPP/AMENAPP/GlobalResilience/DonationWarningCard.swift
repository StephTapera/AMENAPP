// DonationWarningCard.swift
// AMEN — Global Resilience System
// Trust-enforced warning card for donation requests.
// The client cannot override "warning" or "block" levels returned by the CF.

import SwiftUI
import FirebaseFunctions
import FirebaseFirestore

// MARK: - DonationWarningCard

/// Renders a safety banner above (or replacing) a donate button depending on
/// the trust-scoring level resolved from the backend.
///
/// - Parameters:
///   - warningLevel: Initial level hint from the caller. Always overridden by
///     the live result from `trustScoring-checkDonationSafety`.
///   - warningText: Human-readable explanation shown in caution/warning states.
///   - recipientDisplayName: Display name used in accessible descriptions.
///   - recipientId: Firestore UID passed to the CF for live scoring.
struct DonationWarningCard: View {

    // MARK: Input

    let warningLevel: String
    let warningText: String
    let recipientDisplayName: String
    let recipientId: String

    // MARK: State

    /// Live level returned from the Cloud Function. Overrides `warningLevel`
    /// for "warning" and "block" once fetched. Client cannot downgrade these.
    @State private var liveWarningLevel: String
    @State private var dismissed: Bool = false
    @State private var fetchError: Bool = false

    // MARK: Init

    init(
        warningLevel: String,
        warningText: String,
        recipientDisplayName: String,
        recipientId: String
    ) {
        self.warningLevel = warningLevel
        self.warningText = warningText
        self.recipientDisplayName = recipientDisplayName
        self.recipientId = recipientId
        // Seed with the caller-supplied level; will be replaced by CF result.
        _liveWarningLevel = State(initialValue: warningLevel)
    }

    // MARK: Computed

    /// The effective warning level the UI renders. Client-supplied "none" or
    /// "caution" can be upgraded by the CF; CF "warning"/"block" are final.
    private var effectiveLevel: String {
        // If the live level is more severe than the seeded value, use it.
        let rank: [String: Int] = ["none": 0, "caution": 1, "warning": 2, "block": 3]
        let liveRank = rank[liveWarningLevel] ?? 0
        let seedRank = rank[warningLevel] ?? 0
        return liveRank >= seedRank ? liveWarningLevel : warningLevel
    }

    // MARK: Body

    var body: some View {
        Group {
            switch effectiveLevel {
            case "none":
                EmptyView()

            case "caution":
                if !dismissed {
                    cautionBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

            case "warning":
                warningCard

            case "block":
                blockCard

            default:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: effectiveLevel)
        .onAppear {
            fetchLiveWarningLevel()
        }
    }

    // MARK: Caution Banner (dismissable, yellow)

    private var cautionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.yellow)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Donation Caution")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                if !warningText.isEmpty {
                    Text(warningText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    dismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Circle().fill(.regularMaterial))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss donation caution for \(recipientDisplayName)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.yellow.opacity(0.18))
                .glassEffect()
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.yellow.opacity(0.45), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Donation caution for \(recipientDisplayName). \(warningText)")
    }

    // MARK: Warning Card (non-dismissable, orange)

    private var warningCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.orange)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Unverified Donation Request")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(
                    "AMEN could not verify this donation request. Do not send money unless you personally know and trust the recipient."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.15))
                .glassEffect()
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.5), lineWidth: 1.5)
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Warning: AMEN could not verify the donation request from \(recipientDisplayName). Do not send money unless you personally know and trust the recipient."
        )
    }

    // MARK: Block Card (non-dismissable, red, replaces donate button)

    private var blockCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.slash.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.red)
                .accessibilityHidden(true)

            Text("This donation request has been blocked.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.15))
                .glassEffect()
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.55), lineWidth: 1.5)
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Blocked: The donation request from \(recipientDisplayName) has been blocked by AMEN."
        )
    }

    // MARK: Cloud Function Fetch

    /// Calls `trustScoring-checkDonationSafety` and upgrades `liveWarningLevel`
    /// if the backend returns a more severe result. The client can never
    /// downgrade a "warning" or "block" returned here.
    private func fetchLiveWarningLevel() {
        let functions = Functions.functions()
        let payload: [String: Any] = ["recipientId": recipientId]

        functions.httpsCallable("trustScoring-checkDonationSafety")
            .call(payload) { result, error in
                guard error == nil,
                      let data = result?.data as? [String: Any],
                      let level = data["warningLevel"] as? String else {
                    // On CF error: fail safe — keep existing level, do not expose donate button.
                    fetchError = true
                    return
                }

                let rank: [String: Int] = ["none": 0, "caution": 1, "warning": 2, "block": 3]
                let newRank = rank[level] ?? 0
                let currentRank = rank[liveWarningLevel] ?? 0

                // Only upgrade, never downgrade.
                if newRank > currentRank {
                    DispatchQueue.main.async {
                        liveWarningLevel = level
                    }
                } else if newRank <= currentRank {
                    // Accept same-or-lower from CF only if current is still "none"/"caution".
                    // "warning" and "block" are final — client cannot clear them.
                    let isFinal = currentRank >= 2
                    if !isFinal {
                        DispatchQueue.main.async {
                            liveWarningLevel = level
                        }
                    }
                }
            }
    }
}

// MARK: - Preview

#Preview("DonationWarningCard — all levels") {
    ScrollView {
        VStack(spacing: 20) {
            DonationWarningCard(
                warningLevel: "none",
                warningText: "",
                recipientDisplayName: "Grace Church",
                recipientId: "preview-uid-none"
            )

            DonationWarningCard(
                warningLevel: "caution",
                warningText: "This account has not linked a verified ministry.",
                recipientDisplayName: "John Smith",
                recipientId: "preview-uid-caution"
            )

            DonationWarningCard(
                warningLevel: "warning",
                warningText: "",
                recipientDisplayName: "Unknown Ministry",
                recipientId: "preview-uid-warning"
            )

            DonationWarningCard(
                warningLevel: "block",
                warningText: "",
                recipientDisplayName: "Blocked Account",
                recipientId: "preview-uid-block"
            )
        }
        .padding(.vertical, 24)
    }
    .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
}

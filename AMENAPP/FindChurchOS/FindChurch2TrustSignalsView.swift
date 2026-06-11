// FindChurch2TrustSignalsView.swift
// AMENAPP — Find Church 2.0, Wave 5
//
// Trust signals section rendered on every church profile when the
// findChurch2_trustSignals Remote Config flag is enabled.
//
// Design rules (HARD — do not relax):
//   - Glass: .ultraThinMaterial only — no nested materials, no custom opacity stacks
//   - Luminous border: Color.white.opacity(0.45) strokeBorder 0.5pt
//   - Shadow: radius 4, y 2, opacity 0.10
//   - Absent data MUST be visible — render "Not provided" in secondary italic style
//   - NEVER use `if let` to hide absent rows — always show with fallback
//   - All interactive targets ≥ 44×44pt
//   - Dynamic Type text styles only — no fixed point sizes
//   - @Environment(\.accessibilityReduceTransparency) guards glass backgrounds
//   - @Environment(\.accessibilityReduceMotion) guards animations
//
// Flag gate: AMENFeatureFlags.shared.findChurch2TrustSignalsEnabled
// Collection write: reports/{uuid} — type: "church_profile_inaccuracy"

import SwiftUI
import SafariServices
import FirebaseFirestore
import FirebaseAuth

// MARK: - BeliefTagPill (private)

/// Glass pill showing a belief category label and its value.
private struct BeliefTagPill: View {
    let tag: BeliefTag

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 4) {
            Text(tag.category)
                .font(.system(.caption2).weight(.medium))
                .foregroundStyle(.secondary)
            Text(tag.value)
                .font(.system(.caption2).weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(pillBackground)
        .overlay(pillBorder)
        .clipShape(Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tag.category): \(tag.value)")
    }

    @ViewBuilder
    private var pillBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var pillBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
    }
}

// MARK: - TrustInfoRow (private)

/// A label–value row. When `value` is nil the row shows "Not provided"
/// in secondary italic style — the row is NEVER hidden.
private struct TrustInfoRow: View {
    let label: String
    let value: String?            // nil = not provided
    let isLink: Bool              // true = render value as a tappable link
    let onLinkTap: (() -> Void)?  // called only when isLink && value != nil

    init(
        label: String,
        value: String?,
        isLink: Bool = false,
        onLinkTap: (() -> Void)? = nil
    ) {
        self.label = label
        self.value = value
        self.isLink = isLink
        self.onLinkTap = onLinkTap
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(.subheadline))
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .leading)

            Spacer()

            if let v = value {
                if isLink {
                    Button {
                        onLinkTap?()
                    } label: {
                        Text(v)
                            .font(.system(.subheadline).weight(.medium))
                            .foregroundStyle(.blue)
                            .multilineTextAlignment(.trailing)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(label): \(v), opens link")
                    .frame(minHeight: 44)
                } else {
                    Text(v)
                        .font(.system(.subheadline).weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("\(label): \(v)")
                }
            } else {
                Text("Not provided")
                    .font(.system(.subheadline).italic())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(label): Not provided")
            }
        }
        .frame(minHeight: 44)
    }
}

// MARK: - SafariSheet (private)

private struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - ReportSheet (private)

private struct ReportSheet: View {
    let churchId: String
    @Binding var isPresented: Bool

    @State private var reportText: String = ""
    @State private var isSending: Bool = false
    @State private var didSend: Bool = false
    @State private var sendError: String? = nil

    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Is the information on this profile incorrect?")
                    .font(.system(.body))
                    .foregroundStyle(.primary)

                TextEditor(text: $reportText)
                    .font(.system(.body))
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
                    .accessibilityLabel("Describe the issue")

                if let error = sendError {
                    Text(error)
                        .font(.system(.footnote))
                        .foregroundStyle(.red)
                }

                if didSend {
                    Text("Report sent. Thank you.")
                        .font(.system(.footnote))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Report an Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .accessibilityLabel("Cancel report")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await sendReport() }
                    } label: {
                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Send Report")
                        }
                    }
                    .disabled(reportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending || didSend)
                    .accessibilityLabel("Send report")
                }
            }
        }
    }

    @MainActor
    private func sendReport() async {
        isSending = true
        sendError = nil

        let trimmed = reportText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSending = false
            return
        }

        let reportId = UUID().uuidString
        let uid = Auth.auth().currentUser?.uid ?? "anonymous"

        let payload: [String: Any] = [
            "type": "church_profile_inaccuracy",
            "churchId": churchId,
            "reporterId": uid,
            "body": trimmed,
            "createdAt": FieldValue.serverTimestamp()
        ]

        do {
            try await db.collection("reports").document(reportId).setData(payload)
            didSend = true
            // Auto-dismiss after a brief moment so the user sees confirmation
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            isPresented = false
        } catch {
            sendError = "Could not send report. Please try again."
        }

        isSending = false
    }
}

// MARK: - TrustGlassCard (private)

/// Shared glass card container used by each trust-signals section.
private struct TrustGlassCard<Content: View>: View {
    let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
    }
}

// MARK: - FindChurch2TrustSignalsView

/// Trust-signals section for a church profile. Renders 5 sections:
///   1. Verification badge
///   2. Child safety
///   3. Accessibility
///   4. Beliefs transparency (verified churches only)
///   5. Report button
///
/// Gated by `AMENFeatureFlags.shared.findChurch2TrustSignalsEnabled`.
/// Absent data is ALWAYS shown as "Not provided" — rows are never hidden.
struct FindChurch2TrustSignalsView: View {

    let church: ChurchObject

    // MARK: Internal state

    @State private var safariURL: URL? = nil
    @State private var showSafari: Bool = false
    @State private var showReport: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Init

    init(church: ChurchObject) {
        self.church = church
    }

    // MARK: - Body

    var body: some View {
        // Hard gate: entire view is hidden when flag is off.
        // (Callers should also check the flag; this is a belt-and-suspenders guard.)
        if AMENFeatureFlags.shared.findChurch2TrustSignalsEnabled {
            VStack(alignment: .leading, spacing: 14) {
                // Section header
                Text("Trust & Transparency")
                    .font(.system(.title3).weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                // 1 — Verification badge
                verificationSection

                // 2 — Child safety
                childSafetySection

                // 3 — Accessibility
                accessibilitySection

                // 4 — Beliefs transparency
                beliefsSection

                // 5 — Report
                reportButton
            }
            .sheet(isPresented: $showSafari) {
                if let url = safariURL {
                    SafariSheet(url: url)
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showReport) {
                ReportSheet(churchId: church.id, isPresented: $showReport)
            }
        }
    }

    // MARK: - 1. Verification badge section

    @ViewBuilder
    private var verificationSection: some View {
        TrustGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Verification")
                    .font(.system(.footnote).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)

                verificationContent
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var verificationContent: some View {
        switch church.claimState {
        case .unclaimed:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .font(.system(.body))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unverified")
                        .font(.system(.body).weight(.semibold))
                        .foregroundStyle(.primary)
                    Button {
                        // Claim portal entry point — navigated via claimPortal flag
                        // (actual nav handled by the parent church profile view)
                    } label: {
                        Text("Is this your church? Help us verify")
                            .font(.system(.subheadline))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Is this your church? Help us verify. Tap to start verification.")
                }
            }

        case .pending:
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(.body))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Verification pending")
                    .font(.system(.body).weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Verification is pending review")

        case .verified:
            verifiedBadgeContent
        }
    }

    @ViewBuilder
    private var verifiedBadgeContent: some View {
        switch church.verificationTier {
        case .domain:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(.body))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Email-verified")
                        .font(.system(.body).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Verified via church email domain")
                        .font(.system(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Email-verified church")

        case .ein, .manual:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(.body))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verified church")
                        .font(.system(.body).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(church.verificationTier == .ein
                         ? "IRS EIN verified"
                         : "Verified by AMEN team")
                        .font(.system(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Verified church")

        case .none:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(.body))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Claimed")
                    .font(.system(.body).weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Church profile has been claimed")
        }
    }

    // MARK: - 2. Child safety section

    @ViewBuilder
    private var childSafetySection: some View {
        TrustGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Child Safety")
                    .font(.system(.footnote).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)

                // Child Safety Policy row — always shown
                TrustInfoRow(
                    label: "Child Safety Policy",
                    value: childSafetyPolicyValue,
                    isLink: church.childSafetyPolicy.hasFormalPolicy == true
                        && church.childSafetyPolicy.policyURL != nil,
                    onLinkTap: {
                        if let urlStr = church.childSafetyPolicy.policyURL,
                           let url = URL(string: urlStr) {
                            safariURL = url
                            showSafari = true
                        }
                    }
                )

                Divider()

                // Background Checks row — always shown
                TrustInfoRow(
                    label: "Background Checks",
                    value: backgroundChecksValue
                )

                // "Learn more" link — shown only when a policy URL exists
                if let urlStr = church.childSafetyPolicy.policyURL,
                   let url = URL(string: urlStr) {
                    Button {
                        safariURL = url
                        showSafari = true
                    } label: {
                        Label("Learn more", systemImage: "arrow.up.right")
                            .font(.system(.footnote).weight(.medium))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Learn more about child safety policy. Opens in browser.")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var childSafetyPolicyValue: String? {
        switch church.childSafetyPolicy.hasFormalPolicy {
        case .none:
            return nil   // TrustInfoRow shows "Not provided"
        case .some(true):
            if church.childSafetyPolicy.policyURL != nil {
                return "Yes — view policy"
            }
            return "Yes — formal policy on file"
        case .some(false):
            return "No formal policy"
        }
    }

    private var backgroundChecksValue: String? {
        guard let required = church.childSafetyPolicy.backgroundChecksRequired else { return nil }
        return required ? "Required for all volunteers" : "Not required"
    }

    // MARK: - 3. Accessibility section

    @ViewBuilder
    private var accessibilitySection: some View {
        TrustGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Accessibility")
                    .font(.system(.footnote).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)

                // ASL — Bool stored as a definite value; treat false as "no"
                TrustInfoRow(
                    label: "ASL interpretation",
                    value: church.accessibility.hasASL ? "Yes" : "No"
                )

                Divider()

                // Wheelchair
                TrustInfoRow(
                    label: "Wheelchair accessible",
                    value: church.accessibility.isWheelchairAccessible ? "Yes" : "No"
                )

                Divider()

                // Languages — always shown
                TrustInfoRow(
                    label: "Languages",
                    value: languagesValue
                )

                Divider()

                // Childcare
                TrustInfoRow(
                    label: "Childcare",
                    value: church.accessibility.hasChildcare ? "Available" : "Not available"
                )

                Divider()

                // Parking — nil = "Not provided"
                TrustInfoRow(
                    label: "Parking",
                    value: church.accessibility.parkingNotes
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Human-readable language list. Returns nil only if languages array is empty.
    private var languagesValue: String? {
        let langs = church.accessibility.languages
        guard !langs.isEmpty else { return nil }
        // Single "en" with no others = "English only"
        if langs == ["en"] { return "English only" }
        let locale = Locale.current
        let names = langs.compactMap { code -> String? in
            locale.localizedString(forLanguageCode: code)
        }
        guard !names.isEmpty else { return langs.joined(separator: ", ") }
        return names.joined(separator: ", ")
    }

    // MARK: - 4. Beliefs transparency section

    @ViewBuilder
    private var beliefsSection: some View {
        TrustGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("What we believe")
                    .font(.system(.footnote).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .accessibilityAddTraits(.isHeader)

                if church.claimState == .verified, let beliefs = church.beliefs {
                    let tags = beliefs.allTags
                    if tags.isEmpty {
                        // Verified but no belief tags yet
                        Text("Beliefs not listed")
                            .font(.system(.subheadline).italic())
                            .foregroundStyle(.secondary)
                    } else {
                        // Wrapping flow layout using LazyVGrid with flexible columns
                        beliefTagsFlow(tags: tags)
                    }
                } else {
                    // Not verified, or verified but beliefs == nil:
                    // Always show the row — never hide it.
                    Text("Beliefs not listed")
                        .font(.system(.subheadline).italic())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func beliefTagsFlow(tags: [BeliefTag]) -> some View {
        // Approximate wrapping flow: 2-column adaptive grid.
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 120, maximum: 260), spacing: 8, alignment: .leading)
            ],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(tags, id: \.self) { tag in
                BeliefTagPill(tag: tag)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Church beliefs: \(tags.map { "\($0.category) \($0.value)" }.joined(separator: ", "))")
    }

    // MARK: - 5. Report button

    @ViewBuilder
    private var reportButton: some View {
        HStack {
            Spacer()
            Button {
                showReport = true
            } label: {
                Text("Report an issue")
                    .font(.system(.footnote))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .accessibilityLabel("Report an issue with this church profile")
            Spacer()
        }
    }
}

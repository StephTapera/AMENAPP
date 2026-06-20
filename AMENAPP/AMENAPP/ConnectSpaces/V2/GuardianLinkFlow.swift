//  GuardianLinkFlow.swift
//  AMEN Connect V1 — verify-guardian flow (spec §9 GuardianLinkFlow). Unlocks child cards.
//
//  Gated by AMENFeatureFlags.connectGuardianLinkEnabled (default OFF). Renders nothing when off,
//  so it is inert until the flag is flipped for testing. All trust is server-side: this view only
//  requests a link (always returns pending) and reads guardian-only status via the verified callable.

import SwiftUI

struct GuardianLinkFlow: View {
    let churchId: String

    @State private var childId: String = ""
    @State private var evidenceKind: String = "pickup_code"
    @State private var reference: String = ""
    @State private var statusMessage: String?
    @State private var childStatus: ChildStatus?
    @State private var isWorking = false

    private let evidenceKinds: [(value: String, label: String)] = [
        ("pickup_code", "Pickup code"),
        ("staff_attested", "Staff-attested"),
        ("invite_acceptance", "Invite acceptance")
    ]

    var body: some View {
        if AMENFeatureFlags.shared.connectGuardianLinkEnabled {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GlassEyebrow(text: "Verify Guardian")

                VStack(alignment: .leading, spacing: 14) {
                    field("Child ID", text: $childId)

                    Picker("Evidence", selection: $evidenceKind) {
                        ForEach(evidenceKinds, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    .pickerStyle(.segmented)

                    field("Reference (optional)", text: $reference)

                    Button(isWorking ? "Submitting…" : "Request guardian link") {
                        Task { await submit() }
                    }
                    .buttonStyle(GlassKitSolidPillStyle())
                    .disabled(isWorking || childId.isEmpty)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(GlassKitTokens.inkSecondary)
                    }
                }
                .padding(18)
                .glassCardSurface()

                Button("Check child status") { Task { await loadStatus() } }
                    .buttonStyle(GlassKitSolidPillStyle())
                    .disabled(isWorking || childId.isEmpty)

                if let childStatus {
                    GlassFactCard(
                        title: "Child Check-In",
                        summary: childStatus.checkedIn ? "Checked in." : "Not checked in.",
                        facts: statusFacts(childStatus),
                        sources: ["getChildCheckInStatus"]
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GlassKitTokens.page.ignoresSafeArea())
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GlassKitTokens.page))
    }

    private func statusFacts(_ s: ChildStatus) -> [GlassFact] {
        var facts: [GlassFact] = [GlassFact(label: "Checked in", value: s.checkedIn ? "Yes" : "No",
                                            status: s.checkedIn ? .ok : nil)]
        if let ageGroup = s.ageGroup { facts.append(GlassFact(label: "Age group", value: ageGroup)) }
        if let building = s.building { facts.append(GlassFact(label: "Building", value: building)) }
        if let pickupCode = s.pickupCode { facts.append(GlassFact(label: "Pickup code", value: pickupCode)) }
        if let allergies = s.allergies, !allergies.isEmpty {
            facts.append(GlassFact(label: "Allergies", value: allergies.joined(separator: ", "), status: .warn))
        }
        return facts
    }

    private func submit() async {
        isWorking = true; defer { isWorking = false }
        statusMessage = nil
        let evidence = GuardianEvidence(kind: evidenceKind, reference: reference.isEmpty ? nil : reference)
        do {
            let res = try await ConnectGuardianService.shared.requestGuardianLink(
                churchId: churchId, childId: childId, evidence: evidence)
            statusMessage = "Link \(res.linkId) — status: \(res.status). Verification is handled by your church."
        } catch {
            statusMessage = "Could not request link: \(error.localizedDescription)"
        }
    }

    private func loadStatus() async {
        isWorking = true; defer { isWorking = false }
        childStatus = nil
        do {
            childStatus = try await ConnectGuardianService.shared.childCheckInStatus(childId: childId)
        } catch {
            statusMessage = "Status unavailable (guardian verification required): \(error.localizedDescription)"
        }
    }
}

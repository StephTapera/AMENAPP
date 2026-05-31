// ProvenanceDetailSheet.swift
// AMEN Trust Layer — T1 Provenance
// Full sheet presenting the complete MediaCredential audit trail:
// capture attestation, edit chain, and AI contributions.

import SwiftUI

// MARK: - Detail Sheet

struct ProvenanceDetailSheet: View {

    let credential: C2PAMediaCredential
    @Environment(\.dismiss) private var dismiss

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static let absoluteDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // MARK: Capture Attestation
                    cardSection(title: "Capture Attestation", symbol: "camera.fill") {
                        if let attestation = credential.captureAttestation {
                            labeledRow("Device", value: String(attestation.deviceId.prefix(8)) + "…")
                            labeledRow("Timestamp", value: Self.absoluteDateFormatter.string(from: attestation.timestamp))
                            labeledRow("Build", value: attestation.bundleVersion)
                            labeledRow("Signature", value: String(attestation.signatureBase64.prefix(12)) + "…")
                        } else {
                            emptyState("No capture attestation recorded.")
                        }
                    }

                    // MARK: Signer Info
                    cardSection(title: "Signer", symbol: "signature") {
                        labeledRow("Type", value: credential.signerType.rawValue)
                        labeledRow("State", value: credential.originState.rawValue)
                        labeledRow("C2PA Manifest", value: credential.c2paManifestPresent ? "Present" : "Absent")
                        labeledRow("Source Verified", value: credential.sourceVerified ? "Yes" : "No")
                        labeledRow("Metadata Intact", value: credential.metadataIntact ? "Yes" : "No")
                    }

                    // MARK: Edit Chain
                    cardSection(title: "Edit History", symbol: "pencil.circle") {
                        if credential.editChain.isEmpty {
                            emptyState("No edits recorded.")
                        } else {
                            ForEach(Array(credential.editChain.enumerated()), id: \.offset) { idx, edit in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(edit.editType.capitalized)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        Text(Self.relativeDateFormatter.localizedString(for: edit.timestamp, relativeTo: Date()))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(edit.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)

                                if idx < credential.editChain.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }

                    // MARK: AI Contributions
                    cardSection(title: "AI Contributions", symbol: "sparkles") {
                        if credential.aiContributions.isEmpty {
                            emptyState("No AI contributions recorded.")
                        } else {
                            ForEach(Array(credential.aiContributions.enumerated()), id: \.offset) { idx, contribution in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(contribution.type.rawValue.capitalized)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            Text(contribution.model)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(Self.relativeDateFormatter.localizedString(for: contribution.timestamp, relativeTo: Date()))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if contribution.humanEdited {
                                                Label("Human Reviewed", systemImage: "person.badge.checkmark")
                                                    .font(.caption2)
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 6)

                                if idx < credential.aiContributions.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .navigationTitle("Content Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Private Builders

    @ViewBuilder
    private func cardSection<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(14)
            .amenGlassCard(cornerRadius: 12)
        }
    }

    @ViewBuilder
    private func labeledRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let edit = EditRecord(
        editType: "crop",
        timestamp: Date().addingTimeInterval(-3600),
        editorId: "user-abc",
        description: "Cropped to 4:5 ratio for feed display."
    )
    let contribution = C2PAAIContribution(
        type: .altText,
        model: "a11y-vision-v2",
        jobId: "job-xyz-001",
        timestamp: Date().addingTimeInterval(-1800),
        humanEdited: true
    )
    let credential = C2PAMediaCredential(
        mediaId: "preview-detail-001",
        originState: .aiAssisted,
        c2paManifestPresent: true,
        signerType: .amenAppSigned,
        captureAttestation: CaptureAttestation(
            deviceId: "device-abc123",
            timestamp: Date().addingTimeInterval(-7200),
            bundleVersion: "2.4.1",
            signatureBase64: "dGVzdFNpZ25hdHVyZUJhc2U2NA=="
        ),
        editChain: [edit],
        aiContributions: [contribution],
        sourceVerified: true,
        metadataIntact: true
    )
    ProvenanceDetailSheet(credential: credential)
}
#endif

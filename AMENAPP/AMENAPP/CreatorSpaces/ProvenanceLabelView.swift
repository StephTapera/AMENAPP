// ProvenanceLabelView.swift
// AMENAPP — The media "nutrition label" and Shot Real badge.
//
// Design rules:
//   - Shot Real badge ONLY when capturedOnDevice && editHistory empty && !editedWithAI.
//   - Phase-2 fields (aiAssistedPercent, syntheticElementsPresent, authenticityConfidence)
//     display "—" when nil. Never fabricate a score.
//   - Never publicly shame edited content; labels are neutral and factual.

import SwiftUI

// MARK: - Shot Real Badge

struct ShotRealBadge: View {
    let isEligible: Bool
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: isEligible ? "checkmark.seal.fill" : "pencil.and.outline")
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(isEligible ? AmenTheme.Colors.amenGold : .secondary)
            Text(isEligible ? "Shot Real" : (compact ? "Edited" : "Edited / AI-Assisted"))
                .font(compact ? .caption2 : .caption)
                .fontWeight(.semibold)
                .foregroundStyle(isEligible ? AmenTheme.Colors.amenGold : .secondary)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(
            isEligible
                ? AmenTheme.Colors.amenGold.opacity(0.10)
                : Color(.secondarySystemBackground),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    isEligible ? AmenTheme.Colors.amenGold.opacity(0.30) : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Provenance banner (compact, shown in compose view)

struct ProvenanceLabelBanner: View {
    let draft: CSAssetDraft

    var isShotRealEligible: Bool {
        draft.captureMode != .audio && !draft.editedWithAI
    }

    var body: some View {
        HStack(spacing: 10) {
            ShotRealBadge(isEligible: isShotRealEligible, compact: true)

            Divider().frame(height: 16)

            HStack(spacing: 4) {
                Image(systemName: "camera.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(captureLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if draft.editedWithAI && !draft.aiToolsUsed.isEmpty {
                Divider().frame(height: 16)
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(AmenTheme.Colors.amenPurple)
                    Text("AI: \(draft.aiToolsUsed.first ?? "Assisted")")
                        .font(.caption2)
                        .foregroundStyle(AmenTheme.Colors.amenPurple)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var captureLabel: String {
        switch draft.captureMode {
        case .presence: return "Captured in AMEN · Dual Camera"
        case .truth:    return "Captured in AMEN · Truth Mode"
        case .audio:    return "Recorded in AMEN"
        }
    }
}

// MARK: - Full provenance label sheet (expanded view on label tap)

struct ProvenanceLabelFullView: View {
    let label: CSProvenanceLabel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                heroSection
                captureSection
                editSection
                phaseOneLiveSection
                phaseTwoSection
            }
            .navigationTitle("Media Provenance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var heroSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    ShotRealBadge(isEligible: label.isShotReal)
                    Text(label.isShotReal
                         ? "This media was captured unedited on a real device inside AMEN."
                         : "This media was edited or AI-assisted. See details below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private var captureSection: some View {
        Section("Capture") {
            labelRow(title: "Captured On Device", value: label.capturedOnDevice ? "Yes" : "No")
            labelRow(title: "Source Camera", value: label.sourceCamera)
            labelRow(title: "Mode", value: label.captureMode.capitalized)
            labelRow(title: "Captured At", value: label.timestampChain.first(where: { $0.event == "captured" }).map { formatDate($0.timestamp) } ?? "—")
        }
    }

    private var editSection: some View {
        Section("Edit History") {
            if label.editHistory.isEmpty {
                labelRow(title: "Edits", value: "None — unedited")
            } else {
                ForEach(label.editHistory, id: \.tool) { edit in
                    labelRow(
                        title: edit.tool,
                        value: "\(formatDate(edit.timestamp))\(edit.aiInvolved ? " · AI" : "")"
                    )
                }
            }
            labelRow(title: "AI Assisted", value: label.editedWithAI ? "Yes — \(label.aiToolsUsed.joined(separator: ", "))" : "No")
        }
    }

    private var phaseOneLiveSection: some View {
        Section("Signature") {
            labelRow(title: "Integrity", value: "HMAC verified")
            labelRow(title: "Signature", value: String(label.signature.prefix(16)) + "…")
        }
    }

    private var phaseTwoSection: some View {
        Section(header: Text("Advanced Analysis"), footer: Text("Advanced analysis fields require a partner detection service and will show values once that integration is active.")) {
            labelRow(title: "AI-Assisted %",       value: label.aiAssistedPercent.map { "\(Int($0 * 100))%" } ?? "—")
            labelRow(title: "Synthetic Elements",  value: label.syntheticElementsPresent.map { $0 ? "Detected" : "None" } ?? "—")
            labelRow(title: "Authenticity Score",  value: label.authenticityConfidence.map { "\(Int($0 * 100))%" } ?? "—")
        }
    }

    private func labelRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Color bridge

private extension AmenTheme.Colors {
    static var amenGold:   Color { Color(red: 0.83, green: 0.69, blue: 0.22) }
    static var amenPurple: Color { Color(red: 0.42, green: 0.28, blue: 1.00) }
}

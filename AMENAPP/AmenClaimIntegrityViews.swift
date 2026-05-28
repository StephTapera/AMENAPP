import SwiftUI

struct ClaimContextCard: View {
    let contentId: String
    let claimText: String
    var onSubmitted: (() -> Void)? = nil

    @State private var claimType: ClaimType = .factualClaim
    @State private var sourceURL = ""
    @State private var scriptureRef = ""
    @State private var contextSummary = ""
    @State private var status: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add claim context", systemImage: "link.badge.plus")
                .font(.subheadline.bold())
            Text(claimText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Picker("Claim type", selection: $claimType) {
                ForEach(ClaimType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }

            TextField("Source URL", text: $sourceURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            TextField("Scripture reference", text: $scriptureRef)
                .textInputAutocapitalization(.words)
            TextField("Context or clarification", text: $contextSummary, axis: .vertical)
                .lineLimit(2...4)

            Button {
                submit()
            } label: {
                Label(isSubmitting ? "Submitting" : "Submit Context", systemImage: "checkmark.circle")
            }
            .disabled(isSubmitting)

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func submit() {
        isSubmitting = true
        status = nil

        let sourceUrls = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : [sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)]
        let scriptureRefs = scriptureRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : [scriptureRef.trimmingCharacters(in: .whitespacesAndNewlines)]
        let trimmedContext = contextSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try await AmenSocialSafetyService.shared.submitClaimContext(
                    ClaimContext(
                        contentId: contentId,
                        claimText: claimText,
                        claimType: claimType,
                        sourceUrls: sourceUrls,
                        scriptureRefs: scriptureRefs,
                        contextSummary: trimmedContext.isEmpty ? nil : trimmedContext
                    )
                )
                status = "Context submitted for review."
                onSubmitted?()
            } catch {
                status = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

struct IntegrityLabelView: View {
    let label: ContentIntegrityLabel

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.labelType.userFacingLabel)
                    .font(.caption.weight(.semibold))
                if let explanation = label.explanation {
                    Text(explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: label.labelType.icon)
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(Text("\(label.labelType.userFacingLabel). \(label.explanation ?? "")"))
    }
}

private extension ClaimType {
    var displayName: String {
        switch self {
        case .personalOpinion: return "Personal opinion"
        case .interpretation: return "Interpretation"
        case .factualClaim: return "Factual claim"
        case .medicalClaim: return "Medical claim"
        case .politicalClaim: return "Political claim"
        case .financialClaim: return "Financial claim"
        case .theologicalClaim: return "Theological claim"
        case .prophecy: return "Prophecy"
        case .newsEvent: return "News event"
        case .crisisAlert: return "Crisis alert"
        case .allegation: return "Allegation"
        }
    }
}

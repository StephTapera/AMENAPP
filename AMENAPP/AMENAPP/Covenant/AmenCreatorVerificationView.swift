import SwiftUI

// MARK: - Creator Verification View
// Placeholder flow for identity, church, and ministry verification.
// Verification is never automatic — always requires human review.

struct AmenCreatorVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: CreatorVerificationRequest.VerificationType? = nil
    @State private var submitting = false
    @State private var submitted = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            if submitted {
                successView
            } else {
                formView
            }
        }
    }

    // MARK: - Form

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection

                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose Verification Type")
                        .font(.headline)

                    ForEach(CreatorVerificationRequest.VerificationType.allCases, id: \.self) { type in
                        VerificationTypeCard(
                            type: type,
                            isSelected: selectedType == type
                        ) {
                            selectedType = type
                        }
                    }
                }

                if let type = selectedType {
                    requirementsSection(for: type)

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if submitting { ProgressView().scaleEffect(0.8) }
                            Text(submitting ? "Submitting…" : "Submit for Review")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.purple))
                    }
                    .buttonStyle(.plain)
                    .disabled(submitting)

                    Text("Verification is reviewed by the AMEN team. We do not auto-approve from AI analysis. You will be notified when your request is processed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 32)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Get Verified")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Creator Verification", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
            Text("Verification badges help your community trust you. Each type requires documentation reviewed by a human on the AMEN team.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Requirements

    private func requirementsSection(for type: CreatorVerificationRequest.VerificationType) -> some View {
        let requirements: [String]
        switch type {
        case .identity:
            requirements = [
                "Government-issued photo ID",
                "Must match your AMEN display name or legal name",
                "Processed within 3-5 business days"
            ]
        case .church:
            requirements = [
                "Official church letterhead or registration documents",
                "Contact information for a church leader",
                "Website or public directory listing",
                "Processed within 5-7 business days"
            ]
        case .ministry:
            requirements = [
                "Ministry registration or nonprofit documentation",
                "501(c)(3) or equivalent if applicable",
                "Website and social media presence",
                "Processed within 5-7 business days"
            ]
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text("What You'll Need")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(requirements, id: \.self) { req in
                    Label(req, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
            Text("Request Submitted")
                .font(.title3.weight(.semibold))
            Text("Our team will review your application and notify you within the timeframe for your verification type.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Submit

    private func submit() async {
        guard let selectedType else { return }
        submitting = true
        error = nil
        do {
            try await CovenantService.shared.submitVerificationRequest(type: selectedType)
            submitted = true
        } catch {
            self.error = error.localizedDescription
        }
        submitting = false
    }
}

// MARK: - Verification Type Card

private struct VerificationTypeCard: View {
    let type: CreatorVerificationRequest.VerificationType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: typeIcon)
                    .font(.system(size: 20))
                    .foregroundStyle(typeColor)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(typeColor.opacity(0.1)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(type.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(typeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? typeColor : Color.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? typeColor : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var typeIcon: String {
        switch type {
        case .identity: return "person.crop.circle.badge.checkmark"
        case .church:   return "building.columns.fill"
        case .ministry: return "cross.fill"
        }
    }

    private var typeColor: Color {
        switch type {
        case .identity: return .blue
        case .church:   return .purple
        case .ministry: return .indigo
        }
    }

    private var typeDescription: String {
        switch type {
        case .identity: return "Confirm you are who you say you are."
        case .church:   return "Verify your affiliation with a church."
        case .ministry: return "Verify your registered ministry or nonprofit."
        }
    }
}

// MARK: - CaseIterable on VerificationType

extension CreatorVerificationRequest.VerificationType: CaseIterable {
    public static var allCases: [CreatorVerificationRequest.VerificationType] {
        [.identity, .church, .ministry]
    }
}

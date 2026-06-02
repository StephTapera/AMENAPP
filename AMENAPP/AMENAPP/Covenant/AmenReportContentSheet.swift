import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Report Content Sheet
// Privacy-respecting report flow. No dark patterns, no dark UX.
// User selects reason, adds optional note, submits. Server assigns status.

struct AmenReportContentSheet: View {
    let contentType: String
    let contentId: String
    let covenantId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: CovenantReport.ReportReason? = nil
    @State private var additionalNote: String = ""
    @State private var submitting = false
    @State private var submitted = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            if submitted {
                thankYouState
            } else {
                reportForm
            }
        }
    }

    // MARK: - Form

    private var reportForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection

                VStack(alignment: .leading, spacing: 10) {
                    Text("What's the issue?")
                        .font(.headline)
                    ForEach(CovenantReport.ReportReason.allCases, id: \.self) { reason in
                        CovenantReportReasonRow(
                            reason: reason,
                            isSelected: selectedReason == reason
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedReason = reason
                            }
                        }
                    }
                }

                if selectedReason != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Additional context (optional)")
                            .font(.subheadline.weight(.medium))
                        TextEditor(text: $additionalNote)
                            .frame(minHeight: 80, maxHeight: 120)
                            .font(.subheadline)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if submitting {
                                ProgressView().scaleEffect(0.8)
                            }
                            Text(submitting ? "Submitting…" : "Submit Report")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.red))
                    }
                    .disabled(submitting || selectedReason == nil)

                    Text("Your report is confidential. AMEN does not share your identity with the reported user.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 32)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Report Content")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Help keep AMEN safe", systemImage: "shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Reports are reviewed by our trust & safety team. We never take content down based on disagreement alone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Thank You State

    private var thankYouState: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Report Submitted")
                .font(.title3.weight(.semibold))
            Text("Thank you. Our team will review this report. We'll notify you when we've taken action if appropriate.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Submit

    private func submit() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let reason = selectedReason else { return }
        submitting = true
        error = nil
        let data: [String: Any] = [
            "reporterId": uid,
            "covenantId": covenantId as Any,
            "contentType": contentType,
            "contentId": contentId,
            "reason": reason.rawValue,
            "additionalNote": additionalNote.isEmpty ? NSNull() : additionalNote,
            "status": "submitted",
            "createdAt": Timestamp(date: Date())
        ]
        do {
            try await Firestore.firestore().collection("reports").addDocument(data: data)
            submitted = true
        } catch {
            self.error = "Submission failed. Please try again."
        }
        submitting = false
    }
}

// MARK: - Report Reason Row

private struct CovenantReportReasonRow: View {
    let reason: CovenantReport.ReportReason
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.red : Color.secondary)

                Text(reason.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.red.opacity(0.06) : Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

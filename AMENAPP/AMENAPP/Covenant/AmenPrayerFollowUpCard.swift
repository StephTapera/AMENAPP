import SwiftUI
import FirebaseFirestore

// MARK: - Prayer Follow-Up Card
// Compact card for prayer requests needing follow-up.
// Supports "I prayed", status update, and update post actions.

struct AmenPrayerFollowUpCard: View {
    let request: CovenantPrayerRequest
    @State private var hasPrayed = false
    @State private var showUpdateSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            bodyText
            tagsRow
            actionRow
        }
        .padding(16)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(statusColor.opacity(0.25), lineWidth: 1)
                )
        )
        .sheet(isPresented: $showUpdateSheet) {
            PrayerUpdateSheet(request: request)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "hands.sparkles.fill")
                .font(.system(size: 14))
                .foregroundStyle(.purple)
            Text("Prayer Request")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            statusChip
        }
    }

    private var statusChip: some View {
        Text(request.status.displayLabel)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(statusColor.opacity(0.12)))
    }

    private var statusColor: Color {
        switch request.status {
        case .open:     return .blue
        case .updated:  return .orange
        case .answered: return .green
        case .closed:   return .secondary
        }
    }

    // MARK: - Body

    private var bodyText: some View {
        Text(request.body)
            .font(.subheadline)
            .lineLimit(3)
    }

    // MARK: - Tags Row

    private var tagsRow: some View {
        HStack(spacing: 8) {
            Label("\(request.prayedCount)", systemImage: "hands.sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let lastUpdate = request.lastUpdateAt {
                Label("Updated \(lastUpdate.dateValue(), style: .relative)", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                hasPrayed = true
                HapticManager.impact(style: .medium)
                Task {
                    await CovenantService.shared.markIPrayed(
                        prayerRequestId: request.id ?? "",
                        covenantId: request.covenantId
                    )
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: hasPrayed ? "hands.sparkles.fill" : "hands.sparkles")
                        .font(.system(size: 13))
                    Text(hasPrayed ? "Prayed" : "I Prayed")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(hasPrayed ? .white : .purple)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(hasPrayed ? Color.purple : Color.purple.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .disabled(hasPrayed)

            if request.followUpRequested {
                Button {
                    showUpdateSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 13))
                        Text("Post Update")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Prayer Update Sheet

private struct PrayerUpdateSheet: View {
    let request: CovenantPrayerRequest
    @Environment(\.dismiss) private var dismiss
    @State private var updateText = ""
    @State private var selectedStatus: CovenantPrayerRequest.PrayerStatus = .updated
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Share what God has been doing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $updateText)
                    .frame(minHeight: 100)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Update Status")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 10) {
                        ForEach([CovenantPrayerRequest.PrayerStatus.updated, .answered, .closed], id: \.self) { status in
                            statusPill(status)
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Prayer Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Post") {
                        Task {
                            submitting = true
                            try? await CovenantService.shared.updatePrayerStatus(
                                prayerRequestId: request.id ?? "",
                                covenantId: request.covenantId,
                                status: selectedStatus
                            )
                            dismiss()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(updateText.isEmpty || submitting)
                }
            }
        }
    }

    private func statusPill(_ status: CovenantPrayerRequest.PrayerStatus) -> some View {
        let selected = selectedStatus == status
        return Button { selectedStatus = status } label: {
            Text(status.displayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.purple : Color.secondary.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

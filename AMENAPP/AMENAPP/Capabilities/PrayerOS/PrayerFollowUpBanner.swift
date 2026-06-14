// PrayerFollowUpBanner.swift
// AMEN Capabilities v1 — Follow-up reminder banner (Wave 1: Lane D)
//
// Compact banner surfaced from deep-link routing when a prayer follow-up is due.
// Deep link: amen://capabilities/prayer-os/card/{cardId}
// Contract:  Docs/Capabilities/CONTRACTS.md §3.3, §9
// Models:    AMENAPP/AMENAPP/Capabilities/CapabilityModels.swift (FROZEN)

import SwiftUI

// subscript(safe:) — canonical definition in SafeSubscriptExtension.swift

// MARK: - PrayerFollowUpBanner

struct PrayerFollowUpBanner: View {

    // MARK: Input

    let card: PrayerCard
    let followUpIndex: Int

    // MARK: Dependencies

    @StateObject private var service = PrayerOSService.shared

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: State

    @State private var isCompleting: Bool = false
    @State private var completionError: Error? = nil
    @State private var showErrorAlert: Bool = false
    @State private var isDismissed: Bool = false

    // MARK: - Body

    var body: some View {
        if isDismissed { EmptyView() } else { bannerContent }
    }

    // MARK: Banner content

    private var bannerContent: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.and.waveform")
                .font(.title3)
                .foregroundStyle(.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Check in: \(card.subject.displayName)")
                    .font(.headline)
                    .lineLimit(1)

                if let followUp = card.followUps[safe: followUpIndex],
                   let note = followUp.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let followUp = card.followUps[safe: followUpIndex] {
                    Text(followUp.dueAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            doneButton
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Mark done") {
            Task { await markDone() }
        }
        .alert("Could Not Complete Follow-up", isPresented: $showErrorAlert, presenting: completionError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    // MARK: Done button

    @ViewBuilder
    private var doneButton: some View {
        if isCompleting {
            ProgressView()
                .scaleEffect(0.85)
                .accessibilityLabel("Completing follow-up")
        } else {
            Button("Done") {
                Task { await markDone() }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isCompleting)
            .accessibilityLabel("Mark follow-up done for \(card.subject.displayName)")
            .accessibilityHint("Double-tap to mark this follow-up as completed")
        }
    }

    // MARK: - Actions

    private func markDone() async {
        isCompleting = true
        defer { isCompleting = false }

        do {
            try await service.completeFollowUp(
                cardId: card.id,
                followUpIndex: followUpIndex,
                note: nil
            )
            // Dismiss banner after successful completion.
            // Respects reduceMotion: no spring/bounce, just a short ease when motion is reduced.
            withAnimation(
                reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : .easeOut(duration: 0.25)
            ) {
                isDismissed = true
            }
        } catch {
            completionError = error
            showErrorAlert = true
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts = ["Follow-up reminder for \(card.subject.displayName)"]
        if let followUp = card.followUps[safe: followUpIndex],
           let note = followUp.note, !note.isEmpty {
            parts.append(note)
        }
        parts.append("Double-tap Done to mark complete")
        return parts.joined(separator: ". ")
    }
}

// MARK: - Preview

#Preview {
    let card = PrayerCard(
        id: "preview-001",
        subject: PrayerSubject(type: .person, displayName: "John Smith", linkedContactRef: nil),
        category: .health,
        detail: "Praying for full recovery after surgery.",
        status: .active,
        createdAt: Date(),
        updatedAt: Date(),
        reminders: [],
        followUps: [
            PrayerFollowUp(
                dueAt: Date().addingTimeInterval(3600),
                status: .pending,
                note: "Check how he is feeling post-op"
            )
        ]
    )
    PrayerFollowUpBanner(card: card, followUpIndex: 0)
        .padding()
}

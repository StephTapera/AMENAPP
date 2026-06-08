// ONEReportMomentView.swift
// ONE P5-C — Report flow: category picker + evidence lock + timeline receipt.
//
// Evidence invariant: one_reportMoment locks evidence BEFORE any decay runs.
// The decay CF checks evidenceLocked=true and skips the moment.

import SwiftUI

struct ONEReportMomentView: View {
    let momentID: String
    let authorDisplayName: String
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: ONEReportCategory? = nil
    @State private var phase: ReportPhase = .picking
    @State private var receipt: ONEEvidenceReceipt? = nil
    @State private var isLocking = false
    @State private var errorMessage: String? = nil

    private enum ReportPhase { case picking, locked }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .picking: pickingView
                case .locked:  if let r = receipt { lockedView(r) }
                }
            }
            .navigationTitle("Report Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss(); dismiss() }
                        .accessibilityLabel("Cancel report")
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Picking view

    private var pickingView: some View {
        List {
            headerSection
            categorySection
            lockSection
        }
        .listStyle(.insetGrouped)
    }

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: ONE.Spacing.sm) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(ONE.Colors.witnessGold)
                    .font(.systemScaled(14))
                Text("Evidence is locked server-side before any decay can run. The author's decay settings do not apply to reported content.")
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var categorySection: some View {
        Section("Select category") {
            ForEach(ONEReportCategory.allCases, id: \.self) { cat in
                categoryRow(cat)
            }
        }
    }

    private func categoryRow(_ cat: ONEReportCategory) -> some View {
        HStack(spacing: ONE.Spacing.md) {
            Image(systemName: cat.icon)
                .font(.systemScaled(16))
                .foregroundStyle(ONE.Colors.ephemeralRed.opacity(0.8))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(cat.displayLabel)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.primary)
                Text(cat.displayDescription)
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selectedCategory == cat {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ONE.Colors.ephemeralRed)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedCategory = cat }
        .accessibilityLabel("\(cat.displayLabel): \(cat.displayDescription)\(selectedCategory == cat ? ", selected" : "")")
        .accessibilityAddTraits(selectedCategory == cat ? [.isSelected] : [])
    }

    private var lockSection: some View {
        Section {
            if isLocking {
                HStack {
                    ProgressView()
                    Text("Locking evidence…")
                        .font(.systemScaled(14))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await submitReport() }
                } label: {
                    HStack {
                        Spacer()
                        Text("Lock evidence & report")
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, ONE.Spacing.xs)
                }
                .disabled(selectedCategory == nil)
                .listRowBackground(selectedCategory != nil
                    ? ONE.Colors.ephemeralRed
                    : ONE.Colors.ephemeralRed.opacity(0.35))
                .accessibilityLabel("Lock evidence and report")
                .accessibilityHint(selectedCategory == nil ? "Select a category first" : "")
            }
        } footer: {
            Text("A human moderator will review within 24 hours.")
                .font(.caption)
        }
    }

    // MARK: - Locked / timeline view

    private func lockedView(_ r: ONEEvidenceReceipt) -> some View {
        List {
            Section {
                HStack(spacing: ONE.Spacing.sm) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(ONE.Colors.repairGreen)
                        .font(.systemScaled(16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Evidence locked")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(ONE.Colors.repairGreen)
                        Text("Retained for 90 days · \(r.evidenceID)")
                            .font(.systemScaled(11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Evidence locked. Retained 90 days. ID: \(r.evidenceID)")
            }

            Section("Timeline") {
                timelineStep(
                    icon: "lock.fill",
                    color: ONE.Colors.repairGreen,
                    label: "Evidence locked",
                    detail: "Copied to immutable store. Decay paused for this item.",
                    time: r.lockedAt,
                    done: true
                )
                timelineStep(
                    icon: "flag.fill",
                    color: ONE.Colors.repairGreen,
                    label: "Report received",
                    detail: "Category: \(r.category.displayLabel). Sent to moderation queue.",
                    time: r.lockedAt.addingTimeInterval(2),
                    done: true
                )
                timelineStep(
                    icon: "person.fill.checkmark",
                    color: ONE.Colors.witnessGold,
                    label: "Moderator review",
                    detail: "Human review within 24h. You'll be notified.",
                    time: nil,
                    done: false
                )
                timelineStep(
                    icon: "checkmark.circle.fill",
                    color: .secondary,
                    label: "Outcome",
                    detail: "Content removed / no action / escalated if required. Evidence retained 90 days.",
                    time: nil,
                    done: false
                )
            }

            Section {
                Button("Close") { onDismiss(); dismiss() }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Close report")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func timelineStep(
        icon: String,
        color: Color,
        label: String,
        detail: String,
        time: Date?,
        done: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: ONE.Spacing.md) {
            Image(systemName: icon)
                .font(.systemScaled(14))
                .foregroundStyle(done ? color : .secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(done ? .primary : .secondary)
                Text(detail)
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
                if let t = time {
                    Text(t.formatted(date: .omitted, time: .shortened))
                        .font(.systemScaled(11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(detail)\(time != nil ? ", completed" : ", pending")")
    }

    // MARK: - Submit

    private func submitReport() async {
        guard let cat = selectedCategory else { return }
        isLocking = true
        do {
            let r = try await ONEImmuneSignalService.shared.reportMoment(momentID: momentID, category: cat)
            receipt = r
            withAnimation { phase = .locked }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLocking = false
    }
}

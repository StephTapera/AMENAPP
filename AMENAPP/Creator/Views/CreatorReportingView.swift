// CreatorReportingView.swift
// AMENAPP - Creator Spotlight / Wave 3
//
// Report / block / mute bottom sheet for a creator.
// Glass sheet background; opaque action rows.

import SwiftUI

struct CreatorReportingView: View {

    let creatorId: String

    @Environment(\.dismiss) private var dismiss
    @State private var showingReportSubSheet: Bool = false
    @State private var blockConfirmation: Bool = false
    @State private var muteConfirmation: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Glass sheet background
                Color.clear
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()

                List {
                    actionSection
                    safetySection
                    footerSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showingReportSubSheet) {
            ReportCategorySheet(creatorId: creatorId)
        }
        .alert("Block this creator?", isPresented: $blockConfirmation) {
            Button("Block", role: .destructive) {
                handleBlock()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to see your profile or contact you. You can undo this in Settings.")
        }
        .alert("Mute this creator?", isPresented: $muteConfirmation) {
            Button("Mute", role: .destructive) {
                handleMute()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their content will be hidden from your feed. They won't know you muted them.")
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        Section {
            CreatorReportActionRow(
                icon: "flag",
                label: "Report Content",
                color: .orange
            ) {
                showingReportSubSheet = true
            }

            CreatorReportActionRow(
                icon: "exclamationmark.bubble",
                label: "Report Creator",
                color: .orange
            ) {
                showingReportSubSheet = true
            }

            CreatorReportActionRow(
                icon: "nosign",
                label: "Block",
                color: .red
            ) {
                blockConfirmation = true
            }

            CreatorReportActionRow(
                icon: "speaker.slash",
                label: "Mute",
                color: .secondary
            ) {
                muteConfirmation = true
            }
        }
    }

    // MARK: - Safety Section

    private var safetySection: some View {
        Section {
            CreatorReportActionRow(
                icon: "hand.raised",
                label: "Hide Recommendations",
                color: .secondary
            ) {
                handleHideRecommendations()
            }

            CreatorReportActionRow(
                icon: "pencil.and.list.clipboard",
                label: "Correct Creator Information",
                color: .blue
            ) {
                handleCorrectInfo()
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        Section {
            HStack {
                Spacer()
                Text("Your report helps keep the community safe")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    private func handleBlock() {
        // TODO: call blockUser Cloud Function with creatorId
        dismiss()
    }

    private func handleMute() {
        // TODO: call muteUser Cloud Function with creatorId
        dismiss()
    }

    private func handleHideRecommendations() {
        // TODO: write recommendation suppression to user preferences
        dismiss()
    }

    private func handleCorrectInfo() {
        // TODO: open Creator Information Correction flow
        dismiss()
    }
}

// MARK: - Action Row

private struct CreatorReportActionRow: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(.systemBackground))
    }
}

// MARK: - Report Category Sheet

private struct ReportCategorySheet: View {
    let creatorId: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: ReportCategory?
    @State private var submitted: Bool = false

    var body: some View {
        NavigationStack {
            List(ReportCategory.allCases, id: \.self) { category in
                Button {
                    selectedCategory = category
                } label: {
                    HStack {
                        Text(category.displayLabel)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedCategory == category {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color(.systemBackground))
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Report Reason")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") {
                        handleSubmit()
                    }
                    .disabled(selectedCategory == nil)
                    .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .alert("Report Submitted", isPresented: $submitted) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your report has been received. Thank you for helping keep this community safe.")
        }
    }

    private func handleSubmit() {
        guard selectedCategory != nil else { return }
        // TODO: call submitReport Cloud Function with creatorId + category
        submitted = true
    }
}

// MARK: - Report Category

private enum ReportCategory: String, CaseIterable {
    case harassment        = "harassment"
    case impersonation     = "impersonation"
    case fraud             = "fraud"
    case dangerousAdvice   = "dangerous_advice"
    case privacyViolation  = "privacy_violation"
    case misinformation    = "misinformation"
    case spam              = "spam"
    case copyright         = "copyright"
    case spiritualAbuse    = "spiritual_abuse"
    case other             = "other"

    var displayLabel: String {
        switch self {
        case .harassment:       return "Harassment or bullying"
        case .impersonation:    return "Impersonation"
        case .fraud:            return "Fraud or scam"
        case .dangerousAdvice:  return "Dangerous advice"
        case .privacyViolation: return "Privacy violation"
        case .misinformation:   return "False information"
        case .spam:             return "Spam"
        case .copyright:        return "Copyright infringement"
        case .spiritualAbuse:   return "Spiritual abuse"
        case .other:            return "Other"
        }
    }
}

// RedTeamView.swift
// AMENAPP
//
// Wave 6 — the red-team reporting surface: submit a moderation/scam/jailbreak/
// AI-failure report into the real registry, and see your own submissions and their
// status. The registry is empty until real reports arrive (no fake entries).
//
// Gated by AMENFeatureFlags.shared.redTeamSurfaceEnabled (default OFF).

import SwiftUI

struct RedTeamView: View {
    @StateObject private var service = RedTeamService()
    @State private var showSubmit = false

    var body: some View {
        List {
            Section {
                Text("Found a way our moderation, scam protection, or AI fails? Report it. Valid reports earn recognition after a human confirms them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    showSubmit = true
                } label: {
                    Label("Submit a report", systemImage: "ant")
                }
                .tint(.blue)
            }

            Section("Your reports") {
                if service.myReports.isEmpty {
                    Text("You haven't submitted any reports yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.myReports) { report in
                        RedTeamRow(report: report)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Red Team")
        .task { await service.loadMine() }
        .sheet(isPresented: $showSubmit) {
            RedTeamSubmitSheet { category, desc, repro in
                await service.submit(category: category, description: desc, reproSteps: repro)
            }
        }
    }
}

private struct RedTeamRow: View {
    let report: RedTeamReport
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(report.category.displayName).font(.subheadline.weight(.semibold))
                Spacer()
                if report.recognitionAwarded {
                    Label("Recognized", systemImage: "rosette")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green) // state: human-confirmed valid
                } else {
                    Text(report.status.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(report.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

private struct RedTeamSubmitSheet: View {
    let submit: (RedTeamCategory, String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var category: RedTeamCategory = .moderation
    @State private var description = ""
    @State private var reproSteps = ""
    @State private var isSubmitting = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $category) {
                    Text("Moderation").tag(RedTeamCategory.moderation)
                    Text("Scam").tag(RedTeamCategory.scam)
                    Text("Jailbreak").tag(RedTeamCategory.jailbreak)
                    Text("AI failure").tag(RedTeamCategory.aiFailure)
                }
                Section("What happened") {
                    TextField("Describe the issue…", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("How to reproduce") {
                    TextField("Steps to reproduce…", text: $reproSteps, axis: .vertical)
                        .lineLimit(3...8)
                }
                if failed {
                    Text("Couldn't submit. Please try again.")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("New report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task {
                            isSubmitting = true; failed = false
                            let ok = await submit(category, description, reproSteps)
                            isSubmitting = false
                            if ok { dismiss() } else { failed = true }
                        }
                    }
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
        }
    }
}

// MARK: - Display helpers (additive on the frozen Wave 0 contract)

extension RedTeamCategory {
    var displayName: String {
        switch self {
        case .moderation: return "Moderation"
        case .scam:       return "Scam"
        case .jailbreak:  return "Jailbreak"
        case .aiFailure:  return "AI failure"
        }
    }
}

extension RedTeamStatus {
    var displayName: String {
        switch self {
        case .submitted: return "Submitted"
        case .triaging:  return "Triaging"
        case .confirmed: return "Confirmed"
        case .rejected:  return "Rejected"
        case .fixed:     return "Fixed"
        }
    }
}

#if DEBUG
#Preview("Red Team") {
    NavigationStack { RedTeamView() }
}
#endif

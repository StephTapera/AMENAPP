// ONEWitnessRequestView.swift
// ONE — Witness request sheet: replaces "follow" with season-scoped, mutual witness.
// P3-G | Calls one_requestWitness CF. Block/sever still instant and always available.

import SwiftUI

struct ONEWitnessRequestView: View {
    let targetUID: String
    var onComplete: (String?) -> Void  // passes requestID on success, nil on cancel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedKind: ONEWitnessSeason.Kind = .indefinite
    @State private var seasonLabel = ""
    @State private var customDays = 30
    @State private var mutualExposure: ONEPrivacyMirrorLevel = .translucent
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil

    private var canSubmit: Bool {
        switch selectedKind {
        case .indefinite:             return true
        case .liturgical, .academic, .event: return !seasonLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .custom:                 return customDays > 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                seasonSection
                exposureSection
                explanationSection
            }
            .navigationTitle("Witness Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete(nil); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Group {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Send") { Task { await submit() } }
                                .fontWeight(.semibold)
                                .disabled(!canSubmit)
                        }
                    }
                }
            }
            .alert("Something went wrong", isPresented: Binding(
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

    // MARK: - Season section

    private var seasonSection: some View {
        Section {
            Picker("Season", selection: $selectedKind) {
                ForEach(ONEWitnessSeason.Kind.allCases, id: \.self) { kind in
                    Text(kind.displayLabel).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Witness season type")

            if selectedKind != .indefinite && selectedKind != .custom {
                TextField(selectedKind.fieldPlaceholder, text: $seasonLabel)
                    .accessibilityLabel("Season name")
            }

            if selectedKind == .custom {
                Stepper(
                    "\(customDays) day\(customDays == 1 ? "" : "s")",
                    value: $customDays,
                    in: 7...365,
                    step: 7
                )
                .accessibilityLabel("Custom witness duration: \(customDays) days")
            }
        } header: {
            Text("Season")
        } footer: {
            Text(seasonFooter)
                .font(.caption)
        }
    }

    // MARK: - Mutual exposure section

    private var exposureSection: some View {
        Section {
            ForEach(ONEPrivacyMirrorLevel.witnessPickerCases, id: \.self) { level in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.displayLabel)
                            .font(.system(size: 14, weight: .medium))
                        Text(level.exposureDescription)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if mutualExposure == level {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ONE.Colors.witnessGold)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { mutualExposure = level }
                .accessibilityLabel("\(level.displayLabel): \(level.exposureDescription)\(mutualExposure == level ? ", selected" : "")")
                .accessibilityAddTraits(mutualExposure == level ? [.isSelected] : [])
            }
        } header: {
            Text("What they see about you")
        } footer: {
            Text("Your privacy mirror level for this witness relationship. You can change it later.")
                .font(.caption)
        }
    }

    // MARK: - Explanation section

    private var explanationSection: some View {
        Section {
            HStack(alignment: .top, spacing: ONE.Spacing.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                Text("Witnessing is a season, not a subscription. It ends naturally. You and this person can see each other more fully during this season — as much as your privacy mirrors allow.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Submit

    private func submit() async {
        isSubmitting = true
        do {
            let season = buildSeason()
            let requestID = try await ONECallableService.shared.requestWitness(
                targetUID: targetUID,
                seasonLabel: season.label
            )
            isSubmitting = false
            onComplete(requestID)
            dismiss()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
        }
    }

    private func buildSeason() -> ONEWitnessSeason {
        switch selectedKind {
        case .indefinite:  return .indefinite
        case .liturgical:  return .liturgical(seasonLabel.trimmingCharacters(in: .whitespacesAndNewlines))
        case .academic:    return .academic(seasonLabel.trimmingCharacters(in: .whitespacesAndNewlines))
        case .event:       return .event(seasonLabel.trimmingCharacters(in: .whitespacesAndNewlines))
        case .custom:      return .custom(days: customDays)
        }
    }

    private var seasonFooter: String {
        switch selectedKind {
        case .indefinite:  return "Witness relationship continues until either party ends it."
        case .liturgical:  return "e.g. Advent 2026, Lent 2027"
        case .academic:    return "e.g. Spring 2027, Fall 2026"
        case .event:       return "e.g. Retreat 2026, Conference 2027"
        case .custom:      return "Witness relationship ends after \(customDays) days."
        }
    }
}

// MARK: - ONEWitnessSeason.Kind helpers

extension ONEWitnessSeason.Kind: CaseIterable {
    public static var allCases: [ONEWitnessSeason.Kind] {
        [.indefinite, .liturgical, .academic, .event, .custom]
    }

    var displayLabel: String {
        switch self {
        case .indefinite:  return "Ongoing"
        case .liturgical:  return "Liturgical"
        case .academic:    return "Academic"
        case .event:       return "Event"
        case .custom:      return "Custom"
        }
    }

    var fieldPlaceholder: String {
        switch self {
        case .indefinite, .custom: return ""
        case .liturgical:          return "e.g. Advent 2026"
        case .academic:            return "e.g. Spring 2027"
        case .event:               return "e.g. Retreat 2026"
        }
    }
}

// MARK: - ONEPrivacyMirrorLevel helpers

extension ONEPrivacyMirrorLevel {
    static var witnessPickerCases: [ONEPrivacyMirrorLevel] {
        [.sealed, .opaque, .translucent, .open]
    }

    var exposureDescription: String {
        switch self {
        case .sealed:      return "Anonymous — they see nothing"
        case .opaque:      return "They know you exist; no details"
        case .translucent: return "They see your name and bio"
        case .open:        return "Full profile visible"
        }
    }
}

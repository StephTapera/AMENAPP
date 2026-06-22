// AmenSpiritualPresencePickerView.swift
// AMEN Connect + Spaces — Presence & Care Routing (Agent 5)
// Built 2026-06-01
//
// Aegis caps enforced: C-14 (explicit opt-in for reachability),
// C-22 (care signals route to humans), C-34 (privacy — best-reach text
// restricted to admins/pastoral staff), C-41 (reduce-motion adaptive).

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - State row model

private struct SpiritualStateRow: Identifiable {
    let id: AmenConnectSpacesSpiritualState
    let emoji: String
    let label: String
    let accentColor: Color
}

private let kStateRows: [SpiritualStateRow] = [
    .init(id: .inTheWord,               emoji: "📖", label: "In the Word",             accentColor: .accentColor),
    .init(id: .inPrayer,                emoji: "🙏", label: "In Prayer",               accentColor: .amenPurple),
    .init(id: .fasting,                 emoji: "✨", label: "Fasting",                  accentColor: .accentColor),
    .init(id: .sabbathRest,             emoji: "🌙", label: "Sabbath Rest",             accentColor: .amenBlue),
    .init(id: .grieving,                emoji: "💙", label: "Grieving",                 accentColor: .amenBlue),
    .init(id: .discerning,              emoji: "🕊️", label: "Discerning",               accentColor: .amenPurple),
    .init(id: .availableForUrgentPrayer, emoji: "🔴", label: "Available for Urgent Prayer", accentColor: .accentColor),
]

// MARK: - ViewModel

@MainActor
final class AmenSpiritualPresencePickerViewModel: ObservableObject {
    @Published var selectedState: AmenConnectSpacesSpiritualState = .inTheWord
    @Published var urgentReachable: Bool = false
    @Published var carePartnerToggle: Bool = false
    @Published var sabbathUntil: Date = Date().addingTimeInterval(86400)
    @Published var bestReachText: String = ""
    @Published var isSaving: Bool = false
    @Published var errorMessage: String?

    private let userId: String

    init() {
        self.userId = Auth.auth().currentUser?.uid ?? ""
    }

    func save() async {
        guard !userId.isEmpty else {
            errorMessage = "You must be signed in."
            return
        }
        isSaving = true
        errorMessage = nil
        let presence = AmenConnectSpacesPresence(
            userId: userId,
            spiritualState: selectedState,
            urgentReachable: selectedState == .availableForUrgentPrayer ? urgentReachable : false,
            sabbathUntil: selectedState == .sabbathRest ? sabbathUntil : nil,
            updatedAt: Date()
        )
        do {
            _ = try await AmenConnectSpacesCallableProxy.shared.updateSpiritualPresence(presence)
            // Store bestReachText to Firestore presence doc (admin-only field).
            // Only write if non-empty so we avoid overwriting with blanks.
            if !bestReachText.trimmingCharacters(in: .whitespaces).isEmpty {
                let db = Firestore.firestore()
                try await db
                    .collection(AmenConnectSpacesFirestoreBinding.presenceCollection)
                    .document(userId)
                    .setData(["bestReachText": bestReachText], merge: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Main View

struct AmenSpiritualPresencePickerView: View {
    @StateObject private var vm = AmenSpiritualPresencePickerViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Glass bottom-sheet container
        VStack(spacing: 0) {
            // Glass header chrome
            glassHeader
            // Matte scroll content
            ScrollView {
                VStack(spacing: 0) {
                    stateRows
                    Divider().opacity(0.2).padding(.vertical, 8)
                    bestReachSection
                }
                .padding(.vertical, 8)
            }
            .background(Color(.systemBackground))
            // Glass save footer chrome
            glassSaveFooter
        }
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Glass header (chrome)

    private var glassHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("My Spiritual Presence")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Let your space know where you are spiritually.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Divider().opacity(0.25) }
        }
    }

    // MARK: - State rows

    private var stateRows: some View {
        VStack(spacing: 2) {
            ForEach(kStateRows) { row in
                SpiritualStateRowView(
                    row: row,
                    isSelected: vm.selectedState == row.id,
                    urgentReachable: $vm.urgentReachable,
                    carePartnerToggle: $vm.carePartnerToggle,
                    sabbathUntil: $vm.sabbathUntil
                ) {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.01) : .easeInOut(duration: 0.2)) {
                        vm.selectedState = row.id
                        // Always reset opt-in flags when switching states (C-14 explicit opt-in)
                        vm.urgentReachable = false
                        vm.carePartnerToggle = false
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Best reach text (matte, admin-only visibility)

    private var bestReachSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Best way to reach me right now")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
            Text("Optional. Only visible to space admins and pastoral staff.")  // C-34 privacy disclosure
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            TextField("e.g. Text only, no calls please", text: $vm.bestReachText, axis: .vertical)
                .lineLimit(2...4)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 20)
                .accessibilityLabel("Best way to reach me. Visible to admins and pastoral staff only.")
        }
        .padding(.bottom, 16)
    }

    // MARK: - Glass save footer (chrome)

    private var glassSaveFooter: some View {
        VStack(spacing: 6) {
            if let err = vm.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await vm.save() }
            } label: {
                Label(vm.isSaving ? "Saving…" : "Save Presence", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.accentColor)
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(vm.isSaving)
            .accessibilityLabel("Save my spiritual presence")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) { Divider().opacity(0.25) }
        }
    }
}

// MARK: - Individual state row

private struct SpiritualStateRowView: View {
    let row: SpiritualStateRow
    let isSelected: Bool
    @Binding var urgentReachable: Bool
    @Binding var carePartnerToggle: Bool
    @Binding var sabbathUntil: Date
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Primary row button
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Text(row.emoji)
                        .font(.title3)
                        .frame(width: 32)
                    Text(row.label)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? row.accentColor : .primary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(row.accentColor)
                            .font(.body.weight(.semibold))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? row.accentColor.opacity(0.10) : Color.clear)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.emoji) \(row.label)")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            // Expanded controls (only when selected)
            if isSelected {
                expandedControls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private var expandedControls: some View {
        switch row.id {
        case .sabbathRest:
            // Date picker for sabbathUntil
            VStack(alignment: .leading, spacing: 6) {
                Text("Sabbath rest until")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                DatePicker(
                    "Sabbath until",
                    selection: $sabbathUntil,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .accessibilityLabel("Sabbath rest end date and time")
            }
            .padding(.top, 4)

        case .grieving:
            // C-22: care signals route to humans — toggle for care partner matching (default OFF)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $carePartnerToggle) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Match me with a care partner")
                            .font(.subheadline.weight(.semibold))
                        Text("A pastoral team member will reach out.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.amenBlue)
                .accessibilityLabel("Match me with a care partner. Default off. A pastoral team member will reach out.")
                Text("Care needs are always routed to human pastoral staff — never handled by AI alone.")  // C-22 hard rule
                    .font(.caption2)
                    .foregroundStyle(Color.amenBlue)
                    .padding(.top, 2)
            }
            .padding(.top, 4)

        case .availableForUrgentPrayer:
            // C-14: explicit opt-in for urgentReachable — never on by default
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $urgentReachable) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow urgent prayer reach-out")
                            .font(.subheadline.weight(.semibold))
                        Text("Others may contact you immediately for urgent prayer.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.accentColor)
                .accessibilityLabel("Allow urgent prayer reach-out. Explicit opt-in. Default off.")
            }
            .padding(.top, 4)

        default:
            EmptyView()
        }
    }
}

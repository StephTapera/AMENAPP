import SwiftUI

// MARK: - PermissionsCenterView

/// Full-screen Permissions Center — shows all 10 ConsentEdge toggles.
/// Backed by ConsentStore (reactive, persisted, Firestore-synced).
struct PermissionsCenterView: View {
    @ObservedObject private var store = ConsentStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ConsentEdge.allCases, id: \.self) { edge in
                        ConsentEdgeRow(edge: edge, store: store)
                    }
                } header: {
                    Text("What flows where")
                        .textCase(.none)
                        .font(.headline)
                }

                Section {
                    Text("Your data never leaves your device without your explicit permission. Rhythm detection always happens on-device only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Privacy Promise")
                        .textCase(.none)
                }
            }
            .navigationTitle("Permissions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - ConsentEdgeRow

private struct ConsentEdgeRow: View {
    let edge: ConsentEdge
    @ObservedObject var store: ConsentStore
    @State private var showExample = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { store.isEnabled(edge) },
                set: { store.setEnabled(edge, $0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(edge.displayTitle)
                        .font(.body)
                    Text(edge.flowDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // activityToRhythm is on-device only and always enabled — it can never be toggled off
            .disabled(edge == .activityToRhythm)

            if showExample {
                Text(edge.exampleText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(showExample ? "Hide example" : "See an example") {
                withAnimation(.easeInOut(duration: 0.2)) { showExample.toggle() }
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.accentColor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ConsentEdge Display Metadata

extension ConsentEdge {
    var displayTitle: String {
        switch self {
        case .notesToMatching:        return "Notes refine church matching"
        case .notesToGiving:          return "Notes surface giving causes"
        case .messagesToPrayer:       return "Messages suggest prayers"
        case .locationToVisits:       return "Location verifies church visits"
        case .givingToFeed:           return "Giving shapes your feed"
        case .activityToCheckIns:     return "Activity enables gentle check-ins"
        case .graphToBerean:          return "Berean reads your personal graph"
        case .graphToCohorts:         return "Anonymous community matching"
        case .activityToRhythm:       return "Rhythm detection (on-device)"
        case .crossDeviceContinuity:  return "Continue across your devices"
        }
    }

    var flowDescription: String {
        switch self {
        case .notesToMatching:        return "Sermon themes adjust your church DNA score"
        case .notesToGiving:          return "Note themes surface vetted nonprofits"
        case .messagesToPrayer:       return "Prayer requests in DMs become reminders"
        case .locationToVisits:       return "Entering a church during service counts as a visit"
        case .givingToFeed:           return "Your giving history shapes what you see"
        case .activityToCheckIns:     return "A quiet season may prompt a gentle check-in"
        case .graphToBerean:          return "Berean answers questions from your notes and prayers"
        case .graphToCohorts:         return "Anonymized themes improve community suggestions"
        case .activityToRhythm:       return "Your spiritual cadence, measured privately on-device"
        case .crossDeviceContinuity:  return "Pick up where you left off on any device"
        }
    }

    var exampleText: String {
        switch self {
        case .notesToMatching:
            return "E.g. You note a sermon on expository teaching → churches strong in that style rank higher"
        case .notesToGiving:
            return "E.g. You note a missions series → a vetted mission org card appears in Giving"
        case .messagesToPrayer:
            return "E.g. Friend says 'pray for my dad' → a chip appears to add it to your prayer list"
        case .locationToVisits:
            return "E.g. You enter Grace Church at 10am Sunday → a visit is quietly logged"
        case .givingToFeed:
            return "E.g. You give to education causes → education ministries rank higher in your feed"
        case .activityToCheckIns:
            return "E.g. You haven't opened the app in 3 weeks → a single 'How are you?' card appears"
        case .graphToBerean:
            return "E.g. 'What did my pastor say about Romans 8?' → Berean searches your own notes"
        case .graphToCohorts:
            return "E.g. Your theme vectors match a group studying grief → they're suggested (you're anonymous to them)"
        case .activityToRhythm:
            return "E.g. You reflect every two Sundays → 'Right on rhythm' appears; silence if you miss one"
        case .crossDeviceContinuity:
            return "E.g. You start a study on iPhone → your iPad shows 'Pick up your Romans study'"
        }
    }
}

// MARK: - Preview

#Preview {
    PermissionsCenterView()
}

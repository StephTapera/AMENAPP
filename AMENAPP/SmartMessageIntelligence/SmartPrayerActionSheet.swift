import SwiftUI

enum SmartPrayerVisibility: String, CaseIterable, Identifiable {
    case `private` = "Private"
    case selectedPeople = "Selected People"
    case space = "Space"

    var id: String { rawValue }
    var backendValue: String {
        switch self {
        case .private: return "private"
        case .selectedPeople: return "selected_people"
        case .space: return "space"
        }
    }
}

struct SmartPrayerActionSheet: View {
    let extractedText: String
    var onSave: (SmartPrayerVisibility) -> Void
    var onPrayNow: () -> Void
    var onReminder: () -> Void
    var onEncourage: () -> Void
    var onPraiseReport: () -> Void

    @State private var visibility: SmartPrayerVisibility = .private
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Prayer") {
                    Text(extractedText)
                }
                Section("Visibility") {
                    Picker("Visibility", selection: $visibility) {
                        ForEach(SmartPrayerVisibility.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Add to Prayer List", systemImage: "hands.sparkles") {
                        onSave(visibility)
                        dismiss()
                    }
                    Button("Pray Now", systemImage: "heart.text.square", action: onPrayNow)
                    Button("Set Reminder", systemImage: "bell", action: onReminder)
                    Button("Send Encouragement", systemImage: "paperplane", action: onEncourage)
                    Button("Mark Praise Report", systemImage: "checkmark.seal", action: onPraiseReport)
                }
            }
            .navigationTitle("Prayer Request")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
    }
}

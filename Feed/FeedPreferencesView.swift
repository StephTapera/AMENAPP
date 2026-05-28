import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class FeedPreferencesService: ObservableObject {
    @Published var preferences: FeedPreferences = .defaults
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    var userId: String? { Auth.auth().currentUser?.uid }

    func startListening() {
        guard let uid = userId else { return }
        listener = db.collection("users").document(uid)
            .collection("feedPreferences").document("current")
            .addSnapshotListener { [weak self] snapshot, _ in
                if let prefs = try? snapshot?.data(as: FeedPreferences.self) {
                    self?.preferences = prefs
                }
            }
    }

    func save() async {
        guard let uid = userId else { return }
        try? await db.collection("users").document(uid)
            .collection("feedPreferences").document("current")
            .setData(from: preferences)
    }

    deinit { listener?.remove() }
}

struct FeedPreferencesView: View {
    @StateObject private var service = FeedPreferencesService()
    @State private var selectedPriorityTags: Set<FeedPriorityTag> = []

    var body: some View {
        List {
            Section {
                toggleRow(title: "Giving Posts", subtitle: "See posts about charitable giving", isOn: $service.preferences.showGiving, color: Color(red: 0.83, green: 0.69, blue: 0.22))
                toggleRow(title: "Wellness Streaks", subtitle: "See wellness activity and streaks", isOn: $service.preferences.showWellness, color: Color(red: 0.10, green: 0.60, blue: 0.56))
                toggleRow(title: "Support Group Posts", subtitle: "See posts from support groups you follow", isOn: $service.preferences.showSupport, color: Color(red: 0.60, green: 0.50, blue: 0.90))
                toggleRow(title: "Bible Study Posts", subtitle: "See Bible study content", isOn: $service.preferences.showBibleStudy, color: Color(red: 0.83, green: 0.69, blue: 0.22))
                toggleRow(title: "Crisis Support Posts", subtitle: "See anonymous crisis posts (opt-in)", isOn: $service.preferences.showCrisis, color: Color(red: 0.40, green: 0.70, blue: 0.95))
            } header: {
                Text("Content Types").font(.custom("OpenSans-Bold", size: 13))
            }

            Section {
                priorityTagGrid
            } header: {
                Text("Priority Interests").font(.custom("OpenSans-Bold", size: 13))
            } footer: {
                Text("Posts matching your priority interests appear higher in your feed.")
                    .font(.custom("OpenSans-Regular", size: 12))
            }

            Section {
                Button(role: .destructive) {
                    service.preferences = .defaults
                    selectedPriorityTags = []
                    Task { await service.save() }
                } label: {
                    Text("Reset to Defaults").font(.custom("OpenSans-Regular", size: 15))
                }
                .accessibilityLabel("Reset feed preferences to defaults")
            }
        }
        .navigationTitle("Feed Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { service.startListening() }
        .onChange(of: service.preferences.showGiving) { _, _ in Task { await service.save() } }
        .onChange(of: service.preferences.showWellness) { _, _ in Task { await service.save() } }
        .onChange(of: service.preferences.showSupport) { _, _ in Task { await service.save() } }
        .onChange(of: service.preferences.showBibleStudy) { _, _ in Task { await service.save() } }
        .onChange(of: service.preferences.showCrisis) { _, _ in Task { await service.save() } }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>, color: Color) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(subtitle).font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
            }
        }
        .tint(color)
        .accessibilityLabel("\(title): \(isOn.wrappedValue ? "on" : "off")")
    }

    private var priorityTagGrid: some View {
        FlowLayoutTags(tags: FeedPriorityTag.allCases.map { $0.rawDisplayName }, selectedTags: Binding(
            get: { Set(selectedPriorityTags.map { $0.rawDisplayName }) },
            set: { newSet in
                selectedPriorityTags = Set(FeedPriorityTag.allCases.filter { newSet.contains($0.rawDisplayName) })
                service.preferences.priorityTags = Array(newSet)
                Task { await service.save() }
            }
        ))
    }
}

struct FlowLayoutTags: View {
    let tags: [String]
    @Binding var selectedTags: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let rows = chunked(tags, size: 3)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { tag in
                        let isSelected = selectedTags.contains(tag)
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                                if isSelected { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                            }
                        } label: {
                            Text(tag)
                                .font(.custom("OpenSans-Regular", size: 12))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(isSelected ? Color(red: 0.10, green: 0.60, blue: 0.56) : AmenTheme.Colors.surfaceChip)
                                .foregroundStyle(isSelected ? .white : AmenTheme.Colors.textPrimary)
                                .cornerRadius(14)
                        }
                        .accessibilityLabel(tag)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func chunked(_ array: [String], size: Int) -> [[String]] {
        stride(from: 0, to: array.count, by: size).map { Array(array[$0..<min($0 + size, array.count)]) }
    }
}

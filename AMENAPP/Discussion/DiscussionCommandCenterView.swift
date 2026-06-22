// DiscussionCommandCenterView.swift — AMEN App
import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

struct DiscussionDashboard: Sendable {
    var questionCount: Int = 0
    var prayerCount: Int = 0
    var mentorCount: Int = 0
    var topKeywords: [String] = []
    var suggestedResponses: [String] = []
    var healthStatus: String = "healthy"
}

@MainActor
final class DiscussionCommandCenterViewModel: ObservableObject {
    @Published var dashboard: DiscussionDashboard?
    @Published var isLoading = false
    @Published var slowModeSeconds: Double = 30
    @Published var contextRequirement: String = "none"
    @Published var isLocked = false

    private let functions = Functions.functions()
    private let db = Firestore.firestore()
    let threadId: String

    init(threadId: String) { self.threadId = threadId }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let callable = functions.httpsCallable("getDiscussionDashboard")
        guard let result = try? await callable.call(["threadId": threadId]),
              let data = result.data as? [String: Any] else { return }
        dashboard = DiscussionDashboard(
            questionCount:      data["questionCount"]      as? Int      ?? 0,
            prayerCount:        data["prayerCount"]        as? Int      ?? 0,
            mentorCount:        data["mentorCount"]        as? Int      ?? 0,
            topKeywords:        data["topKeywords"]        as? [String] ?? [],
            suggestedResponses: data["suggestedResponses"] as? [String] ?? [],
            healthStatus:       data["healthStatus"]       as? String   ?? "healthy"
        )
    }

    func toggleLock() {
        isLocked.toggle()
        Task {
            try? await db.collection("threads").document(threadId)
                .updateData(["isLocked": isLocked, "updatedAt": Timestamp(date: Date())])
        }
    }
}

struct DiscussionCommandCenterView: View {
    let threadId: String
    let threadTitle: String?
    @StateObject private var vm: DiscussionCommandCenterViewModel
    @Environment(\.dismiss) private var dismiss

    init(threadId: String, threadTitle: String?) {
        self.threadId = threadId
        self.threadTitle = threadTitle
        _vm = StateObject(wrappedValue: DiscussionCommandCenterViewModel(threadId: threadId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                if vm.isLoading {
                    ProgressView().tint(Color.accentColor)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            if let d = vm.dashboard {
                                healthCard(d.healthStatus)
                                statsRow(d)
                                if !d.topKeywords.isEmpty { keywordsSection(d.topKeywords) }
                                if !d.suggestedResponses.isEmpty { suggestionsSection(d.suggestedResponses) }
                            }
                            controlsSection
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Discussion Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.accentColor)
                }
            }
        }
        .task { await vm.load() }
    }

    private func healthCard(_ status: String) -> some View {
        let color: Color = status == "heated" || status == "escalating" ? .orange : .green
        return HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text("Discussion Health: \(status.capitalized)")
                .font(.systemScaled(14, weight: .semibold)).foregroundStyle(Color.white)
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color.opacity(0.3), lineWidth: 1))
        )
    }

    private func statsRow(_ d: DiscussionDashboard) -> some View {
        HStack(spacing: 12) {
            statCell(icon: "questionmark.circle.fill", value: d.questionCount, label: "Questions")
            statCell(icon: "hands.sparkles.fill", value: d.prayerCount, label: "Prayers")
            statCell(icon: "person.2.circle.fill", value: d.mentorCount, label: "Mentors")
        }
    }

    private func statCell(icon: String, value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.systemScaled(20)).foregroundStyle(Color.accentColor)
            Text("\(value)").font(.systemScaled(22, weight: .bold)).foregroundStyle(Color.white)
            Text(label).font(.systemScaled(11)).foregroundStyle(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
    }

    private func keywordsSection(_ keywords: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOP TOPICS").font(.systemScaled(10, weight: .bold)).foregroundStyle(Color.white.opacity(0.35)).kerning(1.2)
            CommandCenterFlowLayout(spacing: 6) {
                ForEach(keywords, id: \.self) { kw in
                    Text(kw).font(.systemScaled(11, weight: .medium)).foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private func suggestionsSection(_ suggestions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SUGGESTED HOST RESPONSES").font(.systemScaled(10, weight: .bold)).foregroundStyle(Color.white.opacity(0.35)).kerning(1.2)
            ForEach(suggestions, id: \.self) { s in
                HStack {
                    Text(s).font(.systemScaled(13)).foregroundStyle(Color.white.opacity(0.8))
                    Spacer()
                    Image(systemName: "chevron.right").font(.systemScaled(11)).foregroundStyle(Color.white.opacity(0.25))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial))
            }
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CONTROLS").font(.systemScaled(10, weight: .bold)).foregroundStyle(Color.white.opacity(0.35)).kerning(1.2)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Slow Mode: \(Int(vm.slowModeSeconds))s").font(.systemScaled(13)).foregroundStyle(Color.white.opacity(0.8))
                    Spacer()
                }
                Slider(value: $vm.slowModeSeconds, in: 10...300, step: 10)
                    .tint(Color.accentColor)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))

            Button(action: vm.toggleLock) {
                HStack {
                    Image(systemName: vm.isLocked ? "lock.fill" : "lock.open.fill")
                        .font(.systemScaled(14))
                    Text(vm.isLocked ? "Unlock Discussion" : "Lock Discussion")
                        .font(.systemScaled(14, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(vm.isLocked ? .red : Color.accentColor)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Flow Layout (private to this file)

private struct CommandCenterFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            rowH = max(rowH, size.height); x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowH = max(rowH, size.height); x += size.width + spacing
        }
    }
}

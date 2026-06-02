import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - Covenant Manage View
// Creator/admin command center. Entry point for all creator tools.
// Requires canManageCovenant permission on current membership.

struct AmenCovenantManageView: View {
    let covenantId: String
    @EnvironmentObject var vm: AmenCovenantViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var manageVM = AmenCovenantManageViewModel()
    @State private var showComposer = false
    @State private var showEventsSheet = false
    @State private var showStoriesSheet = false
    @State private var showModePickerDialog = false
    @State private var showSettingsAlert = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if manageVM.isLoading && manageVM.covenant == nil {
                        loadingPlaceholder
                    } else {
                        headerSection
                        quickStatsStrip
                        toolsGrid
                        postNowButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Manage Community")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if manageVM.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .task { await manageVM.load(covenantId: covenantId) }
            .sheet(isPresented: $showComposer) {
                AmenCovenantPostComposerView(covenantId: covenantId, preselectedType: nil)
            }
            .sheet(isPresented: $showEventsSheet) {
                AmenCovenantEventsView(covenantId: covenantId)
                    .environmentObject(vm)
            }
            .sheet(isPresented: $showStoriesSheet) {
                AmenCovenantStoriesComposerView(covenantId: covenantId)
            }
            .confirmationDialog("Change Operating Mode", isPresented: $showModePickerDialog, titleVisibility: .visible) {
                ForEach(CovenantOperatingMode.allCases, id: \.self) { mode in
                    Button(mode.displayName) {
                        Task { await manageVM.updateOperatingMode(mode, covenantId: covenantId) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Select a mode to configure how your community experiences the space right now.")
            }
            .alert("Coming Soon", isPresented: $showSettingsAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Advanced settings are being built. Check back soon.")
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let covenant = manageVM.covenant {
                Text(covenant.name)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Button {
                    showModePickerDialog = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: covenant.operatingMode.icon)
                            .font(.caption.bold())
                        Text(covenant.operatingMode.displayName)
                            .font(.caption.bold())
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(modeColor(for: covenant.operatingMode))
                }
                .accessibilityLabel("Operating mode: \(covenant.operatingMode.displayName). Tap to change.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Quick Stats Strip

    private var quickStatsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                statCard(
                    value: manageVM.covenant.map { "\($0.memberCount)" } ?? "--",
                    label: "Members",
                    icon: "person.2.fill",
                    color: .blue
                )
                statCard(
                    value: manageVM.covenant.map { "\($0.paidMemberCount)" } ?? "--",
                    label: "Paid",
                    icon: "crown.fill",
                    color: .amber
                )
                statCard(
                    value: "\(manageVM.activeRoomCount)",
                    label: "Rooms",
                    icon: "bubble.left.and.bubble.right.fill",
                    color: .teal
                )
                statCard(
                    value: "\(manageVM.pendingModerationCount)",
                    label: "Pending",
                    icon: "shield.lefthalf.filled",
                    color: manageVM.pendingModerationCount > 0 ? .orange : .secondary
                )
            }
            .padding(.horizontal, 1)
        }
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 76, height: 80)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Tools Grid

    private var toolsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(ManageTool.allCases, id: \.self) { tool in
                toolTile(tool)
            }
        }
    }

    private func toolTile(_ tool: ManageTool) -> some View {
        Button {
            handleToolTap(tool)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(tool.tint.opacity(0.15))
                            .frame(width: 38, height: 38)
                        Image(systemName: tool.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tool.tint)
                    }

                    if tool == .moderation && manageVM.pendingModerationCount > 0 {
                        Spacer()
                        Text("\(manageVM.pendingModerationCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.orange, in: Capsule())
                            .accessibilityLabel("\(manageVM.pendingModerationCount) pending")
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(tool.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tool.title). \(tool.description)")
    }

    // MARK: - Post Now Button

    private var postNowButton: some View {
        Button {
            showComposer = true
        } label: {
            Label("Post Now", systemImage: "square.and.pencil")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.accentColor.opacity(0.35), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Post Now")
    }

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Loading community tools…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Tool Action Routing

    private func handleToolTap(_ tool: ManageTool) {
        switch tool {
        case .posts:
            vm.navigate(to: .contentCalendar(covenantId: covenantId))
        case .rooms:
            vm.navigate(to: .covenantHub(covenantId: covenantId))
        case .members:
            vm.navigate(to: .memberDirectory(covenantId: covenantId))
        case .moderation:
            vm.navigate(to: .moderation(covenantId: covenantId))
        case .revenue:
            vm.navigate(to: .analytics(covenantId: covenantId))
        case .events:
            showEventsSheet = true
        case .stories:
            showStoriesSheet = true
        case .settings:
            showSettingsAlert = true
        }
    }

    // MARK: - Helpers

    private func modeColor(for mode: CovenantOperatingMode) -> Color {
        switch mode {
        case .teaching: return .blue
        case .prayer:   return .purple
        case .event:    return .orange
        case .quiet:    return .secondary
        case .launch:   return .green
        }
    }
}

// MARK: - Manage Tool Enum

private enum ManageTool: String, CaseIterable {
    case posts, rooms, members, moderation, revenue, events, stories, settings

    var title: String {
        switch self {
        case .posts:      return "Posts"
        case .rooms:      return "Rooms"
        case .members:    return "Members"
        case .moderation: return "Moderation"
        case .revenue:    return "Revenue"
        case .events:     return "Events"
        case .stories:    return "Stories"
        case .settings:   return "Settings"
        }
    }

    var description: String {
        switch self {
        case .posts:      return "Schedule and publish content"
        case .rooms:      return "Manage discussion spaces"
        case .members:    return "View and manage your community"
        case .moderation: return "Review flagged content"
        case .revenue:    return "MRR, tiers, and member health"
        case .events:     return "Create and manage events"
        case .stories:    return "Share ephemeral moments"
        case .settings:   return "Community configuration"
        }
    }

    var icon: String {
        switch self {
        case .posts:      return "square.and.pencil"
        case .rooms:      return "bubble.left.and.bubble.right"
        case .members:    return "person.2"
        case .moderation: return "shield"
        case .revenue:    return "chart.bar.xaxis"
        case .events:     return "calendar"
        case .stories:    return "circle.hexagongrid"
        case .settings:   return "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .posts:      return .blue
        case .rooms:      return .teal
        case .members:    return .purple
        case .moderation: return .orange
        case .revenue:    return .green
        case .events:     return .pink
        case .stories:    return .indigo
        case .settings:   return .gray
        }
    }
}

// MARK: - Color Extension

private extension Color {
    static let amber = Color(red: 0.98, green: 0.72, blue: 0.05)
}

// MARK: - Stub Views


/// Scaffolded stories composer. Full implementation lives in a dedicated file.
struct AmenCovenantStoriesComposerView: View {
    let covenantId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Stories")
                    .font(.title3.bold())
                Text("Share ephemeral moments with your community.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("New Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Manage ViewModel

@MainActor
final class AmenCovenantManageViewModel: ObservableObject {
    @Published var covenant: Covenant?
    @Published var pendingModerationCount: Int = 0
    @Published var activeRoomCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let db = Firestore.firestore()

    func load(covenantId: String) async {
        isLoading = true
        defer { isLoading = false }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadCovenant(covenantId: covenantId) }
            group.addTask { await self.loadModerationCount(covenantId: covenantId) }
            group.addTask { await self.loadRoomCount(covenantId: covenantId) }
        }
    }

    private func loadCovenant(covenantId: String) async {
        do {
            let doc = try await db.collection("covenants").document(covenantId).getDocument()
            covenant = try doc.data(as: Covenant.self)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadModerationCount(covenantId: String) async {
        do {
            let items = try await CovenantService.shared.loadModerationQueue(covenantId: covenantId)
            pendingModerationCount = items.filter { $0.status == .pending }.count
        } catch {
            pendingModerationCount = 0
        }
    }

    private func loadRoomCount(covenantId: String) async {
        do {
            let snap = try await db.collection("covenants").document(covenantId)
                .collection("rooms")
                .getDocuments()
            activeRoomCount = snap.documents.count
        } catch {
            activeRoomCount = 0
        }
    }

    func updateOperatingMode(_ mode: CovenantOperatingMode, covenantId: String) async {
        guard let uid = Auth.auth().currentUser?.uid,
              let covenant = covenant,
              covenant.creatorId == uid else { return }
        do {
            try await db.collection("covenants").document(covenantId)
                .updateData(["operatingMode": mode.rawValue])
            self.covenant?.operatingMode = mode
        } catch {
            self.error = error.localizedDescription
        }
    }
}

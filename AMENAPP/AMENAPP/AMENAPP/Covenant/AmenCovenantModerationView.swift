import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - Covenant Moderation View
// Lightweight overview of community moderation health.
// Links through to AmenCovenantModerationQueueView for full queue management.
// Creator/moderator access only.

struct AmenCovenantModerationView: View {
    let covenantId: String
    @EnvironmentObject var vm: AmenCovenantViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var moderationVM = AmenCovenantModerationViewModel()
    @StateObject private var platformQueueVM = PlatformModerationQueueViewModel()
    @State private var showQueue = false
    @State private var guidelinesExpanded = false
    @State private var showGuidelinesEditAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if moderationVM.isLoading && moderationVM.lastUpdated == moderationVM.initialLoadDate {
                    loadingPlaceholder
                } else {
                    statusSummarySection
                    openQueueButton
                    platformQueueSection
                    recentActivitySection
                    communityGuidelinesSection
                    escalationInfoRow
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Moderation Center")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await moderationVM.refresh(covenantId: covenantId) }
                } label: {
                    if moderationVM.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .accessibilityLabel("Refresh moderation data")
                .disabled(moderationVM.isLoading)
            }
        }
        .task { await moderationVM.load(covenantId: covenantId) }
        .task { await platformQueueVM.load() }
        .sheet(isPresented: $showQueue) {
            AmenCovenantModerationQueueView(covenantId: covenantId)
                .environmentObject(vm)
        }
        .alert("Coming Soon", isPresented: $showGuidelinesEditAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Custom community guidelines editing is being built. Check back soon.")
        }
    }

    // MARK: - Header Caption

    private var lastUpdatedCaption: String {
        let interval = Date().timeIntervalSince(moderationVM.lastUpdated)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }

    // MARK: - Status Summary Cards

    private var statusSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Queue Status")
                    .font(.headline)
                Spacer()
                Text("Updated \(lastUpdatedCaption)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                statusCard(
                    count: moderationVM.pendingCount,
                    label: "Pending",
                    color: .orange,
                    icon: "clock.fill"
                )
                statusCard(
                    count: moderationVM.reviewingCount,
                    label: "Reviewing",
                    color: .blue,
                    icon: "eye.fill"
                )
                statusCard(
                    count: moderationVM.escalatedCount,
                    label: "Escalated",
                    color: .red,
                    icon: "exclamationmark.triangle.fill"
                )
            }
        }
    }

    private func statusCard(count: Int, label: String, color: Color, icon: String) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, alignment: .center)

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color, in: Capsule())
                        .offset(x: 14, y: -6)
                }
            }
            .padding(.top, 8)

            Text(count == 0 ? "None" : "\(count)")
                .font(.title3.bold())
                .foregroundStyle(count > 0 ? color : .secondary)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(count) item\(count == 1 ? "" : "s")")
    }

    // MARK: - Open Queue Button

    private var openQueueButton: some View {
        Button {
            showQueue = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Moderation Queue")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(moderationVM.pendingCount > 0
                        ? "\(moderationVM.pendingCount) item\(moderationVM.pendingCount == 1 ? "" : "s") need your review"
                        : "Queue is clear")
                        .font(.subheadline)
                        .foregroundStyle(moderationVM.pendingCount > 0 ? .orange : .secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open moderation queue. \(moderationVM.pendingCount) items pending.")
    }

    // MARK: - Recent Activity Log

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Resolutions")
                .font(.headline)

            if moderationVM.recentLogs.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.tertiary)
                    Text("No recent moderation activity.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(moderationVM.recentLogs.enumerated()), id: \.element.id) { index, log in
                        recentLogRow(log)
                        if index < moderationVM.recentLogs.count - 1 {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
            }
        }
    }

    private func recentLogRow(_ log: AmenCovenantModerationViewModel.RecentLogItem) -> some View {
        HStack(spacing: 12) {
            // Reviewer initials avatar
            ZStack {
                Circle()
                    .fill(statusColorForLog(log.status).opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(log.reviewerInitials)
                    .font(.caption.bold())
                    .foregroundStyle(statusColorForLog(log.status))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(log.snippet)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(timeAgo(from: log.resolvedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusChip(log.status)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Content: \(log.snippet). Status: \(log.status). Resolved \(timeAgo(from: log.resolvedAt)) by \(log.reviewerInitials).")
    }

    private func statusChip(_ status: String) -> some View {
        Text(status.capitalized)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColorForLog(status), in: Capsule())
    }

    private func statusColorForLog(_ status: String) -> Color {
        switch status.lowercased() {
        case "approved": return .green
        case "blocked":  return .red
        case "escalated": return .orange
        case "request_edit", "requestedit": return .blue
        default: return .gray
        }
    }

    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    // MARK: - Community Guidelines Section

    private var communityGuidelinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Community Guidelines")
                .font(.headline)

            VStack(spacing: 0) {
                // Expandable header
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                        guidelinesExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.clipboard.fill")
                            .foregroundStyle(.blue)
                        Text("View Default Rules")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: guidelinesExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Community guidelines. \(guidelinesExpanded ? "Collapse" : "Expand")")

                if guidelinesExpanded {
                    Divider()
                        .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(defaultGuidelines.enumerated()), id: \.offset) { index, rule in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1).")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.blue)
                                    .frame(width: 20, alignment: .leading)
                                Text(rule)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Button {
                            showGuidelinesEditAlert = true
                        } label: {
                            Text("Edit Guidelines")
                                .font(.subheadline.bold())
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit community guidelines")
                    }
                    .padding(16)
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        }
    }

    private let defaultGuidelines: [String] = [
        "Treat all members with dignity, respect, and Christ-like love.",
        "No harassment, hate speech, or discriminatory language of any kind.",
        "Keep discussions rooted in Scripture and constructive dialogue.",
        "No spam, self-promotion, or off-topic commercial content.",
        "Protect the privacy of other members — what's shared here, stays here."
    ]

    // MARK: - Escalation Info Row

    private var escalationInfoRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 28)

            Text("Escalated items are reviewed by AMEN Trust & Safety within 48 hours.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Loading moderation data…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Moderation ViewModel

@MainActor
final class AmenCovenantModerationViewModel: ObservableObject {

    // MARK: - Recent Log Item

    struct RecentLogItem: Identifiable {
        var id: String
        var snippet: String
        var status: String
        var resolvedAt: Date
        var reviewerInitials: String
    }

    // MARK: - Published State

    @Published var pendingCount: Int = 0
    @Published var reviewingCount: Int = 0
    @Published var escalatedCount: Int = 0
    @Published var recentLogs: [RecentLogItem] = []
    @Published var isLoading: Bool = false
    @Published var lastUpdated: Date = Date()

    /// Used to determine first-load state for loading placeholder.
    let initialLoadDate = Date()

    private let db = Firestore.firestore()

    // MARK: - Load

    func load(covenantId: String) async {
        isLoading = true
        defer { isLoading = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadQueueCounts(covenantId: covenantId) }
            group.addTask { await self.loadRecentLogs(covenantId: covenantId) }
        }

        lastUpdated = Date()
    }

    func refresh(covenantId: String) async {
        await load(covenantId: covenantId)
    }

    // MARK: - Queue Counts

    private func loadQueueCounts(covenantId: String) async {
        do {
            // Load all statuses we care about in one pass via loadModerationQueue + broader query
            let allItems = try await loadAllModerationItems(covenantId: covenantId)
            pendingCount = allItems.filter { $0.status == .pending }.count
            reviewingCount = allItems.filter { $0.status == .reviewing }.count
            escalatedCount = allItems.filter { $0.status == .escalated }.count
        } catch {
            pendingCount = 0
            reviewingCount = 0
            escalatedCount = 0
        }
    }

    private func loadAllModerationItems(covenantId: String) async throws -> [CovenantModerationItem] {
        let snap = try await db.collection("covenants").document(covenantId)
            .collection("moderationQueue")
            .whereField("status", in: [
                CovenantModerationItem.ModerationStatus.pending.rawValue,
                CovenantModerationItem.ModerationStatus.reviewing.rawValue,
                CovenantModerationItem.ModerationStatus.escalated.rawValue
            ])
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: CovenantModerationItem.self) }
    }

    // MARK: - Recent Logs

    private func loadRecentLogs(covenantId: String) async {
        do {
            let snap = try await db.collection("covenants").document(covenantId)
                .collection("moderationLogs")
                .order(by: "resolvedAt", descending: true)
                .limit(to: 5)
                .getDocuments()

            recentLogs = snap.documents.compactMap { doc -> RecentLogItem? in
                let data = doc.data()
                guard let snippet = data["contentSnippet"] as? String,
                      let status = data["status"] as? String,
                      let resolvedAtTs = data["resolvedAt"] as? Timestamp,
                      let reviewerId = data["resolvedBy"] as? String else {
                    return nil
                }
                let initials = initialsFromId(reviewerId)
                return RecentLogItem(
                    id: doc.documentID,
                    snippet: String(snippet.prefix(80)),
                    status: status,
                    resolvedAt: resolvedAtTs.dateValue(),
                    reviewerInitials: initials
                )
            }
        } catch {
            recentLogs = []
        }
    }

    // MARK: - Helpers

    private func initialsFromId(_ uid: String) -> String {
        // Use last 2 characters of UID as placeholder initials until display names are available
        let suffix = String(uid.suffix(2)).uppercased()
        return suffix.isEmpty ? "??" : suffix
    }
}

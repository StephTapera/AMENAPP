// AmenRhythmAwareDigestView.swift
// AMEN Spaces — Agent 4: Spaces Intelligence
//
// Digest card that respects Sabbath and liturgical season.
// Sabbath or fasting or grieving: NO leadership pulse pings, NO notification prompts.
// Glass summary card when active; matte rest card when sabbath.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Design Tokens

private extension Color {
    static let amenGold   = Color(hex: "#D9A441")
    static let amenPurple = Color(hex: "#6E4BB5")
    static let amenBlue   = Color(hex: "#245B8F")
    static let amenBlack  = Color(hex: "#070607")

    init(hex: String) {
        let stripped = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: stripped).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Digest Metrics

struct AmenSpaceDigestMetrics {
    var unreadCount: Int
    var openPrayerRequests: Int
    var openTasksForMe: Int
    var upcomingServeSlot: String?
}

// MARK: - Digest ViewModel

@MainActor
final class AmenRhythmAwareDigestViewModel: ObservableObject {
    @Published var metrics = AmenSpaceDigestMetrics(
        unreadCount: 0,
        openPrayerRequests: 0,
        openTasksForMe: 0,
        upcomingServeSlot: nil
    )
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()

    func load(spaceId: String, userId: String) async {
        guard let _ = Auth.auth().currentUser else { return }
        isLoading = true
        errorMessage = nil

        do {
            let snapshot = try await db
                .collection(AmenConnectSpacesFirestoreBinding.spacesCollection)
                .document(spaceId)
                .collection(AmenConnectSpacesFirestoreBinding.itemsSubcollection)
                .getDocuments()

            let items = snapshot.documents.compactMap { doc -> AmenConnectSpacesDerivedItem? in
                try? AmenConnectSpacesFirestoreBinding.bindDerivedItem(doc)
            }

            let prayerCount = items.filter { $0.kind == .prayer && $0.status == .open }.count
            let taskCount   = items.filter {
                $0.kind == .task && $0.status == .open && $0.owner == userId
            }.count
            let serveSlot = items
                .filter { $0.kind == .serveSlot && $0.status == .open }
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                .first

            let serveTitle: String?
            if let slot = serveSlot {
                if let due = slot.due {
                    serveTitle = "\(slot.title) — \(due.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
                } else {
                    serveTitle = slot.title
                }
            } else {
                serveTitle = nil
            }

            metrics = AmenSpaceDigestMetrics(
                unreadCount: 0, // unread count comes from message listener in production
                openPrayerRequests: prayerCount,
                openTasksForMe: taskCount,
                upcomingServeSlot: serveTitle
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Sabbath Rest Card (matte)

private struct SabbathRestCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars")
                .font(.system(size: 22))
                .foregroundStyle(Color.amenGold)

            VStack(alignment: .leading, spacing: 3) {
                Text("Digest paused for your Sabbath.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.90))

                Text("Rest well.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(16)
        .background(
            // Matte — sabbath state never uses glass
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#1A161E"))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
        .accessibilityLabel("Digest paused for your Sabbath. Rest well.")
    }
}

// MARK: - Digest Metric Row

private struct DigestMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.75))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
        }
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Active Digest Card (glass)

private struct ActiveDigestCard: View {
    let metrics: AmenSpaceDigestMetrics

    var body: some View {
        VStack(spacing: 14) {
            // Unread count (no vanity engagement metrics per design rules)
            DigestMetricRow(
                icon: "bubble.left.and.bubble.right",
                label: "Unread messages",
                value: "\(metrics.unreadCount)",
                tint: Color.white.opacity(0.60)
            )

            Divider().opacity(0.10)

            DigestMetricRow(
                icon: "hands.sparkles",
                label: "Open prayer requests",
                value: "\(metrics.openPrayerRequests)",
                tint: Color.amenGold
            )

            Divider().opacity(0.10)

            DigestMetricRow(
                icon: "checkmark.square",
                label: "Open tasks awaiting me",
                value: "\(metrics.openTasksForMe)",
                tint: Color.amenBlue
            )

            if let slot = metrics.upcomingServeSlot {
                Divider().opacity(0.10)

                DigestMetricRow(
                    icon: "person.badge.clock",
                    label: "Upcoming serve slot",
                    value: slot,
                    tint: Color.amenPurple
                )
            }
        }
        .padding(16)
        .background(
            // Glass card — chrome surface
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }
}

// MARK: - AmenRhythmAwareDigestView

struct AmenRhythmAwareDigestView: View {
    let presence: AmenConnectSpacesPresence
    let spaceId: String

    @StateObject private var viewModel = AmenRhythmAwareDigestViewModel()

    // "Leadership pulse" is suppressed for these states
    private static let suppressedStates: Set<AmenConnectSpacesSpiritualState> = [
        .sabbathRest, .fasting, .grieving
    ]

    private var isSabbath: Bool {
        if presence.spiritualState == .sabbathRest { return true }
        if let sabbathUntil = presence.sabbathUntil, sabbathUntil > Date() { return true }
        return false
    }

    private var userId: String {
        presence.userId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isSabbath {
                SabbathRestCard()
            } else {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(Color.amenGold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ActiveDigestCard(metrics: viewModel.metrics)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.amenGold.opacity(0.70))
                        .padding(.horizontal, 4)
                }
            }
        }
        .task {
            guard !isSabbath else { return }
            await viewModel.load(spaceId: spaceId, userId: userId)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 24) {
            // Active state
            AmenRhythmAwareDigestView(
                presence: AmenConnectSpacesPresence(
                    userId: "user-1",
                    spiritualState: .inTheWord,
                    urgentReachable: true,
                    sabbathUntil: nil,
                    updatedAt: Date()
                ),
                spaceId: "demo-space"
            )

            // Sabbath state
            AmenRhythmAwareDigestView(
                presence: AmenConnectSpacesPresence(
                    userId: "user-1",
                    spiritualState: .sabbathRest,
                    urgentReachable: false,
                    sabbathUntil: Date().addingTimeInterval(3600 * 18),
                    updatedAt: Date()
                ),
                spaceId: "demo-space"
            )

            // sabbathUntil in future triggers rest card
            AmenRhythmAwareDigestView(
                presence: AmenConnectSpacesPresence(
                    userId: "user-1",
                    spiritualState: .fasting,
                    urgentReachable: false,
                    sabbathUntil: Date().addingTimeInterval(3600 * 5),
                    updatedAt: Date()
                ),
                spaceId: "demo-space"
            )
        }
        .padding()
    }
    .background(Color(hex: "#070607"))
}
#endif

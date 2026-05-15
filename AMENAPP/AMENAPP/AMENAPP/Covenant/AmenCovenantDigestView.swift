import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Amen Covenant Digest View

struct AmenCovenantDigestView: View {
    let covenantId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm = AmenCovenantDigestViewModel()
    @State private var unreadRooms: [CovenantRoom] = []
    @State private var showMarkReadToast: Bool = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 20) {
                        if vm.isLoading {
                            loadingSection
                        } else if let digest = vm.digest {
                            summaryCard(digest)
                            if !digest.highlights.isEmpty {
                                highlightsSection(digest.highlights)
                            }
                            if !digest.prayerUpdates.isEmpty {
                                prayerUpdatesSection(digest.prayerUpdates)
                            }
                            if !digest.upcomingEvents.isEmpty {
                                upcomingEventsSection(digest.upcomingEvents)
                            }
                            if !unreadRooms.isEmpty {
                                unreadRoomsStrip
                            }
                            markReadButton(digest)
                        } else {
                            emptyDigestCard
                        }

                        if let errorMsg = vm.error {
                            errorCard(errorMsg)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                }

                // Toast overlay
                if showMarkReadToast {
                    toastBanner
                        .transition(
                            reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                        )
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navToolbar }
            .task {
                await vm.load(covenantId: covenantId)
                unreadRooms = await vm.loadUnreadRooms(covenantId: covenantId)
            }
        }
    }

    // MARK: - Nav Toolbar

    @ToolbarContentBuilder
    private var navToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text("Your Daily Digest")
                    .font(.headline)
                if let generatedAt = vm.digest?.generatedAt {
                    Text("Generated \(relativeTime(from: generatedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
    }

    // MARK: - Summary Card

    private func summaryCard(_ digest: AmenCovenantDigestViewModel.DigestData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text("Berean AI")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
                Spacer()
            }

            Text(digest.summaryTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text(digest.summaryBody)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(glassCard(tint: Color.orange.opacity(0.06)))
    }

    // MARK: - Highlights Section

    private func highlightsSection(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "What Happened", icon: "list.bullet")
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Color.purple.opacity(0.5))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        index % 2 == 0
                        ? Color(uiColor: .secondarySystemGroupedBackground)
                        : Color(uiColor: .tertiarySystemGroupedBackground)
                    )
                    if index < items.count - 1 {
                        Divider().padding(.leading, 34)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: - Prayer Updates Section

    private func prayerUpdatesSection(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Prayer Requests", icon: "hands.sparkles.fill")
            VStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 12) {
                        Image(systemName: "hands.sparkles.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.purple)
                            .frame(width: 28)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        statusChip(label: "Open", color: .blue)
                    }
                    .padding(14)
                    .background(glassCard(tint: Color.purple.opacity(0.04)))
                }
            }
        }
    }

    // MARK: - Upcoming Events Section

    private func upcomingEventsSection(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Coming Up", icon: "calendar")
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.orange)
                            .frame(width: 28)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(glassCard(tint: .clear))
        }
    }

    // MARK: - Unread Rooms Strip

    private var unreadRoomsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Unread Rooms", icon: "bubble.left.and.bubble.right.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(unreadRooms) { room in
                        roomPill(room)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func roomPill(_ room: CovenantRoom) -> some View {
        HStack(spacing: 7) {
            Image(systemName: room.type.icon)
                .font(.system(size: 13))
                .foregroundStyle(.purple)
            Text(room.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if room.unreadCount > 0 {
                Text("\(room.unreadCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(room.name), \(room.unreadCount) unread")
    }

    // MARK: - Catch Me Up / Generate Button

    private var emptyDigestCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "newspaper")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No digest yet")
                .font(.title3.weight(.semibold))
            Text("Tap below to generate your daily catch-up.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            generateButton
        }
        .padding(32)
        .background(glassCard(tint: .clear))
    }

    private var generateButton: some View {
        Button {
            Task { await vm.generateDigest(covenantId: covenantId) }
        } label: {
            HStack(spacing: 8) {
                if vm.isGenerating {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(vm.isGenerating ? "Generating…" : "Catch me up")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 13)
            .background(
                Capsule()
                    .fill(Color.purple)
                    .shadow(color: .purple.opacity(0.3), radius: 10, y: 4)
            )
        }
        .buttonStyle(.plain)
        .disabled(vm.isGenerating)
    }

    private func markReadButton(_ digest: AmenCovenantDigestViewModel.DigestData) -> some View {
        Button {
            Task {
                await vm.markRead(covenantId: covenantId)
                withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75)) {
                    showMarkReadToast = true
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation {
                    showMarkReadToast = false
                }
            }
        } label: {
            Text("Mark as read")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading your digest…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Error Card

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(16)
        .background(glassCard(tint: Color.red.opacity(0.05)))
    }

    // MARK: - Toast Banner

    private var toastBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
            Text("Marked as read")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        )
    }

    // MARK: - Helper Views

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.purple)
            Text(title)
                .font(.headline)
        }
    }

    private func statusChip(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func glassCard(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(tint)
            )
            .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Digest ViewModel

@MainActor
final class AmenCovenantDigestViewModel: ObservableObject {

    struct DigestData {
        let summaryTitle: String
        let summaryBody: String
        let highlights: [String]
        let prayerUpdates: [String]
        let upcomingEvents: [String]
        let generatedAt: Date
        let documentId: String
    }

    @Published var digest: DigestData?
    @Published var isLoading: Bool = false
    @Published var isGenerating: Bool = false
    @Published var error: String?

    private let db = Firestore.firestore()

    // MARK: Load latest digest for current user

    func load(covenantId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            let snap = try await db
                .collection("covenants").document(covenantId)
                .collection("digests")
                .whereField("userId", isEqualTo: uid)
                .order(by: "generatedAt", descending: true)
                .limit(to: 1)
                .getDocuments()

            guard let doc = snap.documents.first else {
                digest = nil
                return
            }

            let data = doc.data()
            let generatedAt = (data["generatedAt"] as? Timestamp)?.dateValue() ?? Date()

            digest = DigestData(
                summaryTitle: data["summaryTitle"] as? String ?? "Today's Digest",
                summaryBody: data["summaryBody"] as? String ?? "",
                highlights: data["highlights"] as? [String] ?? [],
                prayerUpdates: data["prayerUpdates"] as? [String] ?? [],
                upcomingEvents: data["upcomingEvents"] as? [String] ?? [],
                generatedAt: generatedAt,
                documentId: doc.documentID
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Generate new digest via CovenantService

    func generateDigest(covenantId: String) async {
        isGenerating = true
        error = nil
        do {
            let since = Calendar.current.startOfDay(for: Date())
            let summary = try await CovenantService.shared.generateCatchUp(
                covenantId: covenantId,
                roomId: nil,
                since: since
            )

            // Persist generated digest to Firestore
            guard let uid = Auth.auth().currentUser?.uid else { return }
            let docRef = db
                .collection("covenants").document(covenantId)
                .collection("digests")
                .document()

            let payload: [String: Any] = [
                "userId": uid,
                "summaryTitle": "Today's Digest",
                "summaryBody": summary.summary,
                "highlights": summary.decisions,
                "prayerUpdates": summary.prayerUpdates,
                "upcomingEvents": summary.upcomingEvents,
                "generatedAt": Timestamp(date: Date())
            ]
            try await docRef.setData(payload)

            digest = DigestData(
                summaryTitle: "Today's Digest",
                summaryBody: summary.summary,
                highlights: summary.decisions,
                prayerUpdates: summary.prayerUpdates,
                upcomingEvents: summary.upcomingEvents,
                generatedAt: Date(),
                documentId: docRef.documentID
            )
        } catch {
            self.error = error.localizedDescription
        }
        isGenerating = false
    }

    // MARK: Mark digest as read

    func markRead(covenantId: String) async {
        guard let docId = digest?.documentId else { return }
        try? await db
            .collection("covenants").document(covenantId)
            .collection("digests").document(docId)
            .updateData(["readAt": Timestamp(date: Date())])
    }

    // MARK: Load unread rooms

    func loadUnreadRooms(covenantId: String) async -> [CovenantRoom] {
        let rooms = CovenantService.shared.rooms.filter {
            $0.covenantId == covenantId && $0.unreadCount > 0
        }
        return rooms
    }
}

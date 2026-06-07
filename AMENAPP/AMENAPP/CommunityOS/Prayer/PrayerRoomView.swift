// PrayerRoomView.swift
// AMEN App — Community OS / Prayer OS (A7)
//
// Main prayer room view. Shows a prayer request with privacy badge, partner row,
// update feed, and primary "Pray for this" action.
//
// Integration:
//   - PrayerRoomRealtimeCoordinator (AIIntelligence/) for live translation + realtime session
//   - ActionThread.prayerCircle for care workflows (read-only reference; do not spawn from here)
//   - PrayerPrivacySelector — shown in edit flow (not inline; keep room view clean)
//
// Feature flag gate: AMENFeatureFlags.shared.communityOSPrayerOSEnabled
//
// Design contract (C3):
//   - system colors only, white cards, AmenShadow.card spec
//   - 28pt continuous corner radius on all cards
//   - Private is the visual default and most prominent privacy level

import SwiftUI
import FirebaseAuth
import UIKit

// MARK: - PrayerUpdateCard (stub)

/// Stub card for a prayer update or testimony in the updates feed.
/// Replace with a full Firestore-backed model once PrayerUpdateService is built.
private struct PrayerUpdateCard: View {
    let updateType: PrayerType
    let updateBody: String
    let createdAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: updateType.systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                Text(updateType.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(timeLabel)
                    .font(.caption2)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }

            Text(updateBody)
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(updateType.displayName): \(updateBody)")
    }

    private var timeLabel: String {
        let diff = Date().timeIntervalSince(createdAt)
        if diff < 60      { return "just now" }
        if diff < 3600    { return "\(Int(diff / 60))m ago" }
        if diff < 86400   { return "\(Int(diff / 3600))h ago" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: createdAt)
    }
}

// MARK: - PrayerRoomView

/// Main prayer room view displaying a prayer request and its community of intercessors.
/// Gated by `AMENFeatureFlags.shared.communityOSPrayerOSEnabled`.
struct PrayerRoomView: View {

    let prayerId: String

    @State private var prayer: PrayerRequest?
    @StateObject private var coordinator = PrayerRoomRealtimeCoordinator()
    @State private var isExpanded = false
    @State private var showUpdateSheet = false
    @State private var showMarkAnsweredConfirm = false
    @State private var showInviteSheet = false
    @State private var updateSheetType: PrayerType = .update
    @State private var stubUpdates: [PrayerUpdateStub] = []
    @State private var isPraying = false
    @State private var hasPrayed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        guard AMENFeatureFlags.shared.communityOSPrayerOSEnabled else {
            return AnyView(featureUnavailableView)
        }
        return AnyView(mainContent)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        if let prayer = prayer {
                            provenanceBanner(for: prayer)
                            prayerHeroCard(prayer)
                            privacyBadge(prayer)
                            PrayerPartnerRow(
                                partnerIds: prayer.partnerIds,
                                maxVisible: 5,
                                onInvitePartner: { showInviteSheet = true }
                            )
                            .padding(.horizontal, 16)

                            prayForThisButton(prayer)
                            updatesSection
                            secondaryActions(prayer)
                        } else {
                            loadingState
                        }

                        Color.clear.frame(height: 40)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Prayer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Close prayer room")
                }
            }
        }
        .sheet(isPresented: $showUpdateSheet) {
            if let prayer = prayer {
                PrayerUpdateSheet(
                    prayerId: prayer.id,
                    updateType: updateSheetType,
                    isPresented: $showUpdateSheet,
                    onSubmit: { text in
                        stubUpdates.insert(
                            PrayerUpdateStub(type: updateSheetType, body: text, createdAt: Date()),
                            at: 0
                        )
                    }
                )
            }
        }
        .confirmationDialog(
            "Mark as Answered",
            isPresented: $showMarkAnsweredConfirm,
            titleVisibility: .visible
        ) {
            Button("Yes, this prayer was answered") {
                if prayer != nil {
                    prayer?.status = .answered
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will mark the prayer as answered and notify your prayer partners.")
        }
        .sheet(isPresented: $showInviteSheet) {
            if let prayer = prayer {
                let url = URL(string: "https://amenapp.com/prayer/\(prayer.id)") ?? URL(string: "https://amenapp.com")!
                VStack(spacing: 20) {
                    Text("Invite a Prayer Partner")
                        .font(.headline)
                        .padding(.top, 20)
                    Text("Share this prayer so others can join you in intercession.")
                        .font(.callout)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    ShareLink(
                        item: url,
                        subject: Text("Join me in prayer"),
                        message: Text("I'd love for you to pray with me: \(prayer.title)")
                    ) {
                        Label("Share prayer invite", systemImage: "square.and.arrow.up")
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(Color.accentColor))
                            .padding(.horizontal, 24)
                    }
                    Button("Close") { showInviteSheet = false }
                        .font(.callout)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .padding(.bottom, 20)
                }
                .presentationDetents([.height(260)])
                .accessibilityElement(children: .contain)
            }
        }
        .task { await loadPrayer() }
    }

    // MARK: - Provenance Banner

    @ViewBuilder
    private func provenanceBanner(for prayer: PrayerRequest) -> some View {
        if let prov = prayer.provenance {
            DiscussionProvenanceBanner(
                provenance: prov,
                onTap: nil
            )
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Prayer Hero Card

    private func prayerHeroCard(_ prayer: PrayerRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prayer.title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color(uiColor: .label))

            Group {
                if isExpanded || prayer.body.count <= 200 {
                    Text(prayer.body)
                        .font(.body)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: isExpanded)
                } else {
                    Text(prayer.body)
                        .font(.body)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineSpacing(3)
                        .lineLimit(3)

                    Button {
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
                            isExpanded = true
                        }
                    } label: {
                        Text("Read more")
                            .font(.callout)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Expand full prayer text")
                }
            }

            // Status badge when not active
            if prayer.status != .active {
                HStack(spacing: 6) {
                    Image(systemName: prayer.status.systemImage)
                        .font(.system(size: 11))
                    Text(prayer.status.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(prayer.isAnswered ? Color.accentColor : Color(uiColor: .secondaryLabel))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(
                            prayer.isAnswered
                                ? Color.accentColor.opacity(0.10)
                                : Color(uiColor: .secondarySystemFill)
                        )
                )
                .accessibilityLabel("Prayer status: \(prayer.status.displayName)")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.07), radius: 24, x: 0, y: 5)
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Privacy Badge Chip

    private func privacyBadge(_ prayer: PrayerRequest) -> some View {
        HStack(spacing: 5) {
            Image(systemName: prayer.privacyLevel.systemImage)
                .font(.system(size: 11))
            Text(prayer.privacyLevel.displayName)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(Color(uiColor: .secondaryLabel))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(uiColor: .secondarySystemFill))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .accessibilityLabel("Privacy: \(prayer.privacyLevel.displayName). \(prayer.privacyLevel.description)")
    }

    // MARK: - Pray for This Button

    private func prayForThisButton(_ prayer: PrayerRequest) -> some View {
        Button {
            Task { await prayForThis(prayer) }
        } label: {
            Group {
                if hasPrayed {
                    HStack(spacing: 8) {
                        Image(systemName: "hands.sparkles.fill")
                            .font(.system(size: 16, weight: .regular))
                        Text("Praying")
                            .font(.callout)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.7))
                    )
                } else if isPraying {
                    ProgressView()
                        .tint(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            Capsule()
                                .fill(Color.accentColor)
                        )
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "hands.sparkles")
                            .font(.system(size: 16, weight: .regular))
                        Text("Pray for this")
                            .font(.callout)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .disabled(prayer.softDeleted || prayer.status == .closed || hasPrayed || isPraying)
        .accessibilityLabel(hasPrayed ? "You are praying for this request" : "Pray for this prayer request")
    }

    // MARK: - Pray for This Action

    private func prayForThis(_ prayer: PrayerRequest) async {
        guard !hasPrayed && !isPraying else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isPraying = true
        do {
            try await AmenEdgeService().createEdge(
                fromRef: "users/\(uid)",
                fromType: .user,
                toRef: "prayerRequests/\(prayer.id)",
                toType: .prayer,
                edgeType: .praysFor,
                createdBy: uid
            )
        } catch {
            // Non-fatal: edge creation failure does not block the local UI confirmation
        }
        hasPrayed = true
        isPraying = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Updates Section

    @ViewBuilder
    private var updatesSection: some View {
        if !stubUpdates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Updates")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.horizontal, 16)
                    .accessibilityAddTraits(.isHeader)

                ForEach(stubUpdates) { stub in
                    PrayerUpdateCard(
                        updateType: stub.type,
                        updateBody: stub.body,
                        createdAt: stub.createdAt
                    )
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Secondary Actions

    private func secondaryActions(_ prayer: PrayerRequest) -> some View {
        HStack(spacing: 10) {
            Button {
                updateSheetType = .update
                showUpdateSheet = true
            } label: {
                Label("Add Update", systemImage: "arrow.clockwise")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .disabled(prayer.softDeleted || prayer.status != .active)
            .accessibilityLabel("Add an update to this prayer")

            Button {
                if prayer.status == .active {
                    showMarkAnsweredConfirm = true
                } else {
                    updateSheetType = .testimony
                    showUpdateSheet = true
                }
            } label: {
                Label(
                    prayer.status == .active ? "Mark Answered" : "Share Testimony",
                    systemImage: prayer.status == .active ? "checkmark.circle" : "star"
                )
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemFill))
                )
            }
            .buttonStyle(.plain)
            .disabled(prayer.softDeleted || prayer.status == .closed)
            .accessibilityLabel(prayer.status == .active ? "Mark this prayer as answered" : "Share a testimony")
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color.accentColor)
            Text("Loading prayer…")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Loading prayer room")
    }

    // MARK: - Feature Unavailable

    private var featureUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hands.sparkles")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
            Text("Prayer rooms are coming soon.")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prayer rooms feature is not yet available.")
    }

    // MARK: - Data Loading

    private func loadPrayer() async {
        // Stub: load from Firestore /prayers/{prayerId} once PrayerService is built.
        // For now, populate with a placeholder so the layout renders correctly.
        prayer = PrayerRequest(
            id: prayerId,
            authorId: "uid_author",
            title: "For healing and peace",
            body: "Praying for strength and peace through this difficult season. Trust in the Lord with all your heart and lean not on your own understanding. In all your ways acknowledge Him and He will make your paths straight.",
            prayerType: .request,
            privacyLevel: .private,
            status: .active,
            partnerIds: [],
            reminderEnabled: false,
            provenance: nil,
            createdAt: Date(),
            softDeleted: false
        )
    }
}

// MARK: - Stub Model (internal to PrayerRoomView)

private struct PrayerUpdateStub: Identifiable {
    let id = UUID()
    let type: PrayerType
    let body: String
    let createdAt: Date
}

// MARK: - Preview

#if DEBUG
#Preview {
    PrayerRoomView(prayerId: "preview_prayer_001")
}
#endif

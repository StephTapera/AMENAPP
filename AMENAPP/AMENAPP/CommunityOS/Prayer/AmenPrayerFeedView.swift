// AmenPrayerFeedView.swift
// AMEN App — CommunityOS / Prayer OS (Phase 2 — Agent A7)
//
// Feed view for prayer requests filtered by PrayerContext.
//
// Anti-engagement invariants enforced here:
//   - prayerCount is NEVER displayed to any user.
//   - No "X people prayed" counter visible in any card.
//   - No streak comparisons or leaderboards.
//
// Design contract (C3):
//   - White card background, systemGroupedBackground behind list
//   - 28pt continuous corner radius on all cards
//   - System colors only
//   - 44pt minimum touch targets on all interactive elements
//   - Answered prayers show a subtle green checkmark badge (no count shown)
//
// Feature flag gate: AMENFeatureFlags.shared.communityOSPrayerOSEnabled

import FirebaseAuth
import SwiftUI

// MARK: - AmenPrayerFeedView

/// Prayer request feed for a given PrayerContext.
/// Shows prayer cards, allows filtering, and surfaces a "Request Prayer" compose entry.
struct AmenPrayerFeedView: View {

    var context: PrayerContext = .public

    @StateObject private var service = AmenPrayerService()
    @State private var showCompose = false
    @State private var showCreateRoom = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        guard AMENFeatureFlags.shared.communityOSPrayerOSEnabled else {
            return AnyView(featureUnavailableView)
        }
        return AnyView(contentView)
    }

    // MARK: - Content

    private var contentView: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.prayerRequests.isEmpty {
                    loadingView
                } else if service.prayerRequests.isEmpty {
                    emptyStateView
                } else {
                    feedList
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Prayer")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCompose = true
                    } label: {
                        Label("Request Prayer", systemImage: "plus")
                    }
                    .accessibilityLabel("Request prayer")
                }
            }
        }
        .sheet(isPresented: $showCompose) {
            AmenPrayerComposeView(
                service: service,
                context: context,
                isPresented: $showCompose
            )
        }
        .task { await loadFeed() }
        .refreshable { await loadFeed() }
    }

    // MARK: - Feed List

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(service.prayerRequests) { prayer in
                    AmenPrayerCard(prayer: prayer, service: service)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color.accentColor)
            Text("Loading prayers…")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading prayer requests")
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hands.sparkles")
                .font(.systemScaled(44, weight: .ultraLight))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)

            Text("No prayers yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color(uiColor: .label))

            Text("Share a prayer request and invite others to pray with you.")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showCompose = true
            } label: {
                Text("Request Prayer")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(
                        Capsule().fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Request prayer — opens the compose screen")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Feature Unavailable

    private var featureUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hands.sparkles")
                .font(.systemScaled(44, weight: .ultraLight))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
            Text("Prayer is off")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prayer feature is not yet available.")
    }

    // MARK: - Load

    private func loadFeed() async {
        do {
            try await service.loadPrayerRequests(context: context)
        } catch {
            service.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - AmenPrayerCard

/// Individual prayer request card shown in the feed.
///
/// Anti-engagement rules:
///   - prayerCount is NEVER displayed. Not even to the request owner in this view.
///   - No "X people prayed" shown publicly.
///   - Answered prayers get a subtle checkmark badge (no count).
struct AmenPrayerCard: View {

    let prayer: AmenPrayerRequest
    let service: AmenPrayerService

    @State private var hasPrayed = false
    @State private var isPraying = false
    @State private var showReportSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Current user ID — replace with Auth injection when wired into the full app context.
    private var currentUserId: String {
        // Production code would inject Auth.auth().currentUser?.uid here.
        return "current_user"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author row
            authorRow

            // Title
            Text(prayer.title)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Body (truncated)
            Text(prayer.body)
                .font(.footnote)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .lineLimit(3)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            // Tags row
            if !prayer.tags.isEmpty {
                tagsRow
            }

            Divider()
                .padding(.vertical, 2)

            // Action row
            bottomActionRow
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 4)
        )
        .overlay(answeredBadge, alignment: .topTrailing)
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button(role: .destructive) {
                showReportSheet = true
            } label: {
                Label("Report Prayer", systemImage: "flag")
            }
            // Block author only for non-anonymous requests where the author is identifiable.
            if !prayer.isAnonymous && !prayer.createdBy.isEmpty {
                Button {
                    Task {
                        try? await BlockService.shared.blockUser(userId: prayer.createdBy)
                    }
                } label: {
                    Label("Block User", systemImage: "nosign")
                }
            }
        }
        .reportContentSheet(
            isPresented: $showReportSheet,
            targetType: .prayerRequest,
            targetId: prayer.id
        )
    }

    // MARK: - Author Row

    private var authorRow: some View {
        HStack(spacing: 8) {
            // Anonymous or real avatar placeholder
            ZStack {
                Circle()
                    .fill(Color(uiColor: .secondarySystemFill))
                    .frame(width: 32, height: 32)

                Image(systemName: prayer.isAnonymous ? "person.fill.questionmark" : "person.fill")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(prayer.displayAuthorName.isEmpty ? "Anonymous" : prayer.displayAuthorName)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(uiColor: .label))

                Text(timeAgo(prayer.createdAt))
                    .font(.caption2)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }

            Spacer()

            // Privacy badge
            HStack(spacing: 4) {
                Image(systemName: prayer.privacyLevel.systemImage)
                    .font(.systemScaled(10))
                Text(prayer.privacyLevel.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundStyle(Color(uiColor: .tertiaryLabel))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color(uiColor: .secondarySystemFill))
            )
            .accessibilityLabel("Privacy: \(prayer.privacyLevel.displayName)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Prayer by \(prayer.displayAuthorName.isEmpty ? "Anonymous" : prayer.displayAuthorName), \(timeAgo(prayer.createdAt)). Privacy: \(prayer.privacyLevel.displayName)"
        )
    }

    // MARK: - Tags Row

    private var tagsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(prayer.tags.prefix(5), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.accentColor.opacity(0.08))
                        )
                }
            }
        }
        .accessibilityLabel("Tags: \(prayer.tags.prefix(5).joined(separator: ", "))")
    }

    // MARK: - Bottom Action Row

    private var bottomActionRow: some View {
        HStack(spacing: 0) {
            // "Pray with them" button — primary action.
            // NOTE: prayerCount is intentionally NOT shown here (anti-engagement rule).
            Button {
                guard !hasPrayed, !isPraying else { return }
                Task { await prayForThis() }
            } label: {
                HStack(spacing: 6) {
                    if #available(iOS 18.0, *) {
                        Image(systemName: hasPrayed ? "hands.sparkles.fill" : "hands.sparkles")
                            .font(.systemScaled(14))
                            .symbolEffect(
                                .bounce,
                                options: .nonRepeating,
                                isActive: hasPrayed && !reduceMotion
                            )
                    } else {
                        Image(systemName: hasPrayed ? "hands.sparkles.fill" : "hands.sparkles")
                            .font(.systemScaled(14))
                    }
                    Text(hasPrayed ? "Praying" : "Pray with them")
                        .font(.footnote)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(hasPrayed ? Color.accentColor : Color(uiColor: .secondaryLabel))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            hasPrayed
                                ? Color.accentColor.opacity(0.10)
                                : Color(uiColor: .secondarySystemFill)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(hasPrayed || isPraying)
            .frame(minHeight: 44)
            .accessibilityLabel(hasPrayed ? "You are praying for this request" : "Pray with them")

            Spacer()

            // Follow-up badge if there are recent updates
            if !prayer.followUps.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.systemScaled(10))
                    Text("Updated")
                        .font(.caption2)
                }
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityLabel("This prayer has updates")
            }
        }
    }

    // MARK: - Answered Badge

    @ViewBuilder
    private var answeredBadge: some View {
        if prayer.isAnswered {
            Image(systemName: "checkmark.circle.fill")
                .font(.systemScaled(18, weight: .semibold))
                .foregroundStyle(Color.green)
                .padding(10)
                .accessibilityLabel("This prayer was answered")
        }
    }

    // MARK: - Actions

    private func prayForThis() async {
        guard !hasPrayed else { return }
        isPraying = true
        defer { isPraying = false }
        do {
            try await service.prayForRequest(prayer.id, userId: currentUserId)
            withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7)) {
                hasPrayed = true
            }
        } catch {
            // Silently fail; do not show error to avoid discouraging prayer.
            // Log for diagnostics only.
            print("[AmenPrayerCard] prayForRequest failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func timeAgo(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60      { return "just now" }
        if diff < 3600    { return "\(Int(diff / 60))m ago" }
        if diff < 86400   { return "\(Int(diff / 3600))h ago" }
        if diff < 604800  { return "\(Int(diff / 86400))d ago" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}

// MARK: - AmenPrayerComposeView

/// Prayer compose sheet presented from the feed's "Request Prayer" toolbar button.
private struct AmenPrayerComposeView: View {

    let service: AmenPrayerService
    let context: PrayerContext
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var prayerBody  = ""
    @State private var selectedPrivacy: PrayerPrivacyLevel = .private
    @State private var isAnonymous = false
    @State private var isSubmitting = false

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prayerBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var bodyView: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(uiColor: .quaternaryLabel))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .accessibilityHidden(true)

            Text("Request Prayer")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color(uiColor: .label))
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))

                        TextField("What are you praying for?", text: $title)
                            .font(.body)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemFill))
                            )
                    }

                    // Body field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Share your prayer")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))

                        ZStack(alignment: .topLeading) {
                            if prayerBody.isEmpty {
                                Text("Write your prayer request here…")
                                    .font(.body)
                                    .foregroundStyle(Color(uiColor: .placeholderText))
                                    .padding(14)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $prayerBody)
                                .font(.body)
                                .frame(minHeight: 100)
                                .padding(10)
                                .scrollContentBackground(.hidden)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemFill))
                        )
                    }

                    // Privacy picker
                    AmenPrayerPrivacyPickerView(selection: $selectedPrivacy)

                    // Anonymous toggle
                    Toggle(isOn: $isAnonymous) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Post anonymously")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(Color(uiColor: .label))
                            Text("Your name will not be shown to others.")
                                .font(.caption)
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                    }
                    .tint(Color.accentColor)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            // Submit
            VStack(spacing: 10) {
                Button {
                    guard canSubmit, !isSubmitting else { return }
                    Task { await submit() }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        } else {
                            Text("Share Prayer Request")
                                .font(.callout)
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Capsule()
                            .fill(canSubmit ? Color.accentColor : Color(uiColor: .secondarySystemFill))
                    )
                    .foregroundStyle(canSubmit ? Color.white : Color(uiColor: .secondaryLabel))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit || isSubmitting)
                .padding(.horizontal, 20)
                .accessibilityLabel("Share prayer request")

                Button {
                    isPresented = false
                } label: {
                    Text("Cancel")
                        .font(.callout)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .accessibilityLabel("Cancel")
            }
            .padding(.bottom, 30)
        }
        .background(Color(.systemBackground))
    }

    var body: some View {
        bodyView
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let churchRef: String?
        let spaceRef: String?
        switch context {
        case .church(let ref): churchRef = ref; spaceRef = nil
        case .space(let ref):  spaceRef = ref;  churchRef = nil
        default:               churchRef = nil;  spaceRef = nil
        }

        do {
            guard let uid = Auth.auth().currentUser?.uid else {
                throw AmenPrayerComposeError.notAuthenticated
            }

            _ = try await service.createPrayerRequest(
                title:      title.trimmingCharacters(in: .whitespacesAndNewlines),
                body:       prayerBody.trimmingCharacters(in: .whitespacesAndNewlines),
                privacy:    selectedPrivacy,
                isAnonymous: isAnonymous,
                churchRef:  churchRef,
                spaceRef:   spaceRef,
                tags:       [],
                creatorId:  uid,
                provenance: nil
            )
            isPresented = false
            try await service.loadPrayerRequests(context: context)
        } catch {
            print("[AmenPrayerComposeView] submit failed: \(error.localizedDescription)")
        }
    }
}

private enum AmenPrayerComposeError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        "Sign in before requesting prayer."
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Public feed") {
    AmenPrayerFeedView(context: .public)
}

#Preview("Personal feed") {
    AmenPrayerFeedView(context: .personal("uid_preview"))
}
#endif

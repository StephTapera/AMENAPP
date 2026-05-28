// AmenMediaAIMetadataReviewSheet.swift
// AMENAPP
//
// Creator-only sheet for reviewing and approving/rejecting AI-generated media metadata.
// Gated by AMENFeatureFlags.shared.mediaApprovalFlowEnabled.
// Never shows to public viewers — only to the post creator.

import FirebaseAuth
import FirebaseFunctions
import SwiftUI

// MARK: - Models

struct AIDraftItem: Identifiable {
    let id: String
    let draftType: String   // "captions", "keyMoments", "summary", "explanation"
    let previewText: String
    var status: DraftStatus

    enum DraftStatus {
        case pending, approving, rejecting, approved, rejected, error
    }
}

// MARK: - AmenMediaAIMetadataReviewSheet

struct AmenMediaAIMetadataReviewSheet: View {

    // MARK: Inputs

    let postId: String
    let mediaId: String
    var drafts: [AIDraftItem]
    var onDismiss: (() -> Void)? = nil

    // MARK: State

    @State private var items: [AIDraftItem]
    @State private var rejectingItemId: String?
    @State private var rejectReason: String = ""
    @State private var toastMessage: String?
    @State private var toastIsError: Bool = false
    @State private var showToast: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Init

    init(postId: String, mediaId: String, drafts: [AIDraftItem], onDismiss: (() -> Void)? = nil) {
        self.postId = postId
        self.mediaId = mediaId
        self.drafts = drafts
        self.onDismiss = onDismiss
        self._items = State(initialValue: drafts)
    }

    // MARK: Feature gate

    var body: some View {
        guard AMENFeatureFlags.shared.mediaApprovalFlowEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(sheetContent)
    }

    // MARK: Main sheet

    private var sheetContent: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        aiReviewBanner
                        featureFlagGuard
                        draftList
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 36)
                }

                if showToast {
                    toastBanner
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .zIndex(10)
                        .padding(.bottom, 20)
                        .padding(.horizontal, 20)
                }
            }
            .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.80), value: showToast)
            .navigationTitle("AI Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss?()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel("Done reviewing AI metadata")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - AI review banner

    private var aiReviewBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("AI-generated — requires your review")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("These captions, key moments, and summaries were generated automatically. Nothing is published until you approve each item.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bannerBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.18), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI-generated content requires your review. Nothing is published until you approve.")
    }

    // MARK: - Feature flag guard (secondary flag)

    @ViewBuilder
    private var featureFlagGuard: some View {
        if !AMENFeatureFlags.shared.mediaAIDraftMetadataEnabled {
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("AI metadata drafts are not yet enabled for your account.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Draft list

    @ViewBuilder
    private var draftList: some View {
        let pendingItems = items.filter { $0.status != .approved && $0.status != .rejected }
        let settledItems = items.filter { $0.status == .approved || $0.status == .rejected }

        if items.isEmpty {
            emptyState
        } else {
            if !pendingItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pending review")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(pendingItems) { item in
                        draftCard(item: item)
                    }
                }
            }

            if !settledItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reviewed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(settledItems) { item in
                        draftCard(item: item)
                    }
                }
            }
        }
    }

    // MARK: - Draft card

    @ViewBuilder
    private func draftCard(item: AIDraftItem) -> some View {
        let isRejectExpanded = rejectingItemId == item.id

        VStack(alignment: .leading, spacing: 14) {
            // Header row: type badge + title
            HStack(alignment: .center, spacing: 10) {
                typeBadge(for: item.draftType)
                Text(draftTitle(for: item.draftType))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                statusIcon(for: item.status)
            }

            // Preview text
            Text(item.previewText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(isRejectExpanded ? 3 : 5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel("Draft preview: \(item.previewText.prefix(300))\(item.previewText.count > 300 ? "…" : "")")

            // Reject reason input (expanded inline)
            if isRejectExpanded {
                rejectReasonField(item: item)
            }

            // Action row (only for pending/error states)
            if item.status == .pending || item.status == .error {
                actionRow(item: item, isRejectExpanded: isRejectExpanded)
            }

            // Error label
            if item.status == .error {
                Text("An error occurred. Please try again.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error: An error occurred. Please try again.")
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(borderColor(for: item.status), lineWidth: 0.75)
        )
        .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.82), value: isRejectExpanded)
        .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.82), value: item.status)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Reject reason field

    @ViewBuilder
    private func rejectReasonField(item: AIDraftItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reason for rejection (optional)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("e.g. Inaccurate, off-brand, not needed", text: $rejectReason, axis: .vertical)
                .font(.callout)
                .padding(10)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.75)
                )
                .lineLimit(2...4)
                .accessibilityLabel("Rejection reason text field")
                .accessibilityHint("Optional. Describe why you are rejecting this draft.")
        }
    }

    // MARK: - Action row (Liquid Glass)

    @ViewBuilder
    private func actionRow(item: AIDraftItem, isRejectExpanded: Bool) -> some View {
        HStack(spacing: 10) {
            // Approve button
            Button {
                Task { await approve(item: item) }
            } label: {
                approveButtonLabel(item: item)
            }
            .disabled(item.status == .approving || item.status == .rejecting)
            .frame(minHeight: 44)
            .accessibilityLabel("Approve this \(draftTitle(for: item.draftType)) draft")
            .accessibilityHint("Publishes this AI-generated draft as visible to your audience.")

            // Reject / Cancel-reject button
            if isRejectExpanded {
                Button {
                    Task { await reject(item: item) }
                } label: {
                    rejectConfirmLabel(item: item)
                }
                .disabled(item.status == .approving || item.status == .rejecting)
                .frame(minHeight: 44)
                .accessibilityLabel("Confirm rejection of this \(draftTitle(for: item.draftType)) draft")

                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.26, dampingFraction: 0.80)) {
                        rejectingItemId = nil
                        rejectReason = ""
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemFill), in: Circle())
                }
                .accessibilityLabel("Cancel rejection")
            } else {
                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.26, dampingFraction: 0.80)) {
                        rejectingItemId = item.id
                        rejectReason = ""
                    }
                } label: {
                    Label("Reject", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(glassRejectBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6)
                        )
                }
                .frame(minHeight: 44)
                .disabled(item.status == .approving || item.status == .rejecting)
                .accessibilityLabel("Reject this \(draftTitle(for: item.draftType)) draft")
                .accessibilityHint("Marks this draft as rejected. It will not be published.")
            }
        }
    }

    // MARK: - Button labels

    @ViewBuilder
    private func approveButtonLabel(item: AIDraftItem) -> some View {
        if item.status == .approving {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white)
                Text("Approving…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.70), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Label("Approve", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.6)
                )
        }
    }

    @ViewBuilder
    private func rejectConfirmLabel(item: AIDraftItem) -> some View {
        if item.status == .rejecting {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Rejecting…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Label("Confirm Reject", systemImage: "xmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.18), lineWidth: 0.6)
                )
        }
    }

    // MARK: - Type badge

    private func typeBadge(for draftType: String) -> some View {
        Text(badgeLabel(for: draftType))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(badgeForeground(for: draftType))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeBackground(for: draftType), in: Capsule(style: .continuous))
            .accessibilityLabel("\(badgeLabel(for: draftType)) draft type")
    }

    private func badgeLabel(for draftType: String) -> String {
        switch draftType {
        case "captions":    return "Caption"
        case "keyMoments":  return "Key Moment"
        case "summary":     return "Summary"
        case "explanation": return "Explanation"
        default:            return draftType.capitalized
        }
    }

    private func badgeBackground(for draftType: String) -> Color {
        switch draftType {
        case "captions":    return Color.blue.opacity(0.14)
        case "keyMoments":  return Color.purple.opacity(0.14)
        case "summary":     return Color.green.opacity(0.14)
        case "explanation": return Color.orange.opacity(0.14)
        default:            return Color(.secondarySystemFill)
        }
    }

    private func badgeForeground(for draftType: String) -> Color {
        switch draftType {
        case "captions":    return .blue
        case "keyMoments":  return .purple
        case "summary":     return .green
        case "explanation": return .orange
        default:            return .secondary
        }
    }

    // MARK: - Status icon

    @ViewBuilder
    private func statusIcon(for status: AIDraftItem.DraftStatus) -> some View {
        switch status {
        case .pending, .approving, .rejecting:
            EmptyView()
        case .approved:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.green)
                .accessibilityLabel("Approved")
        case .rejected:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Rejected")
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.red)
                .accessibilityLabel("Error")
        }
    }

    // MARK: - Border color

    private func borderColor(for status: AIDraftItem.DraftStatus) -> Color {
        switch status {
        case .approved: return Color.green.opacity(0.30)
        case .rejected: return Color(.separator).opacity(0.40)
        case .error:    return Color.red.opacity(0.30)
        default:        return Color.black.opacity(0.07)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No pending AI drafts")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("All AI-generated metadata has been reviewed, or none has been generated yet for this post.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 12)
    }

    // MARK: - Toast banner

    private var toastBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: toastIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toastIsError ? .red : .green)
                .accessibilityHidden(true)
            Text(toastMessage ?? "")
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(toastBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.09), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toastMessage ?? "")
    }

    // MARK: - Backgrounds

    private var bannerBackground: AnyShapeStyle {
        AnyShapeStyle(Color.blue.opacity(0.06))
    }

    private var glassRejectBackground: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(.secondarySystemFill))
            : AnyShapeStyle(.ultraThinMaterial)
    }

    private var toastBackground: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(.systemBackground))
            : AnyShapeStyle(.regularMaterial)
    }

    // MARK: - Helpers

    private func draftTitle(for draftType: String) -> String {
        switch draftType {
        case "captions":    return "Caption"
        case "keyMoments":  return "Key Moment"
        case "summary":     return "Summary"
        case "explanation": return "Explanation"
        default:            return draftType.capitalized
        }
    }

    private func itemIndex(for item: AIDraftItem) -> Int? {
        items.firstIndex(where: { $0.id == item.id })
    }

    private func setStatus(_ status: AIDraftItem.DraftStatus, for item: AIDraftItem) {
        guard let idx = itemIndex(for: item) else { return }
        items[idx].status = status
    }

    // MARK: - Firebase callable: Approve

    private func approve(item: AIDraftItem) async {
        guard let idx = itemIndex(for: item) else { return }
        items[idx].status = .approving

        let functions = Functions.functions()
        do {
            _ = try await functions.httpsCallable("approveMediaMetadata").call([
                "postId":    postId,
                "mediaId":   mediaId,
                "draftType": item.draftType,
                "draftId":   item.id
            ] as [String: Any])
            items[idx].status = .approved
            AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "ai_metadata_approved"))
            presentToast("Draft approved and published.", isError: false)
        } catch {
            items[idx].status = .error
            presentToast("Approval failed. Please try again.", isError: true)
        }
    }

    // MARK: - Firebase callable: Reject

    private func reject(item: AIDraftItem) async {
        guard let idx = itemIndex(for: item) else { return }
        items[idx].status = .rejecting

        let functions = Functions.functions()
        var payload: [String: Any] = [
            "postId":    postId,
            "mediaId":   mediaId,
            "draftType": item.draftType,
            "draftId":   item.id
        ]
        let trimmedReason = rejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedReason.isEmpty {
            payload["reason"] = trimmedReason
        }

        do {
            _ = try await functions.httpsCallable("rejectMediaMetadata").call(payload)
            items[idx].status = .rejected
            AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "ai_metadata_rejected"))
            rejectingItemId = nil
            rejectReason = ""
            presentToast("Draft rejected.", isError: false)
        } catch {
            items[idx].status = .error
            presentToast("Rejection failed. Please try again.", isError: true)
        }
    }

    // MARK: - Toast

    private func presentToast(_ message: String, isError: Bool) {
        toastMessage = message
        toastIsError = isError
        withAnimation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.80)) {
            showToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.25)) {
                showToast = false
            }
        }
    }
}

//
//  UserProfileViewMini.swift
//  AMENAPP
//
//  Compact, context-aware profile suggestion card.
//  Used in Discovery, #OpenTable, Prayer, and Testimonies feeds.
//
//  Design: white background · black text · grayscale accents ·
//          restrained Liquid Glass · no visual noise.
//

import SwiftUI

// MARK: - Main View

struct UserProfileViewMini: View {
    @StateObject var vm: UserProfileMiniViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var appeared = false
    @State private var showReportSheet = false
    @State private var followBounce = false

    var body: some View {
        Group {
            if vm.isHidden {
                hiddenState
            } else {
                cardBody
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : (reduceMotion ? 0 : 8))
                    .onAppear {
                        withAnimation(reduceMotion
                            ? .linear(duration: 0.15)
                            : .spring(response: 0.42, dampingFraction: 0.84)) {
                            appeared = true
                        }
                        vm.onAppear()
                    }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = vm.toastMessage {
                toastBanner(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.toastMessage)
        .sheet(isPresented: $showReportSheet) {
            ReportUserView(
                userName: vm.model.displayName,
                userId: vm.model.id
            ) { reason, description in
                Task {
                    let moderationReason: ModerationReportReason
                    switch reason {
                    case .spam:          moderationReason = .spam
                    case .harassment:    moderationReason = .harassment
                    case .inappropriate: moderationReason = .inappropriateContent
                    case .impersonation: moderationReason = .other
                    case .falseInfo:     moderationReason = .falseInformation
                    case .other:         moderationReason = .other
                    }
                    try? await ModerationService.shared.reportUser(
                        userId: vm.model.id,
                        reason: moderationReason,
                        additionalDetails: description.isEmpty ? nil : description
                    )
                }
            }
        }
    }

    // MARK: - Card Body

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.top, 14)
                .padding(.horizontal, 14)

            if !vm.reasons.isEmpty {
                reasonChips
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            if let bio = vm.model.bioShort, !bio.isEmpty {
                bioSection(bio)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }

            // Context panel only shown when engine reports meaningful signal.
            if vm.showContextPanel {
                contextPanel
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            Divider()
                .padding(.top, 12)
                .opacity(0.06)

            metadataRow
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            Divider().opacity(0.06)

            actionRow
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .padding(.bottom, 2)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        // Card body tap opens the full profile.
        // Button taps within the card consume the event first, so this never double-fires.
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { vm.onTapProfile() }
    }

    private var cardBackground: some View {
        Group {
            if reduceTransparency {
                Color.white
            } else {
                ZStack {
                    Color.white.opacity(0.92)
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            avatarButton

            VStack(alignment: .leading, spacing: 2) {
                nameRow
                if let role = vm.model.roleTitle, !role.isEmpty {
                    Text(role)
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("@\(vm.model.username)")
                    .font(.systemScaled(12))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            overflowButton
        }
    }

    private var avatarButton: some View {
        Button(action: vm.onTapProfile) {
            avatarImage
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View \(vm.model.displayName)'s profile")
    }

    private var avatarImage: some View {
        CachedAsyncImage(
            url: vm.model.avatarURL,
            size: CGSize(width: 120, height: 120),
            content: { img in
                img.resizable().scaledToFill()
            },
            placeholder: {
                initialsPlaceholder
            }
        )
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        .overlay(alignment: .bottomTrailing) {
            if let badge = avatarSourceBadge {
                Text(badge)
                    .font(.systemScaled(9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.68)))
                    .offset(x: 4, y: 4)
                    .accessibilityHidden(true)
            }
        }
    }

    private var avatarSourceBadge: String? {
        switch vm.model.suggestionSource {
        case .prayer:      return "Prayer"
        case .testimonies: return "Testimony"
        case .openTable:   return "Table"
        case .findFriends: return "Friend"
        default:           return nil
        }
    }

    private var initialsPlaceholder: some View {
        Circle()
            .fill(Color.black.opacity(0.06))
            .overlay(
                Text(String(vm.model.displayName.prefix(1)).uppercased())
                    .font(.systemScaled(20, weight: .semibold))
                    .foregroundStyle(.secondary)
            )
    }

    private var nameRow: some View {
        HStack(spacing: 4) {
            Text(vm.model.displayName)
                .font(.systemScaled(17, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            ForEach(vm.model.badges.prefix(1)) { badge in
                Image(systemName: badge.icon)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(badge.label)
            }
        }
    }

    private var overflowButton: some View {
        Menu {
            ForEach(vm.smartActions) { action in
                Button(role: action.isDestructive ? .destructive : nil) {
                    handleOverflowAction(action)
                } label: {
                    Label(action.rawValue, systemImage: action.icon)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)   // 44pt minimum tap target
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.04))
                        .frame(width: 32, height: 32)
                )
        }
        .buttonStyle(.plain)
        .onTapGesture { vm.onTapOverflow() }
        .accessibilityLabel("More options for \(vm.model.displayName)")
    }

    // MARK: - Reason Chips

    private var reasonChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(vm.reasons) { reason in
                    MiniReasonChip(reason: reason)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suggested because: \(vm.reasons.map(\.label).joined(separator: ", "))")
    }

    // MARK: - Bio

    private func bioSection(_ bio: String) -> some View {
        Text(bio)
            .font(.systemScaled(13))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Context Panel

    private var contextPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Explanation
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.systemScaled(11))
                    .foregroundStyle(.secondary)
                Text(vm.priorityExplanation)
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Mutual connection preview
            if !vm.model.mutualConnectionPreview.isEmpty {
                mutualPreview
            }

            // Expand/collapse smart actions
            if vm.isExpanded {
                expandedActions
                    .transition(reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .move(edge: .top)))
            }

            Button {
                vm.onTapExpand()
            } label: {
                HStack(spacing: 3) {
                    Text(vm.isExpanded ? "Show less" : "Show more")
                        .font(.systemScaled(12))
                    Image(systemName: "chevron.down")
                        .font(.systemScaled(9, weight: .semibold))
                        .rotationEffect(.degrees(vm.isExpanded ? 180 : 0))
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.isExpanded)
        }
    }

    private var mutualPreview: some View {
        HStack(spacing: -6) {
            ForEach(vm.model.mutualConnectionPreview.prefix(3)) { mutual in
                CachedAsyncImage(
                    url: mutual.avatarURL,
                    size: CGSize(width: 40, height: 40),
                    content: { img in img.resizable().scaledToFill() },
                    placeholder: {
                        Circle()
                            .fill(Color.black.opacity(0.08))
                            .overlay(
                                Text(String(mutual.displayName.prefix(1)).uppercased())
                                    .font(.systemScaled(9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            )
                    }
                )
                .frame(width: 20, height: 20)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .zIndex(Double(vm.model.mutualConnectionPreview.count))
            }

            if let count = vm.model.mutualConnectionCount, count > 0 {
                Text(mutualLabel(count: count))
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vm.model.mutualConnectionCount ?? 0) mutual connections")
    }

    private var expandedActions: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(vm.smartActions.prefix(4)) { action in
                Button {
                    handleOverflowAction(action)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: action.icon)
                            .font(.systemScaled(13))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(action.rawValue)
                            .font(.systemScaled(13))
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: 14) {
            if let followers = vm.model.followerCount {
                metadataItem(
                    value: formatCount(followers),
                    label: "followers",
                    icon: "person.2"
                )
            }
            if let prayers = vm.model.sharedPrayerCount, prayers > 0 {
                metadataItem(
                    value: "\(prayers)",
                    label: prayers == 1 ? "shared prayer" : "shared prayers",
                    icon: "hands.sparkles"
                )
            }
            if let cred = vm.model.credibility, let label = cred.responseLabel {
                Spacer(minLength: 0)
                Text(label)
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.04)))
            }
        }
    }

    private func metadataItem(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.systemScaled(10))
                .foregroundStyle(.secondary)
            Text("\(value) \(label)")
                .font(.systemScaled(11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.04)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: - Action Row

    private var primaryActionIcon: String {
        switch vm.primaryAction {
        case .follow:           return vm.isFollowed ? "checkmark" : "person.badge.plus"
        case .viewProfile:      return "person.crop.circle"
        case .readThread:       return "text.bubble"
        case .joinConversation: return "bubble.left.and.bubble.right"
        case .prayTogether:     return "hands.sparkles"
        case .prayForTopic:     return "hands.sparkles"
        case .viewTestimony:    return "play.circle"
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            // Primary CTA
            primaryCTAButton
                .frame(maxWidth: .infinity)

            // Secondary CTA
            secondaryCTAButton

            // Message shortcut (if different from secondary)
            if vm.secondaryAction != .message, vm.canMessage {
                messageCTAButton
            }
        }
    }

    private var primaryCTAButton: some View {
        Button {
            vm.onTapPrimaryAction()
        } label: {
            ZStack {
                if vm.isFollowLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: primaryActionIcon)
                            .font(.systemScaled(12, weight: .semibold))
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: vm.isFollowed)
                        Text(vm.followButtonLabel)
                            .font(.systemScaled(15, weight: .semibold))
                    }
                }
            }
            .foregroundStyle(vm.isFollowed ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white))
            .frame(height: 44)    // 44pt minimum
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(vm.isFollowed
                          ? Color.black.opacity(0.06)
                          : .black)
            )
        }
        .buttonStyle(MiniPressStyle())
        .disabled(vm.isFollowLoading)
        .scaleEffect(followBounce ? 1.06 : 1.0)
        .animation(.interpolatingSpring(stiffness: 340, damping: 14), value: followBounce)
        .animation(.easeInOut(duration: 0.2), value: vm.isFollowed)
        .onChange(of: vm.isFollowed) { _, _ in
            guard !reduceMotion else { return }
            followBounce = true
            Task {
                try? await Task.sleep(for: .milliseconds(140))
                followBounce = false
            }
        }
        .accessibilityLabel(vm.primaryAction.accessibilityLabel)
    }

    private var secondaryCTAButton: some View {
        Button {
            vm.onTapSecondaryAction()
        } label: {
            Text(vm.secondaryAction.label)
                .font(.systemScaled(13))
                .foregroundStyle(.primary)
                .frame(height: 44)    // 44pt minimum
                .padding(.horizontal, 14)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(MiniPressStyle())
        .accessibilityLabel(vm.secondaryAction.label)
    }

    private var messageCTAButton: some View {
        Button {
            vm.onTapMessage()
        } label: {
            Image(systemName: "bubble.left")
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)    // 44x44 minimum
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(MiniPressStyle())
        .accessibilityLabel("Send message to \(vm.model.displayName)")
    }

    // MARK: - Hidden State

    private var hiddenState: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .font(.systemScaled(14))
                .foregroundStyle(.tertiary)
            Text("Suggestion hidden")
                .font(.systemScaled(13))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Button("Undo") {
                vm.undoHide()
            }
            .font(.systemScaled(13, weight: .medium))
            .foregroundStyle(.primary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }

    // MARK: - Toast

    private func toastBanner(_ message: String) -> some View {
        Text(message)
            .font(.systemScaled(13))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(Color.black.opacity(0.82))
            )
            .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    }

    // MARK: - Overflow Routing

    private func handleOverflowAction(_ action: UserMiniOverflowAction) {
        switch action {
        case .viewProfile:    vm.onTapProfile()
        case .saveForLater:   vm.onTapSaveForLater()
        case .hideSuggestion: vm.onTapHideSuggestion()
        case .seeSimilar:     vm.onTapSeeSimilar()
        case .report:
            vm.onTapReport()
            showReportSheet = true
        case .shareProfile:
            vm.onTapShare()
            ShareRouter.presentProfile(
                id: vm.model.id,
                displayName: vm.model.displayName,
                username: vm.model.username,
                bio: vm.model.bioShort,
                imageURL: vm.model.avatarURL?.absoluteString,
                sourceSurface: "user_mini_\(vm.model.suggestionSource.rawValue.lowercased())"
            )
        }
    }

    // MARK: - Helpers

    private func mutualLabel(count: Int) -> String {
        let firstName = vm.model.mutualConnectionPreview.first
            .map { $0.displayName.components(separatedBy: " ").first ?? $0.displayName }
            ?? "Someone"
        switch count {
        case 1:  return "\(firstName) follows them"
        case 2:  return "\(firstName) and 1 other follow them"
        default: return "\(firstName) and \(count - 1) others follow them"
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Reason Chip Subview

private struct MiniReasonChip: View {
    let reason: UserMiniReason

    var body: some View {
        HStack(spacing: 4) {
            if let icon = reason.icon {
                Image(systemName: icon)
                    .font(.systemScaled(10, weight: .medium))
            }
            Text(reason.label)
                .font(.systemScaled(11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.05))
                .overlay(
                    Capsule().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Press Button Style

private struct MiniPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}


// MARK: - Preview

#Preview("Discovery") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.discovery,
                handler: .mock()
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

#Preview("Discovery — Named Mutuals") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.discovery,
                handler: .mock()
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

#Preview("OpenTable — Unread Thread") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.openTableUnread,
                handler: .mock()
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

#Preview("OpenTable — Read Thread") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.openTableRead,
                handler: .mock()
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

#Preview("OpenTable — Replied Thread") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.openTableReplied,
                handler: .mock()
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

#Preview("Prayer — Active Topic") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.prayer,
                handler: .mock()
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

#Preview("Prayer — Already Prayed Today") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.prayerPrayedToday,
                handler: .mock()
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

#Preview("Testimony — With Title") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.testimonies,
                handler: .mock()
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

#Preview("Already Followed") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.alreadyFollowed,
                handler: .mock()
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

#Preview("Cannot Message") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.cannotMessage,
                handler: .mock(messagingAllowed: false)
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

#Preview("Long Name") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.longName,
                handler: .mock()
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

#Preview("Missing Avatar / Low Info") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.lowInfo,
                handler: .mock()
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

#Preview("Low Signal — Context Suppressed") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.noSignal,
                handler: .mock()
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

#Preview("Blocked / Unavailable") {
    ScrollView {
        UserProfileViewMini(
            vm: UserProfileMiniViewModel(
                model: UserProfileMiniPreviewData.blocked,
                handler: .mock()
            )
        )
        .padding()
    }
    .background(Color(white: 0.96))
}

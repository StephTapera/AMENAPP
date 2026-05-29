// AmenYouPanelView.swift
// AMENAPP
//
// Slack-style "You" slide-over profile panel.
// Appears as a modal sheet when the user taps their avatar.
// Faith-native design using AMEN design tokens throughout.

import SwiftUI

// MARK: - SpiritualPresenceStatus

enum SpiritualPresenceStatus: String, CaseIterable, Identifiable {
    case active    = "active"
    case praying   = "praying"
    case inService = "inService"
    case studying  = "studying"
    case atRest    = "atRest"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active:    return "Active"
        case .praying:   return "Praying"
        case .inService: return "In Service"
        case .studying:  return "Studying"
        case .atRest:    return "At Rest"
        }
    }

    var icon: String {
        switch self {
        case .active:    return "circle.fill"
        case .praying:   return "hands.sparkles.fill"
        case .inService: return "building.columns.fill"
        case .studying:  return "book.fill"
        case .atRest:    return "moon.zzz.fill"
        }
    }

    var emoji: String {
        switch self {
        case .active:    return "🟢"
        case .praying:   return "🙏"
        case .inService: return "⛪"
        case .studying:  return "📖"
        case .atRest:    return "💭"
        }
    }
}

// MARK: - AmenYouPanelViewModel

@MainActor
final class AmenYouPanelViewModel: ObservableObject {
    @Published var displayName: String = "Beloved"
    @Published var avatarInitial: String = "B"
    @Published var avatarColorHex: String = "#7043CC"
    @Published var presenceStatus: SpiritualPresenceStatus = .active
    @Published var heartStatus: String = ""
    @Published var notificationsPaused: Bool = false
    @Published var isAway: Bool = false
    @Published var pendingInvitations: Int = 0

    func loadCurrentUser() async {
        // stub: populate from Firebase Auth / Firestore user document
    }

    func updatePresenceStatus(_ status: SpiritualPresenceStatus) async {
        presenceStatus = status
        // stub: write to Firestore users/{uid}/presenceStatus
    }

    func toggleNotificationsPaused() {
        notificationsPaused.toggle()
    }

    func toggleAway() {
        isAway.toggle()
    }

    func signOut() async {
        // stub: call FirebaseAuth.signOut() and clean local state
    }
}

// MARK: - AmenYouPanelView

struct AmenYouPanelView: View {

    @StateObject private var viewModel = AmenYouPanelViewModel()

    var onDismiss: () -> Void = {}
    var onViewProfile: () -> Void = {}
    var onPreferencesTapped: () -> Void = {}
    var onNotificationsTapped: () -> Void = {}
    var onStatusChanged: (SpiritualPresenceStatus) -> Void = { _ in }

    @State private var showHeartStatusPicker: Bool = false
    @State private var signOutConfirmationShown: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            AmenTheme.Colors.backgroundPrimary
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    closeRow
                    profileHeroSection
                    presencePillRow
                        .padding(.top, 16)
                        .padding(.horizontal, 16)

                    Divider()
                        .foregroundStyle(AmenTheme.Colors.separatorSubtle)
                        .padding(.top, 20)

                    sectionBlock(
                        header: "STATUS",
                        rows: [pauseNotificationsRow, setAwayRow]
                    )

                    sectionBlock(
                        header: "SOCIAL",
                        rows: [invitationsRow, viewProfileRow]
                    )

                    sectionBlock(
                        header: "TOOLS",
                        rows: [prayerCircleRow, notificationsRow, preferencesRow]
                    )

                    sectionBlock(
                        header: "ACCOUNT",
                        rows: [signOutRow]
                    )

                    Spacer(minLength: 40)
                }
            }
        }
        .task { await viewModel.loadCurrentUser() }
        .sheet(isPresented: $showHeartStatusPicker) {
            HeartStatusPickerSheet(
                currentStatus: $viewModel.heartStatus,
                onDismiss: { showHeartStatusPicker = false }
            )
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Sign out of AMEN?",
            isPresented: $signOutConfirmationShown,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task { await viewModel.signOut() }
                onDismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Close row

    private var closeRow: some View {
        HStack {
            Button {
                HapticManager.impact(style: .light)
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.medium)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(AmenTheme.Colors.surfaceChip)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close panel")
            .accessibilityHint("Dismisses the profile panel")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Profile hero

    private var profileHeroSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: AmenTheme.Colors.shadowCard, radius: 8, x: 0, y: 2)

            VStack(spacing: 12) {
                avatarCircle
                    .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text(viewModel.displayName)
                        .font(AMENFont.bold(20))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    presenceStatusLine
                }

                heartStatusField
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AmenTheme.Colors.amenGold, AmenTheme.Colors.amenPurple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 72)

            Text(viewModel.avatarInitial)
                .font(AMENFont.bold(30))
                .foregroundStyle(.white)
        }
    }

    private var presenceStatusLine: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(presenceDotColor)
                .frame(width: 8, height: 8)
                .animation(
                    reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.78),
                    value: viewModel.presenceStatus
                )

            Text(presenceStatusLabel)
                .font(AMENFont.regular(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .animation(
                    reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.78),
                    value: viewModel.presenceStatus
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(presenceStatusLabel)")
    }

    private var presenceDotColor: Color {
        switch viewModel.presenceStatus {
        case .active:    return AmenTheme.Colors.statusSuccess
        case .praying:   return AmenTheme.Colors.amenGold
        case .inService: return AmenTheme.Colors.amenPurple
        case .studying:  return AmenTheme.Colors.amenBlue
        case .atRest:    return AmenTheme.Colors.textTertiary
        }
    }

    private var presenceStatusLabel: String {
        switch viewModel.presenceStatus {
        case .active:    return "Active"
        case .praying:   return "Praying 🙏"
        case .inService: return "In Service ⛪"
        case .studying:  return "Studying 📖"
        case .atRest:    return "At Rest 💭"
        }
    }

    private var heartStatusField: some View {
        Button {
            HapticManager.impact(style: .light)
            showHeartStatusPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.clipboard")
                    .imageScale(.small)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)

                Text(
                    viewModel.heartStatus.isEmpty
                        ? "What's on your heart?"
                        : viewModel.heartStatus
                )
                .font(AMENFont.regular(14))
                .foregroundStyle(
                    viewModel.heartStatus.isEmpty
                        ? AmenTheme.Colors.textPlaceholder
                        : AmenTheme.Colors.textPrimary
                )
                .lineLimit(1)
                .truncationMode(.tail)

                Spacer()

                Image(systemName: "pencil")
                    .imageScale(.small)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AmenTheme.Colors.surfaceInput)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            viewModel.heartStatus.isEmpty
                ? "Set heart status"
                : "Heart status: \(viewModel.heartStatus)"
        )
        .accessibilityHint("Opens a picker to share what's on your heart")
    }

    // MARK: - Presence pills

    private var presencePillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SpiritualPresenceStatus.allCases) { status in
                    presencePill(status)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spiritual presence status")
    }

    private func presencePill(_ status: SpiritualPresenceStatus) -> some View {
        let isSelected = viewModel.presenceStatus == status
        return Button {
            HapticManager.impact(style: .light)
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.15)
                    : .spring(response: 0.32, dampingFraction: 0.78)
            ) {
                viewModel.presenceStatus = status
            }
            Task { await viewModel.updatePresenceStatus(status) }
            onStatusChanged(status)
        } label: {
            HStack(spacing: 5) {
                Text(status.emoji)
                    .font(.system(size: 13))
                Text(status.displayName)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(
                        isSelected
                            ? AmenTheme.Colors.textInverse
                            : AmenTheme.Colors.textPrimary
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? AmenTheme.Colors.amenGold : AmenTheme.Colors.surfaceChip)
            .clipShape(Capsule())
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.15)
                    : .spring(response: 0.32, dampingFraction: 0.78),
                value: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(status.displayName) status")
        .accessibilityHint(
            isSelected
                ? "Currently selected"
                : "Tap to set your status to \(status.displayName)"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Section builder

    private func sectionBlock(header: String, rows: [AnyView]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .font(AMENFont.semiBold(11))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    row
                    if index < rows.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .background(AmenTheme.Colors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Row builder helper

    private func panelRow(
        icon: String,
        iconTint: Color,
        label: String,
        badge: Int = 0,
        trailingView: AnyView? = nil,
        isDestructive: Bool = false,
        a11yLabel: String,
        a11yHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            HapticManager.impact(style: .light)
            action()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .imageScale(.small)
                    .foregroundStyle(isDestructive ? AmenTheme.Colors.statusError : iconTint)
                    .frame(width: 22, height: 22)

                Text(label)
                    .font(AMENFont.regular(16))
                    .foregroundStyle(
                        isDestructive
                            ? AmenTheme.Colors.statusError
                            : AmenTheme.Colors.textPrimary
                    )

                Spacer()

                if badge > 0 {
                    Text("\(badge)")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AmenTheme.Colors.statusError)
                        .clipShape(Capsule())
                        .accessibilityLabel("\(badge) pending")
                }

                if let trailing = trailingView {
                    trailing
                }

                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(a11yHint)
    }

    // MARK: - Action rows

    private var pauseNotificationsRow: AnyView {
        AnyView(
            Button(action: {
                HapticManager.impact(style: .light)
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.15)
                        : .spring(response: 0.32, dampingFraction: 0.78)
                ) {
                    viewModel.toggleNotificationsPaused()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "bell.slash")
                        .imageScale(.small)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .frame(width: 22, height: 22)

                    Text("Pause Notifications")
                        .font(AMENFont.regular(16))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)

                    Spacer()

                    Toggle("", isOn: $viewModel.notificationsPaused)
                        .labelsHidden()
                        .tint(AmenTheme.Colors.amenGold)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                viewModel.notificationsPaused
                    ? "Notifications paused"
                    : "Pause Notifications"
            )
            .accessibilityHint(
                viewModel.notificationsPaused
                    ? "Toggle to resume notifications"
                    : "Toggle to pause all notifications"
            )
        )
    }

    private var setAwayRow: AnyView {
        AnyView(
            Button(action: {
                HapticManager.impact(style: .light)
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.15)
                        : .spring(response: 0.32, dampingFraction: 0.78)
                ) {
                    viewModel.toggleAway()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill")
                        .imageScale(.small)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .frame(width: 22, height: 22)

                    Text("Set yourself as away")
                        .font(AMENFont.regular(16))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)

                    Spacer()

                    Toggle("", isOn: $viewModel.isAway)
                        .labelsHidden()
                        .tint(AmenTheme.Colors.amenPurple)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isAway ? "Currently away" : "Set yourself as away")
            .accessibilityHint(
                viewModel.isAway
                    ? "Toggle to mark yourself as active"
                    : "Toggle to mark yourself as away"
            )
        )
    }

    private var invitationsRow: AnyView {
        AnyView(
            panelRow(
                icon: "person.badge.plus",
                iconTint: AmenTheme.Colors.textSecondary,
                label: "Invitations to connect",
                badge: viewModel.pendingInvitations,
                a11yLabel: viewModel.pendingInvitations > 0
                    ? "Invitations to connect, \(viewModel.pendingInvitations) pending"
                    : "Invitations to connect",
                a11yHint: "Opens your pending connection invitations"
            ) {
                // navigation handled by parent host
            }
        )
    }

    private var viewProfileRow: AnyView {
        AnyView(
            panelRow(
                icon: "person.circle.fill",
                iconTint: AmenTheme.Colors.textSecondary,
                label: "View full profile",
                a11yLabel: "View full profile",
                a11yHint: "Opens your complete profile page"
            ) {
                onViewProfile()
                onDismiss()
            }
        )
    }

    private var prayerCircleRow: AnyView {
        AnyView(
            panelRow(
                icon: "sparkles",
                iconTint: AmenTheme.Colors.amenGold,
                label: "Prayer Circle (VIP)",
                a11yLabel: "Prayer Circle VIP",
                a11yHint: "Opens your exclusive Prayer Circle"
            ) {
                // navigation handled by parent host
            }
        )
    }

    private var notificationsRow: AnyView {
        AnyView(
            panelRow(
                icon: "bell.fill",
                iconTint: AmenTheme.Colors.textSecondary,
                label: "Notifications",
                a11yLabel: "Notifications settings",
                a11yHint: "Opens notification preferences"
            ) {
                onNotificationsTapped()
                onDismiss()
            }
        )
    }

    private var preferencesRow: AnyView {
        AnyView(
            panelRow(
                icon: "gearshape.fill",
                iconTint: AmenTheme.Colors.textSecondary,
                label: "Preferences",
                a11yLabel: "Preferences",
                a11yHint: "Opens app preferences and settings"
            ) {
                onPreferencesTapped()
                onDismiss()
            }
        )
    }

    private var signOutRow: AnyView {
        AnyView(
            panelRow(
                icon: "rectangle.portrait.and.arrow.right",
                iconTint: AmenTheme.Colors.statusError,
                label: "Sign Out",
                isDestructive: true,
                a11yLabel: "Sign Out",
                a11yHint: "Signs you out of AMEN"
            ) {
                signOutConfirmationShown = true
            }
        )
    }
}

// MARK: - HeartStatusPickerSheet

/// Inline spiritual status composer sheet.
private struct HeartStatusPickerSheet: View {

    @Binding var currentStatus: String
    var onDismiss: () -> Void

    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

    private let suggestions: [String] = [
        "Grateful for His grace 🙏",
        "Seeking His guidance 📖",
        "Standing on His promises ✝️",
        "Walking by faith, not sight",
        "Trusting the process 🌱",
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Share what's on your heart…", text: $draft, axis: .vertical)
                    .font(AMENFont.regular(16))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .padding(12)
                    .background(AmenTheme.Colors.surfaceInput)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .focused($fieldFocused)
                    .lineLimit(3)
                    .accessibilityLabel("Heart status text field")

                Text("SUGGESTIONS")
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .accessibilityAddTraits(.isHeader)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                HapticManager.impact(style: .light)
                                draft = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AmenTheme.Colors.surfaceChip)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(suggestion)
                            .accessibilityHint("Tap to use this suggestion")
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .background(AmenTheme.Colors.backgroundPrimary)
            .navigationTitle("What's on your heart?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticManager.impact(style: .light)
                        onDismiss()
                    }
                    .font(AMENFont.regular(16))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        HapticManager.impact(style: .light)
                        currentStatus = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        onDismiss()
                    }
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            draft = currentStatus
            fieldFocused = true
        }
    }
}

// MARK: - Preview

#Preview("You Panel") {
    AmenYouPanelView(
        onDismiss: {},
        onViewProfile: {},
        onPreferencesTapped: {},
        onNotificationsTapped: {},
        onStatusChanged: { _ in }
    )
}

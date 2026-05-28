// SmartAccountResumeView.swift
// AMENAPP
//
// Instagram/Facebook-style one-tap account resume screen.
// Shows after app launch when a remembered account exists.
// Never routes to Home until server validation passes.
//
// Design: white background, black text, native iOS Liquid Glass pills,
// Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency support.

import SwiftUI
import FirebaseAuth
import FirebaseAnalytics

struct SmartAccountResumeView: View {

    // Called when validation succeeds — hides splash, reveals main content
    let onAuthenticated: () -> Void
    // Called when user wants a different account / re-auth / error terminal
    let onUseAnotherAccount: () -> Void

    @StateObject private var viewModel = SmartAccountResumeViewModel()
    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @ObservedObject private var accountStore = RememberedAccountStore.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var contentOpacity: Double = 0
    @State private var contentScale: CGFloat = 0.96
    @State private var showAccountSwitcher = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                stateContent
                    .opacity(contentOpacity)
                    .scaleEffect(contentScale)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8),
                        value: contentOpacity
                    )
                Spacer()

                // AMEN watermark
                Text("AMEN")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(5)
                    .foregroundStyle(.primary.opacity(0.1))
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            Analytics.logEvent("smart_account_resume_shown", parameters: nil)
            viewModel.beginValidation()
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.35).delay(0.1)) {
                contentOpacity = 1
                contentScale = 1
            }
        }
        .onChange(of: viewModel.route) { _, route in
            handleRoute(route)
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    // MARK: - State Router

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.screenState {
        case .loading:
            loadingView

        case .continueAvailable(let account):
            continueView(account: account)

        case .reAuthRequired(let account):
            reAuthView(account: account)

        case .offline(let account):
            offlineView(account: account)

        case .error(let message, let account):
            errorView(message: message, account: account)
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: 0) {
            let account = accountStore.mostRecentAccount
            if let account = account {
                avatarView(account: account, size: 88)
                spacer(24)
                Text(account.displayName)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                spacer(10)
            }
            HStack(spacing: 8) {
                Text("Logging you in")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if reduceMotion {
                    ProgressView().tint(.secondary).scaleEffect(0.75)
                } else {
                    LiquidDotsProgressView(color: .secondary)
                }
            }
            .accessibilityLabel("Logging you in, please wait")
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Continue State

    private func continueView(account: RememberedAccount) -> some View {
        VStack(spacing: 0) {
            avatarView(account: account, size: 88)
            spacer(24)

            Text(account.displayName)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            if let username = account.username {
                spacer(4)
                Text("@\(username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            spacer(36)

            // Continue pill
            Button {
                Task { await viewModel.continueTapped() }
            } label: {
                Text("Continue as \(account.firstName)")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: 300)
                    .padding(.vertical, 15)
                    .background(Color.primary, in: Capsule())
            }
            .accessibilityLabel("Continue as \(account.displayName)")

            spacer(14)

            // Secondary actions row
            HStack(spacing: 20) {
                Button {
                    notYouTapped(account: account)
                } label: {
                    Text("Not you?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Not \(account.displayName)?")

                if accountStore.accounts.count > 1 {
                    Circle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 3, height: 3)
                        .accessibilityHidden(true)

                    Button {
                        Analytics.logEvent("account_switch_started", parameters: nil)
                        withAnimation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.82)) {
                            showAccountSwitcher.toggle()
                        }
                    } label: {
                        Text("Switch accounts")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Switch accounts")
                } else {
                    Circle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 3, height: 3)
                        .accessibilityHidden(true)

                    Button {
                        Analytics.logEvent("smart_account_resume_use_another_account_tapped", parameters: nil)
                        onUseAnotherAccount()
                    } label: {
                        Text("Use another account")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Use another account")
                }
            }

            // Multi-account switcher panel
            if showAccountSwitcher && accountStore.accounts.count > 1 {
                spacer(28)
                accountSwitcherPanel(currentUID: account.uid)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Re-Auth State

    private func reAuthView(account: RememberedAccount) -> some View {
        VStack(spacing: 0) {
            avatarView(account: account, size: 88)
            spacer(24)

            Text(account.displayName)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            spacer(10)
            Text("Please confirm it's you")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            spacer(32)

            Button {
                Analytics.logEvent("smart_account_resume_reauth_required", parameters: nil)
                onUseAnotherAccount()
            } label: {
                Text("Sign In Again")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: 300)
                    .padding(.vertical, 15)
                    .background(Color.primary, in: Capsule())
            }
            .accessibilityLabel("Sign in again as \(account.displayName)")

            spacer(14)

            Button {
                Analytics.logEvent("smart_account_resume_use_another_account_tapped", parameters: nil)
                onUseAnotherAccount()
            } label: {
                Text("Use another account")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Offline State

    private func offlineView(account: RememberedAccount) -> some View {
        VStack(spacing: 0) {
            avatarView(account: account, size: 88)
            spacer(24)

            Text(account.displayName)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            spacer(10)
            Text("Connection issue. Retry to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            spacer(32)

            Button {
                viewModel.retryValidation()
            } label: {
                Text("Retry")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: 300)
                    .padding(.vertical, 15)
                    .background(Color.primary, in: Capsule())
            }

            spacer(14)

            Button {
                Analytics.logEvent("smart_account_resume_use_another_account_tapped", parameters: nil)
                onUseAnotherAccount()
            } label: {
                Text("Use another account")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Error State

    private func errorView(message: String, account: RememberedAccount?) -> some View {
        VStack(spacing: 0) {
            if let account = account {
                avatarView(account: account, size: 88)
                spacer(24)
                Text(account.displayName)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                spacer(10)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            spacer(32)

            Button {
                viewModel.retryValidation()
            } label: {
                Text("Retry")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: 300)
                    .padding(.vertical, 15)
                    .background(Color.primary, in: Capsule())
            }

            spacer(14)

            Button {
                Analytics.logEvent("smart_account_resume_use_another_account_tapped", parameters: nil)
                onUseAnotherAccount()
            } label: {
                Text("Use another account")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let account = account {
                spacer(8)
                Button {
                    notYouTapped(account: account)
                } label: {
                    Text("Not you?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Multi-Account Switcher

    private func accountSwitcherPanel(currentUID: String) -> some View {
        let others = accountStore.accounts.filter { $0.uid != currentUID }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Other accounts")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ForEach(others) { account in
                Button {
                    switchToAccount(account)
                } label: {
                    HStack(spacing: 12) {
                        smallAvatarView(account: account)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            if let username = account.username {
                                Text("@\(username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if account.uid != others.last?.uid {
                    Divider().padding(.leading, 56)
                }
            }

            Divider().padding(.top, 2)

            Button {
                Analytics.logEvent("smart_account_resume_use_another_account_tapped", parameters: nil)
                onUseAnotherAccount()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 36, height: 36)
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("Add another account")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(Material.regularMaterial))
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Avatar

    @ViewBuilder
    private func avatarView(account: RememberedAccount, size: CGFloat) -> some View {
        ZStack {
            // Glass ring
            Circle()
                .fill(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(Material.ultraThinMaterial))
                .frame(width: size + 18, height: size + 18)
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)

            // Photo or initials
            Group {
                if let url = account.avatarCacheURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            initialsView(account: account, size: size)
                        }
                    }
                } else {
                    initialsView(account: account, size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        }
        .accessibilityLabel("Profile photo for \(account.displayName)")
        .accessibilityAddTraits(.isImage)
    }

    private func initialsView(account: RememberedAccount, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(.tertiarySystemBackground))
            Text(account.initials)
                .font(.system(size: size * 0.35, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private func smallAvatarView(account: RememberedAccount) -> some View {
        Group {
            if let url = account.avatarCacheURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Circle().fill(Color(.tertiarySystemBackground))
                            Text(account.initials).font(.caption.bold()).foregroundStyle(.primary)
                        }
                    }
                }
            } else {
                ZStack {
                    Circle().fill(Color(.tertiarySystemBackground))
                    Text(account.initials).font(.caption.bold()).foregroundStyle(.primary)
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    // MARK: - Actions

    private func notYouTapped(account: RememberedAccount) {
        Analytics.logEvent("smart_account_resume_not_you_tapped", parameters: nil)
        RememberedAccountStore.shared.clearAccount(uid: account.uid)
        authViewModel.signOut()
        onUseAnotherAccount()
    }

    private func switchToAccount(_ account: RememberedAccount) {
        Analytics.logEvent("account_switch_started", parameters: nil)
        // Sign out current user, then route to login.
        // After they log in, auth listener updates RememberedAccountStore.
        authViewModel.signOut()
        onUseAnotherAccount()
    }

    private func handleRoute(_ route: AccountResumeRoute?) {
        guard let route = route else { return }
        switch route {
        case .home, .onboarding, .suspended:
            // Let existing ContentView gates handle onboarding/deactivation routing.
            // Just reveal the main content layer.
            Analytics.logEvent("smart_account_resume_success", parameters: nil)
            onAuthenticated()
        case .profileMissing, .reAuth, .login:
            Analytics.logEvent("smart_account_resume_failed", parameters: nil)
            onUseAnotherAccount()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func spacer(_ height: CGFloat) -> some View {
        Spacer().frame(height: height)
    }
}

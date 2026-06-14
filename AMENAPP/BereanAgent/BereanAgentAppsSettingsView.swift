// BereanAgentAppsSettingsView.swift
// AMEN — Berean Agent Surface · Wave 1 Lane A
//
// Full-screen settings for connected apps and permission mode.
// Design: §2 warm paper bg, wine-red accent (one per screen), 24pt card corners,
//         Liquid Glass via .glassEffect(), no glass-on-glass.
// §7 blockers enforced: giving + messages are read-only labels, not tappable.

import SwiftUI

// MARK: - Main Settings View

@MainActor
struct BereanAgentAppsSettingsView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var broker = BASPermissionBroker.shared
    @State private var registry = BASConnectedAppsRegistry.shared
    @State private var selectedApp: BASConnectedApp?
    @State private var showScopeSheet = false

    // Mirror broker.isPrivateModeActive locally for Toggle binding
    @State private var privateModeOn: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Warm paper background
                Color.basWarmPaper
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        privateModeCard
                        permissionModeSection
                        connectedAppsSection
                        browseAppsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Connected Apps")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.basWineRed)
                        .accessibilityLabel("Done, close Connected Apps settings")
                }
            }
            .onAppear { privateModeOn = broker.isPrivateModeActive }
            .sheet(isPresented: $showScopeSheet) {
                if let app = selectedApp {
                    BereanAgentAppScopeSheet(app: app, onDismiss: {
                        showScopeSheet = false
                        selectedApp = nil
                    })
                }
            }
        }
    }

    // MARK: Private Mode Card

    private var privateModeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: privateModeOn ? "lock.fill" : "lock.open.fill")
                .font(.title2)
                .foregroundStyle(privateModeOn ? Color.basWineRed : Color.secondary)
                .animation(
                    reduceMotion ? .none : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8)),
                    value: privateModeOn
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Private Mode")
                    .font(.headline)
                    .foregroundStyle(privateModeOn ? Color.basWineRed : Color.basInk)

                if privateModeOn {
                    Text("Berean Paused")
                        .font(.caption)
                        .foregroundStyle(Color.basWineRed)
                        .fontWeight(.semibold)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(
                reduceMotion ? .none : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8)),
                value: privateModeOn
            )

            Spacer()

            Toggle("", isOn: $privateModeOn)
                .labelsHidden()
                .tint(Color.basWineRed)
                .onChange(of: privateModeOn) { _, newValue in
                    if newValue {
                        broker.pauseAll()
                    } else {
                        broker.resumeAll()
                    }
                }
                .accessibilityLabel("Private Mode")
                .accessibilityHint("Pauses all Berean context access")
        }
        .padding(16)
        .background(Color.basTan, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.basInk.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    // MARK: Permission Mode Section

    private var permissionModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Permission Mode")

            Picker("Permission Mode", selection: permissionModeBinding) {
                Text("Ask Every Time").tag(BASScopeMode.askEveryTime)
                Text("Important Actions Only").tag(BASScopeMode.importantActionsOnly)
                Text("Read Only").tag(BASScopeMode.readOnly)
                Text("Private Mode").tag(BASScopeMode.privateMode)
            }
            .pickerStyle(.menu)
            .padding(14)
            .background(Color.basTan, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.basInk.opacity(0.12), radius: 12, x: 0, y: 4)
            .accessibilityLabel("Permission Mode Picker")
            .accessibilityHint("Choose how Berean asks before accessing connected apps")
        }
    }

    private var permissionModeBinding: Binding<BASScopeMode> {
        Binding<BASScopeMode>(
            get: {
                if broker.isPrivateModeActive { return .privateMode }
                return .askEveryTime
            },
            set: { newMode in
                if newMode == .privateMode {
                    privateModeOn = true
                    broker.pauseAll()
                } else {
                    privateModeOn = false
                    broker.resumeAll()
                }
            }
        )
    }

    // MARK: Connected Apps Section

    /// Apps that are neither blocked (§7) nor disabled.
    private var enabledApps: [BASConnectedApp] {
        registry.apps.filter { app in
            app.id != .giving && app.id != .messages && app.isEnabled
        }
    }

    private var connectedAppsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Connected Apps")

            if enabledApps.isEmpty {
                zeroAppsEnabledEmptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(registry.apps.enumerated()), id: \.element.id) { index, app in
                        appRow(app: app, isLast: index == registry.apps.count - 1)
                    }
                }
                .background(Color.basTan, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.basInk.opacity(0.12), radius: 12, x: 0, y: 4)
            }
        }
    }

    // MARK: Zero-Apps Empty State

    private var zeroAppsEnabledEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.largeTitle.weight(.light))
                .foregroundStyle(Color.basInk.opacity(0.25))
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Connect apps to give Berean helpful context.")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundColor(.basInk)
                    .multilineTextAlignment(.center)

                Text("Your Scripture library and calendar are great starting points.")
                    .font(.footnote)
                    .foregroundColor(.basInk.opacity(0.55))
                    .multilineTextAlignment(.center)
            }

            Button {
                registry.setEnabled(true, for: .bibleDotCom)
            } label: {
                Text("Connect Scripture")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.basWineRed)
                            .shadow(color: Color.basWineRed.opacity(0.30), radius: 8, x: 0, y: 3)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Connect Scripture — enable Bible.com to give Berean helpful context")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(Color.basTan, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.basInk.opacity(0.12), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func appRow(app: BASConnectedApp, isLast: Bool) -> some View {
        let isBlocked = app.id == .giving || app.id == .messages

        Group {
            HStack(spacing: 12) {
                Image(systemName: app.id.iconToken)
                    .font(.body)
                    .foregroundStyle(Color.basInk.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.id.displayName)
                        .font(.body)
                        .foregroundStyle(isBlocked ? Color.secondary : Color.basInk)

                    if isBlocked {
                        Text("Not available yet")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    } else if app.id.isSensitive {
                        Text("Requires explicit grant each time")
                            .font(.caption2)
                            .foregroundStyle(Color(.systemOrange))
                    }
                }

                Spacer()

                if isBlocked {
                    scopeChip(text: "Unavailable", color: Color.secondary.opacity(0.5))
                } else {
                    scopeChip(text: scopeLabel(app.currentScope), color: Color.basInk.opacity(0.12))
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .onTapGesture {
            guard !isBlocked else { return }
            selectedApp = app
            showScopeSheet = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isBlocked
                ? "\(app.id.displayName), not available yet"
                : "\(app.id.displayName), current scope: \(scopeLabel(app.currentScope))"
        )
        .accessibilityHint(isBlocked ? "" : "Tap to change permission scope")
        .accessibilityAddTraits(isBlocked ? [] : .isButton)

        if !isLast {
            Divider()
                .padding(.leading, 56)
        }
    }

    // MARK: Browse Apps Section

    private var browseAppsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Discover")

            NavigationLink(destination: BereanAgentAppBrowserStubView()) {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.body)
                        .foregroundStyle(Color.basInk.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)

                    Text("Browse Apps")
                        .font(.body)
                        .foregroundStyle(Color.basInk)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .background(Color.basTan, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.basInk.opacity(0.12), radius: 12, x: 0, y: 4)
            }
            .accessibilityLabel("Browse Apps")
            .accessibilityHint("See more apps coming soon")
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(Color.basInk.opacity(0.6))
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }

    private func scopeChip(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(Color.basInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }

    private func scopeLabel(_ scope: BASScopeMode) -> String {
        switch scope {
        case .askEveryTime:         return "Ask Every Time"
        case .importantActionsOnly: return "Important Only"
        case .readOnly:             return "Read Only"
        case .never_:               return "Never"
        case .privateMode:          return "Private"
        }
    }
}

// MARK: - Scope Sheet (inline)

@MainActor
struct BereanAgentAppScopeSheet: View {

    let app: BASConnectedApp
    let onDismiss: () -> Void

    @State private var registry = BASConnectedAppsRegistry.shared
    @State private var selectedScope: BASScopeMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(app: BASConnectedApp, onDismiss: @escaping () -> Void) {
        self.app = app
        self.onDismiss = onDismiss
        _selectedScope = State(initialValue: app.currentScope)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.basWarmPaper.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    // App header
                    HStack(spacing: 14) {
                        Image(systemName: app.id.iconToken)
                            .font(.largeTitle)
                            .foregroundStyle(Color.basInk)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.id.displayName)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.basInk)

                            Text(whyText(for: app.id))
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 8)

                    if app.id.isSensitive {
                        Label {
                            Text("Requires explicit grant each time")
                                .font(.footnote)
                                .foregroundStyle(Color(.systemOrange))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(.systemOrange))
                        }
                        .padding(12)
                        .background(Color(.systemOrange).opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Sensitive app: requires explicit grant each time")
                    }

                    // Scope picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Access Scope")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.basInk.opacity(0.6))
                            .textCase(.uppercase)

                        Picker("Scope", selection: $selectedScope) {
                            Text("Read Only").tag(BASScopeMode.readOnly)
                            Text("Ask Every Time").tag(BASScopeMode.askEveryTime)
                            Text("Never").tag(BASScopeMode.never_)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Access scope for \(app.id.displayName)")
                    }

                    Spacer()

                    Button {
                        withAnimation(
                            reduceMotion ? .none : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))
                        ) {
                            registry.setEnabled(selectedScope != .never_, for: app.id)
                        }
                        onDismiss()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.basWineRed, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .accessibilityLabel("Done, save scope for \(app.id.displayName)")
                }
                .padding(20)
            }
            .navigationTitle("App Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .accessibilityLabel("Cancel, discard scope changes")
                }
            }
        }
    }

    private func whyText(for appID: BASConnectedAppID) -> String {
        switch appID {
        case .appleMusic:    return "Berean can suggest worship music during prayer and study sessions."
        case .spotify:       return "Berean can suggest worship music and podcasts aligned with your study."
        case .bibleDotCom:   return "Berean can sync reading plans and highlights for deeper study."
        case .calendar:      return "Berean can help schedule devotion, prayer, and church events."
        case .notes:         return "Berean can read and enrich sermon and study notes you've written."
        case .churchProfile: return "Berean can surface church-specific content and sermon archives."
        case .files:         return "Berean can access study PDFs and documents you share."
        case .giving:        return "Read-only access. No write paths available (§7)."
        case .messages:      return "Not available yet (§7)."
        }
    }
}

// MARK: - Browser Stub

@MainActor
struct BereanAgentAppBrowserStubView: View {

    var body: some View {
        ZStack {
            Color.basWarmPaper.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(Color.basInk.opacity(0.3))
                    .accessibilityHidden(true)

                Text("More apps coming soon")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.basInk)

                Text("We're building integrations with your favorite faith-based and productivity apps.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .navigationTitle("Browse Apps")
        .navigationBarTitleDisplayMode(.large)
    }
}

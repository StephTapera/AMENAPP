import SwiftUI

struct SettingsSafetyReleaseTrainView: View {
    private let sections = SettingsReleaseSurface.allCases

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                SettingsSectionCard(
                    title: "Release Train Status",
                    footer: "All new settings surfaces stay disabled until their owned lane and backend dependency are verified."
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(SettingsSafetyInvariant.all) { invariant in
                            HStack(alignment: .top, spacing: 10) {
                                Text(invariant.id)
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 24)
                                    .background(Color.black, in: Capsule())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(invariant.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(invariant.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                SettingsSectionCard(title: "Surfaces") {
                    VStack(spacing: 0) {
                        ForEach(sections) { surface in
                            NavigationLink {
                                SettingsReleaseSurfaceDetailView(surface: surface)
                            } label: {
                                SettingsReleaseSurfaceRow(surface: surface)
                            }
                            .buttonStyle(.plain)

                            if surface != sections.last {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Settings Safety Train")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings, Safety & Account Controls")
                .font(.title2.weight(.bold))
            Text("Wave 0 contracts are present. Lane surfaces below are intentionally flag-gated until build, deploy, rules, and launch gates are verified.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsReleaseSurfaceRow: View {
    let surface: SettingsReleaseSurface

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: surface.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(surface.tint)
                .frame(width: 30, height: 30)
                .background(surface.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(surface.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(surface.flag.defaultValue ? "Live" : "Flag off")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(surface.flag.defaultValue ? .green : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(.secondarySystemFill), in: Capsule())
                }

                Text(surface.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(surface.title), \(surface.flag.defaultValue ? "live" : "flag off")")
    }
}

private struct SettingsReleaseSurfaceDetailView: View {
    let surface: SettingsReleaseSurface

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSectionCard(title: surface.title, footer: surface.footer) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(surface.summary, systemImage: surface.icon)
                            .font(.subheadline.weight(.semibold))

                        Text(surface.disabledCopy)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        SettingsReleaseDependencyList(surface: surface)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsSectionCard(title: "Launch Gate") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(surface.launchGate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Report status") {
                            // TODO(dependency): wire issue/status reporting once submitIssueReport deploys in Lane G.
                        }
                        .disabled(true)
                        .buttonStyle(.bordered)
                        .accessibilityHint("Disabled until issue reporting is deployed and audited.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(surface.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsReleaseDependencyList: View {
    let surface: SettingsReleaseSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Feature flag: \(surface.flag.rawValue)", systemImage: "flag")
            Label("Default: \(surface.flag.defaultValue ? "on" : "off")", systemImage: surface.flag.defaultValue ? "checkmark.circle" : "pause.circle")

            if surface.callables.isEmpty {
                Label("No callable dependency for this shell state", systemImage: "checkmark.shield")
            } else {
                ForEach(surface.callables, id: \.self) { callable in
                    Label("Callable: \(callable.rawValue) @ \(SettingsFunctionContract.region)", systemImage: "network")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

enum SettingsReleaseSurface: String, CaseIterable, Identifiable {
    case appearance
    case general
    case security
    case sessions
    case trustedContact
    case family
    case notifications
    case storage
    case dataControls
    case about
    case reportIssue
    case bereanAI
    case amenSafety

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .general: return "General"
        case .security: return "Security"
        case .sessions: return "Active Sessions"
        case .trustedContact: return "Trusted Contact"
        case .family: return "Family & Parental Controls"
        case .notifications: return "Notifications"
        case .storage: return "Storage"
        case .dataControls: return "Data Controls"
        case .about: return "About & Policies"
        case .reportIssue: return "Report App Issue"
        case .bereanAI: return "Berean AI Controls"
        case .amenSafety: return "AMEN Safety"
        }
    }

    var summary: String {
        switch self {
        case .appearance: return "Light glass, accent color, glass intensity, and reduce transparency."
        case .general: return "Language, scripture translation, input behavior, search, accessibility, voice, and speech."
        case .security: return "Passkeys, MFA, lockdown mode, Face ID gate, recovery, and suspicious-login alerts."
        case .sessions: return "Current and trusted sessions with single-session and all-session revocation."
        case .trustedContact: return "Opt-in emergency trusted contact with consent and server-only crisis notification."
        case .family: return "Guardian linking, age-aware defaults, COPPA entry point, and flags-only review."
        case .notifications: return "Granular channel choices with safety and account-security notification floors."
        case .storage: return "Storage breakdown, safe cache clear, and confirmed offline-download deletion."
        case .dataControls: return "Data export, E2EE client-side export, account deletion, AI-memory deletion, and connected apps."
        case .about: return "Terms, Privacy, Guidelines, DMCA, Child Safety Policy, version, build, and licenses."
        case .reportIssue: return "Issue report sheet with category, 2000-character limit, screenshot/log toggles, and PII stripping."
        case .bereanAI: return "Sources, scripture cross-check, uncertainty labels, denomination context without bias lock, and presets."
        case .amenSafety: return "Report, block, mute, hide topic, safe commenting, sensitive-topic warnings, and crisis routing."
        }
    }

    var disabledCopy: String {
        switch self {
        case .appearance, .general, .about:
            return "This surface can be implemented client-side, but remains behind its release flag until the shell build is green."
        default:
            return "This surface is visible for routing and review, but actions stay disabled until the required callable, rules, audit logging, and launch gate are verified."
        }
    }

    var footer: String {
        "Flag-off surfaces must remain reviewable and non-crashing; live actions are wired only after their dependency is deployed."
    }

    var launchGate: String {
        switch self {
        case .security, .sessions, .dataControls:
            return "G-SEC and G-PRIV must be human-verified before this can ship."
        case .trustedContact, .family, .amenSafety:
            return "G-CHILD and S4/S5/S7 must be human/legal-verified before this can ship."
        case .bereanAI:
            return "G-AISAFE must be human-verified before this can ship."
        default:
            return "R1/R2 build, accessibility, and flag-off state gates must be green before this can ship."
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintpalette"
        case .general: return "slider.horizontal.3"
        case .security: return "lock.shield"
        case .sessions: return "desktopcomputer.and.iphone"
        case .trustedContact: return "person.crop.circle.badge.checkmark"
        case .family: return "figure.2.and.child.holdinghands"
        case .notifications: return "bell.badge"
        case .storage: return "internaldrive"
        case .dataControls: return "tray.and.arrow.down"
        case .about: return "info.circle"
        case .reportIssue: return "exclamationmark.bubble"
        case .bereanAI: return "sparkles"
        case .amenSafety: return "shield.lefthalf.filled"
        }
    }

    var tint: Color {
        switch self {
        case .security, .sessions: return .orange
        case .trustedContact, .family, .amenSafety: return .green
        case .bereanAI: return .purple
        case .reportIssue: return .red
        case .storage, .dataControls: return .blue
        default: return .primary
        }
    }

    var flag: SettingsFeatureFlag {
        switch self {
        case .appearance: return .appearanceV2
        case .general: return .generalV2
        case .security: return .passkeys
        case .sessions: return .sessions
        case .trustedContact: return .trustedContact
        case .family: return .parentalControls
        case .notifications: return .notificationPrefsV2
        case .storage: return .storageManagement
        case .dataControls: return .dataExport
        case .about: return .settingsV2
        case .reportIssue: return .issueReporting
        case .bereanAI: return .bereanAIControls
        case .amenSafety: return .amenSafetyControls
        }
    }

    var callables: [SettingsFunctionContract.Callable] {
        switch self {
        case .appearance, .general, .about, .notifications, .storage:
            return []
        case .security:
            return [.setMfaTotp, .verifyMfaTotp, .disableMfaTotp, .setMfaSms, .verifyMfaSms, .disableMfaSms, .setLockdownMode]
        case .sessions:
            return [.listActiveSessions, .revokeSession, .revokeAllSessions]
        case .trustedContact:
            return [.addTrustedContact, .confirmTrustedContact, .removeTrustedContact]
        case .family:
            return [.requestFamilyLink, .acceptFamilyLink, .unlinkFamily, .setParentalControls]
        case .dataControls:
            return [.requestDataExport, .requestAccountDeletion, .deleteAiMemory]
        case .reportIssue, .amenSafety:
            return [.submitIssueReport]
        case .bereanAI:
            return []
        }
    }
}

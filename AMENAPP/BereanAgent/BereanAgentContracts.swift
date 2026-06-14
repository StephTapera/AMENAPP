// BereanAgentContracts.swift
// AMEN — Berean Agent Surface (BAS) frozen type contracts (Wave 0)
//
// FROZEN after BAS-W0-GATE. No agent may add, remove, rename, or retype
// anything in this file without a Class C blocker and human approval.
//
// Pre-check results (2026-06-14):
//   PermissionBroker: not found in codebase → BASPermissionBroker is safe
//   ComposerMode: found in CommunityOS/Composer/AmenComposerModels.swift
//                 and as BereanComposerMode typealias → BASComposerMode is safe
//   GlassEffectContainer: iOS 26 SwiftUI API confirmed as GlassEffectContainer(spacing:)
//                         with .glassEffect(_:in:) modifier on child views
//   Color(hex:): canonical definition in Color+Hex.swift (project-wide)
//   Motion.adaptive: confirmed present, use Motion.adaptive(_:) pattern
//   Flag helper: @Published private(set) var <name>: Bool = false + sync in syncBASFlags
//
// §7 BLOCKERS (read-only or hardcoded):
//   giving/finances: read-only, giving BASConnectedAppID always .never_
//   Safety audit: advisory default — "Share anyway" ALWAYS available, no hard-block
//   Workspace E2EE: isEncrypted=false, flagged OFF, show "E2EE: Coming Soon" label only

import Foundation
import SwiftUI

// MARK: - C-1: Permission Contract

/// Scope granularity for a BAS permission request.
enum BASScopeMode: String, Codable {
    case askEveryTime
    case importantActionsOnly
    case readOnly
    case never_
    case privateMode
}

/// How a user responds to a BAS permission request.
enum BASGrantType: String, Codable {
    case allowOnce
    case allowForThisTask
    case alwaysAllow
    case deny
}

/// A single permission request surfaced to the user before a BAS action.
struct BASPermissionRequest: Identifiable {
    let id: UUID
    let targetApp: String
    let why: String
    let wontAccess: String
    let scope: BASScopeMode
}

/// Central broker for all BAS permission decisions.
/// Stub: denies everything in private mode, grants .allowOnce otherwise.
@MainActor
@Observable
final class BASPermissionBroker {

    static let shared = BASPermissionBroker()

    private(set) var isPrivateModeActive: Bool = false

    private var allPaused: Bool = false

    private init() {}

    @discardableResult
    func request(_ req: BASPermissionRequest) async -> BASGrantType {
        guard !isPrivateModeActive, !allPaused else { return .deny }
        return .allowOnce
    }

    func pauseAll() { allPaused = true }
    func resumeAll() { allPaused = false }
}

// MARK: - C-2: Plugin Registry

/// Every first-party plugin available in the Berean Agent Surface.
enum BASPluginID: String, CaseIterable, Identifiable, Codable {
    case bible
    case compare
    case context
    case prayer
    case sermon
    case notes
    case church
    case music
    case research
    case image
    case memory
    case factCheck

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bible:     return "Bible"
        case .compare:   return "Compare Translations"
        case .context:   return "Context"
        case .prayer:    return "Prayer"
        case .sermon:    return "Sermon"
        case .notes:     return "Notes"
        case .church:    return "Church"
        case .music:     return "Music"
        case .research:  return "Research"
        case .image:     return "Image"
        case .memory:    return "Memory"
        case .factCheck: return "Fact Check"
        }
    }

    /// SF Symbol name for this plugin's icon.
    var iconToken: String {
        switch self {
        case .bible:     return "book.fill"
        case .compare:   return "arrow.left.arrow.right"
        case .context:   return "dot.radiowaves.up.forward"
        case .prayer:    return "hands.and.sparkles.fill"
        case .sermon:    return "waveform.and.mic"
        case .notes:     return "note.text"
        case .church:    return "building.columns.fill"
        case .music:     return "music.note"
        case .research:  return "magnifyingglass"
        case .image:     return "photo.fill"
        case .memory:    return "brain.filled.head.profile"
        case .factCheck: return "checkmark.shield.fill"
        }
    }

    /// Default scope required for this plugin.
    var requiredScope: BASScopeMode {
        switch self {
        case .bible, .compare, .factCheck, .music, .church, .context:
            return .readOnly
        case .notes, .memory:
            return .importantActionsOnly
        case .prayer, .sermon, .research, .image:
            return .askEveryTime
        }
    }
}

/// A concrete plugin instance with its current user-configured scope.
struct BASPlugin: Identifiable {
    let id: BASPluginID
    var currentScope: BASScopeMode
}

/// Registry of all BAS plugins. Scope changes persist in-memory only
/// (persistent storage is a Wave 1+ concern).
@Observable
@MainActor
final class BASPluginRegistry {

    static let shared = BASPluginRegistry()

    private(set) var plugins: [BASPlugin]

    private init() {
        plugins = BASPluginID.allCases.map { BASPlugin(id: $0, currentScope: $0.requiredScope) }
    }

    func updateScope(_ scope: BASScopeMode, for id: BASPluginID) {
        guard let idx = plugins.firstIndex(where: { $0.id == id }) else { return }
        plugins[idx].currentScope = scope
    }
}

// MARK: - C-3: Composer Mode

/// Predefined composer modes in the Berean Agent Surface.
/// Named BASComposerMode to avoid conflict with ComposerMode / BereanComposerMode
/// already present in CommunityOS/Composer/AmenComposerModels.swift.
enum BASComposerMode: String, CaseIterable, Identifiable {
    case ask
    case agent
    case study
    case pray
    case create
    case research
    case post
    case summarize

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ask:       return "Ask"
        case .agent:     return "Agent"
        case .study:     return "Study"
        case .pray:      return "Pray"
        case .create:    return "Create"
        case .research:  return "Research"
        case .post:      return "Post"
        case .summarize: return "Summarize"
        }
    }

    var placeholder: String {
        switch self {
        case .ask:       return "Ask Berean anything…"
        case .agent:     return "What should I do next?"
        case .study:     return "Start a Bible study…"
        case .pray:      return "What would you like to pray about?"
        case .create:    return "Write something with Berean…"
        case .research:  return "Research a topic or verse…"
        case .post:      return "Draft a post…"
        case .summarize: return "Paste or describe content to summarize…"
        }
    }

    /// Plugin IDs active for this mode's toolset.
    var toolset: [BASPluginID] {
        switch self {
        case .ask:       return [.bible, .context, .factCheck]
        case .agent:     return [.context, .memory, .notes, .church]
        case .study:     return [.bible, .compare, .sermon, .notes, .memory]
        case .pray:      return [.prayer, .bible, .music]
        case .create:    return [.image, .notes, .research]
        case .research:  return [.research, .factCheck, .bible, .compare]
        case .post:      return [.image, .notes, .context]
        case .summarize: return [.context, .factCheck, .notes]
        }
    }
}

// MARK: - C-4: Top-Bar Accessory Protocol

/// Any BAS component that can inject content into the adaptive top bar implements this.
@MainActor
protocol BASTopBarAccessoryProvider {
    associatedtype AccessoryContent: View
    @ViewBuilder func accessoryContent() -> AccessoryContent
    var accessibilityLabel: String { get }
}

// MARK: - C-5: Workspace Model

/// Role of the current user within a BAS workspace.
enum BASWorkspaceRole: String, Codable, CaseIterable {
    case owner
    case pastorAdmin
    case contributor
    case viewer
    case prayerOnly

    var canEditStudyNotes: Bool {
        switch self {
        case .owner, .pastorAdmin, .contributor: return true
        case .viewer, .prayerOnly: return false
        }
    }

    var canCreateContent: Bool {
        switch self {
        case .owner, .pastorAdmin, .contributor: return true
        case .viewer, .prayerOnly: return false
        }
    }

    var canManageMembers: Bool {
        switch self {
        case .owner, .pastorAdmin: return true
        case .contributor, .viewer, .prayerOnly: return false
        }
    }
}

/// Navigation tabs inside a BAS workspace.
enum BASWorkspaceTab: String, CaseIterable, Identifiable, Codable {
    case allContent
    case createdByYou
    case sharedWithYou
    case church
    case bibleStudies
    case sermons
    case prayerGroups
    case devotionals

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allContent:     return "All Content"
        case .createdByYou:   return "Created by You"
        case .sharedWithYou:  return "Shared with You"
        case .church:         return "Church"
        case .bibleStudies:   return "Bible Studies"
        case .sermons:        return "Sermons"
        case .prayerGroups:   return "Prayer Groups"
        case .devotionals:    return "Devotionals"
        }
    }
}

/// A BAS collaborative workspace. E2EE is always false (§7 — "Coming Soon" only).
struct BASWorkspace: Identifiable, Codable {
    let id: String
    var name: String
    var role: BASWorkspaceRole
    var tab: BASWorkspaceTab
    var isPrivate: Bool
    var createdBy: String
    var memberCount: Int
    /// §7: E2EE is coming soon — this value is always false in current builds.
    var isEncrypted: Bool = false
}

// MARK: - C-6: Safety Audit

/// Severity of a safety audit finding.
enum BASSeverityLevel: String, Codable {
    case info
    case advisory
    case blocking
}

/// Enforcement policy for a safety audit. Default is advisory (§7).
enum BASSafetyPolicy: String, Codable {
    /// Advisory: user is shown context, "Share anyway" is ALWAYS available.
    case advisory
    /// Blocking: reserved for crisis/minors/legal — not activated without human approval.
    case blocking
}

/// The specific checks Berean runs before surfacing or sharing AI output.
enum BASAuditCheckKind: String, CaseIterable, Codable {
    case scriptureAccuracy
    case verseInContext
    case translationMatch
    case theologicalConfidence
    case harmfulAdvice
    case manipulativeClaim
    case misquote
    case interpretationLabel
}

/// Result of a single audit check.
struct BASSafetyAuditResult: Identifiable {
    let id: UUID
    let check: BASAuditCheckKind
    let passed: Bool
    let severity: BASSeverityLevel
    let note: String?
}

/// Full safety audit for a BAS response. Default policy is advisory (§7).
struct BASSafetyAudit {
    var results: [BASSafetyAuditResult]
    /// §7: Default policy is always .advisory. "Share anyway" must remain available.
    var policy: BASSafetyPolicy = .advisory
    var isInterpretation: Bool = false

    /// True when there are no unresolved .blocking-severity failures.
    /// Advisory failures never block sharing.
    var overallPassed: Bool {
        guard policy == .blocking else { return true }
        return !results.contains { !$0.passed && $0.severity == .blocking }
    }
}

// MARK: - C-7: Connected Apps

/// First-party and third-party apps connectable to the Berean Agent Surface.
enum BASConnectedAppID: String, CaseIterable, Identifiable, Codable {
    case appleMusic
    case spotify
    case bibleDotCom
    case calendar
    case notes
    case churchProfile
    case files
    case giving
    case messages

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMusic:    return "Apple Music"
        case .spotify:       return "Spotify"
        case .bibleDotCom:   return "Bible.com"
        case .calendar:      return "Calendar"
        case .notes:         return "Notes"
        case .churchProfile: return "Church Profile"
        case .files:         return "Files"
        case .giving:        return "Giving"
        case .messages:      return "Messages"
        }
    }

    /// SF Symbol name for this app's icon.
    var iconToken: String {
        switch self {
        case .appleMusic:    return "music.note.list"
        case .spotify:       return "headphones.circle.fill"
        case .bibleDotCom:   return "text.book.closed.fill"
        case .calendar:      return "calendar"
        case .notes:         return "note.text"
        case .churchProfile: return "building.columns.fill"
        case .files:         return "folder.fill"
        case .giving:        return "dollarsign.circle.fill"
        case .messages:      return "message.fill"
        }
    }

    /// Default scope for this app. §7: giving and messages are always .never_.
    var defaultScope: BASScopeMode {
        switch self {
        case .appleMusic, .spotify, .bibleDotCom, .notes, .churchProfile:
            return .readOnly
        case .calendar, .files:
            return .askEveryTime
        case .giving, .messages:
            return .never_   // §7 — finance + private messaging read-only / disabled
        }
    }

    /// Whether this app handles sensitive data (finance or private messages).
    var isSensitive: Bool {
        switch self {
        case .giving, .messages: return true
        default: return false
        }
    }
}

/// A concrete connected-app instance with its current enabled state and scope.
struct BASConnectedApp: Identifiable {
    let id: BASConnectedAppID
    var currentScope: BASScopeMode
    var isEnabled: Bool
}

/// Registry of all BAS connected apps.
@Observable
@MainActor
final class BASConnectedAppsRegistry {

    static let shared = BASConnectedAppsRegistry()

    private(set) var apps: [BASConnectedApp]

    private init() {
        apps = BASConnectedAppID.allCases.map { appID in
            BASConnectedApp(
                id: appID,
                currentScope: appID.defaultScope,
                // §7: giving and messages start disabled
                isEnabled: appID.defaultScope != .never_
            )
        }
    }

    func setEnabled(_ enabled: Bool, for id: BASConnectedAppID) {
        // §7: giving and messages may NEVER be enabled by agent code
        guard id.defaultScope != .never_ else { return }
        guard let idx = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[idx].isEnabled = enabled
    }
}

// MARK: - BAS Design Tokens

extension Color {
    /// Warm parchment background — the primary page surface for Berean Agent.
    /// Hex F7F0E3: a warm cream that reads cleanly in light mode; dark-mode surface
    /// falls back to system adaptive layering in Wave 1+ views.
    static var basWarmPaper: Color { Color(hex: "F7F0E3") }

    /// Wine-red accent — used at most once per screen per §2.
    /// Hex 6B2137: a deep, warm burgundy readable at WCAG AA contrast.
    static var basWineRed: Color { Color(hex: "6B2137") }

    /// Tan card surface — one step elevated above warm paper.
    /// Hex E8D9C0: a toasted parchment tone for glass-adjacent cards.
    static var basTan: Color { Color(hex: "E8D9C0") }

    /// Near-black warm ink — primary text on warm paper.
    /// Hex 1C1008: a very dark warm brown that avoids harsh true-black.
    static var basInk: Color { Color(hex: "1C1008") }
}

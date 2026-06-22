// AmenInteractionFoundation.swift
// AMENAPP — Phase B interaction foundation (from the §13 interaction audit).
//
// Single source of truth for two cross-cutting concerns the audit surfaced
// repeatedly across surfaces:
//   • ToastCoordinator — one app-wide toast queue. Motivated by the pervasive
//     "silent failure" finding (try? / catch { dlog } / errorMessage never
//     rendered). Lightweight feedback belongs here, not in a full modal.
//   • ModalCoordinator — one-active-at-a-time modal arbitration. Motivated by
//     the modal-stacking / recursive-sheet findings (e.g. related-content
//     sheets stacking indefinitely; paywall-behind-permission conflicts).
//   • AmenInteractionStateMachine — the reusable button/control lifecycle from
//     §4, with valid-transition enforcement so UI never desyncs from backend.
//
// This file is pure infrastructure: it changes no behavior until a surface
// consumes it (Phase C). It depends only on SwiftUI/Foundation so it compiles
// in isolation. Names are unique app-wide (verified — no shadowing).

import SwiftUI

// MARK: - Interaction State Machine (§4)

/// The lifecycle every critical/animated control moves through.
/// Invalid transitions are ignored safely (never crash, never desync).
public enum AmenInteractionState: String, Equatable, Sendable {
    case idle
    case pressed
    case expanding
    case expanded
    case loading
    case success
    case failed
    case disabled
    case collapsing
    case cancelled

    /// The states this state may legally transition to.
    var allowedNext: Set<AmenInteractionState> {
        switch self {
        case .idle:       return [.pressed, .loading, .disabled, .expanding]
        case .pressed:    return [.expanding, .loading, .idle, .cancelled, .disabled]
        case .expanding:  return [.expanded, .cancelled, .collapsing]
        case .expanded:   return [.loading, .collapsing, .cancelled, .idle]
        case .loading:    return [.success, .failed, .cancelled]
        case .success:    return [.idle, .collapsing]
        case .failed:     return [.idle, .loading, .collapsing]      // retry allowed
        case .disabled:   return [.idle]
        case .collapsing: return [.idle, .cancelled]
        case .cancelled:  return [.idle]
        }
    }

    var isTerminalForGesture: Bool { self == .idle || self == .disabled }
}

/// Observable driver for a single control's interaction lifecycle.
/// Reset on view disappear so animation state never outlives the view (§4).
@MainActor
public final class AmenInteractionStateMachine: ObservableObject {
    @Published public private(set) var state: AmenInteractionState = .idle

    public init(initial: AmenInteractionState = .idle) {
        self.state = initial
    }

    /// Attempt a transition. Returns true if it was legal and applied.
    /// Illegal transitions are ignored (logged in DEBUG), never fatal.
    @discardableResult
    public func transition(to next: AmenInteractionState) -> Bool {
        guard state.allowedNext.contains(next) else {
            #if DEBUG
            print("⚠️ AmenInteractionStateMachine: ignored illegal \(state.rawValue) → \(next.rawValue)")
            #endif
            return false
        }
        state = next
        return true
    }

    /// Hard reset — call from `.onDisappear`.
    public func reset() { state = .idle }

    public var isBusy: Bool { state == .loading || state == .expanding || state == .collapsing }
}

// MARK: - Toast Coordinator

public struct AmenToastModel: Identifiable, Equatable {
    public enum Kind: Equatable {
        case info       // neutral
        case success    // green = state/status (two-accent contract)
        case failure    // calm, non-punitive — never playful on errors
    }
    public let id = UUID()
    public let kind: Kind
    public let message: String
    public let actionTitle: String?

    public init(kind: Kind, message: String, actionTitle: String? = nil) {
        self.kind = kind
        self.message = message
        self.actionTitle = actionTitle
    }

    public static func == (lhs: AmenToastModel, rhs: AmenToastModel) -> Bool { lhs.id == rhs.id }
}

/// App-wide single toast queue. Use for lightweight feedback (success, recoverable
/// failure) instead of a modal. Replaces the scattered silent-failure pattern.
@MainActor
public final class ToastCoordinator: ObservableObject {
    public static let shared = ToastCoordinator()

    @Published public private(set) var current: AmenToastModel?
    private var queue: [AmenToastModel] = []
    private var dismissTask: Task<Void, Never>?
    private let visibleDuration: Duration = .seconds(3)

    private init() {}

    public func show(_ toast: AmenToastModel) {
        if current == nil {
            present(toast)
        } else if current != toast {
            queue.append(toast)
        }
    }

    /// Convenience for the most common case the audit calls for.
    public func failure(_ message: String, actionTitle: String? = nil) {
        show(AmenToastModel(kind: .failure, message: message, actionTitle: actionTitle))
    }

    public func success(_ message: String) {
        show(AmenToastModel(kind: .success, message: message))
    }

    public func dismissCurrent() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        if !queue.isEmpty {
            present(queue.removeFirst())
        }
    }

    private func present(_ toast: AmenToastModel) {
        current = toast
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: self?.visibleDuration ?? .seconds(3))
            guard !Task.isCancelled else { return }
            self?.dismissCurrent()
        }
    }
}

// MARK: - Modal Coordinator

/// The kinds of exclusive surfaces the app may show. Only ONE may be active at a
/// time (§4): no modal stacking, no sheet-behind-alert, no paywall/permission
/// conflict, no recursive sheet-over-sheet.
public enum AmenModalKind: Equatable, Identifiable {
    case sheet(id: String)
    case alert(id: String)
    case paywall(id: String)
    case permission(id: String)
    case destructiveConfirm(id: String)

    public var id: String {
        switch self {
        case .sheet(let id):              return "sheet:\(id)"
        case .alert(let id):              return "alert:\(id)"
        case .paywall(let id):            return "paywall:\(id)"
        case .permission(let id):         return "permission:\(id)"
        case .destructiveConfirm(let id): return "confirm:\(id)"
        }
    }
}

/// Arbitrates exclusive modal presentation app-wide. A request while something is
/// already presented is rejected (returns false) rather than stacked. Navigation
/// should call `reset()` so a stale modal can't survive a route change.
@MainActor
public final class ModalCoordinator: ObservableObject {
    public static let shared = ModalCoordinator()

    @Published public private(set) var active: AmenModalKind?

    private init() {}

    /// Request to present. Returns false if another modal is already active.
    @discardableResult
    public func present(_ kind: AmenModalKind) -> Bool {
        guard active == nil else {
            #if DEBUG
            print("⚠️ ModalCoordinator: rejected \(kind.id) — \(active!.id) already active")
            #endif
            return false
        }
        active = kind
        return true
    }

    /// Dismiss only if `kind` is the active one (prevents racing dismissals).
    public func dismiss(_ kind: AmenModalKind) {
        if active == kind { active = nil }
    }

    public func dismissActive() { active = nil }

    /// Clear on navigation so no hidden modal Boolean is left true (§4).
    public func reset() { active = nil }

    public var isPresenting: Bool { active != nil }
}

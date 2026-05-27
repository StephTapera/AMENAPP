import Foundation

// MARK: - ActionChipBarViewModel

/// Drives `ActionChipBar` by resolving which chips are available for a given
/// profile. Cancels any in-flight resolution when a new `start()` call arrives.
///
/// Typical lifecycle (called from the parent Profile view):
/// ```swift
/// .task { await viewModel.start() }
/// .onDisappear { viewModel.stop() }
/// ```
@MainActor
@Observable
public final class ActionChipBarViewModel {

    // MARK: Configuration (set before calling start())

    public var targetUserId: String
    public var roleFlags: ProfileRoleFlags
    public var bereanAboutOptIn: Bool
    public var linksStore: ProfileLinksStore?
    public var viewerIsOwner: Bool

    // MARK: Output

    public private(set) var resolvedChips: [any ActionChip] = []
    public private(set) var isResolving = false

    // MARK: Private

    private let resolver = ActionChipResolver()
    private var resolveTask: Task<Void, Never>?

    // MARK: Init

    public init(
        targetUserId: String,
        roleFlags: ProfileRoleFlags? = nil,
        bereanAboutOptIn: Bool = false,
        linksStore: ProfileLinksStore? = nil,
        viewerIsOwner: Bool = false
    ) {
        self.targetUserId = targetUserId
        self.roleFlags = roleFlags ?? ProfileRoleFlags()
        self.bereanAboutOptIn = bereanAboutOptIn
        self.linksStore = linksStore
        self.viewerIsOwner = viewerIsOwner
    }

    // MARK: Public API

    /// Kicks off an async resolution pass. Cancels any previous in-flight task.
    public func start() {
        stop()
        resolveTask = Task { await resolve() }
    }

    /// Cancels any in-flight resolution task. Call from `.onDisappear`.
    public func stop() {
        resolveTask?.cancel()
        resolveTask = nil
    }

    // MARK: Private

    /// Runs availability checks concurrently and updates `resolvedChips`.
    public func resolve() async {
        guard !Task.isCancelled else { return }
        isResolving = true
        defer { isResolving = false }

        let chips = await resolver.resolve(
            targetUserId: targetUserId,
            roleFlags: roleFlags,
            bereanAboutOptIn: bereanAboutOptIn,
            linksStore: linksStore,
            viewerIsOwner: viewerIsOwner
        )

        guard !Task.isCancelled else { return }
        resolvedChips = chips
    }
}

// AmenActionPillContainer.swift
// AMEN App — CommunityOS / ActionPill
//
// Phase 2 — Agent A18 (Universal Action Pill)
// ViewModifier that attaches AmenActionPillView to any content view.
//
// Handles:
//   • Local actions (save, followUp) — toggle without opening composer
//   • Intent-based actions — build PillComposerSource + present AmenUniversalComposer
//   • Placement (bottomTrailing / bottomLeading / bottomCenter)
//
// Design rules:
//   • System semantic colors only (no custom hex, no amenGold)
//   • No view/like/reaction counts exposed at any layer
//   • AmenUniversalComposer (A3) is the only creation surface wired here
//
// NOTE: `PillComposerSource` is a lightweight routing struct local to the ActionPill layer.
//       The full `ComposerSource` type (with ComposerSourceType, prefillText, etc.) lives in
//       CommunityOS/Composer/AmenComposerModels.swift. Unify when A18 and A3 are merged
//       into a single composer coordinator.
//
// Cross-reference:
//   AmenActionPillModel.swift    — model + PillAction definitions
//   AmenActionPillView.swift     — the actual pill widget
//   AmenUniversalComposer.swift  — creation sheet (A3, string-API)
//   AmenComposerModels.swift     — canonical ComposerSource / ComposerConfig (A3 full models)
//   CommunityObjectTypes.swift   — AmenObjectType, AmenIntent

import SwiftUI

// MARK: - PillComposerSource

/// Lightweight routing payload passed from the pill to the caller and to
/// `AmenUniversalComposer` when an intent-based pill action is tapped.
///
/// Uses the string-API of `AmenUniversalComposer` (sourceRef / sourceType / initialIntent)
/// rather than the richer `ComposerSource` model in `AmenComposerModels.swift`, to avoid
/// a hard dependency on the Composer sub-module from the ActionPill layer.
///
/// OPEN: Unify with `ComposerSource` in `AmenComposerModels.swift` when A18 + A3
///       are merged into a single composer coordinator.
struct PillComposerSource: Sendable {
    /// Firestore document path of the source object (e.g. `"posts/abc123"`).
    let objectRef: String
    /// `AmenObjectType.rawValue` of the source object.
    let objectType: String
    /// `AmenIntent.rawValue` to pre-select in `AmenUniversalComposer`.
    let intentRawValue: String
}

// MARK: - AmenActionPillContainer

/// ViewModifier that overlays `AmenActionPillView` at the specified corner of any content.
///
/// Usage via the `.amenActionPill(...)` extension:
/// ```swift
/// PostCardView(post: post)
///     .amenActionPill(
///         model: AmenActionPillModel(
///             objectType: .post,
///             objectRef: "posts/\(post.id)",
///             objectOwnerId: post.authorId,
///             currentUserId: currentUser.id,
///             isSaved: post.isSaved,
///             isFollowedUp: false
///         ),
///         onSave: { saved in viewModel.setSaved(saved) }
///     )
/// ```
struct AmenActionPillContainer: ViewModifier {

    // MARK: Inputs

    /// Object model — determines which actions are shown.
    let model: AmenActionPillModel

    /// Corner / edge to anchor the pill.
    var placement: PillPlacement = .bottomTrailing

    /// `true` when the pill sits over a hero photo (dark translucent glass style).
    var onPhotoBackground: Bool = false

    /// Called when the user saves or un-saves the object.
    var onSave: (_ saved: Bool) -> Void = { _ in }

    /// Called for intent-based actions before the composer sheet opens.
    /// Receives the tapped `PillAction` and the resolved `PillComposerSource`.
    /// Default is a no-op; composer still auto-presents.
    var onCompose: (_ action: PillAction, _ source: PillComposerSource) -> Void = { _, _ in }

    // MARK: Placement

    enum PillPlacement: Sendable {
        case bottomTrailing
        case bottomLeading
        case bottomCenter
    }

    // MARK: State

    @State private var isSaved: Bool
    @State private var isFollowedUp: Bool
    @State private var showComposer: Bool = false
    @State private var pendingSource: PillComposerSource? = nil

    // MARK: Computed — live model reflecting current toggle state

    private var liveModel: AmenActionPillModel {
        var m = model
        m.isSaved = isSaved
        m.isFollowedUp = isFollowedUp
        return m
    }

    // MARK: Init

    init(
        model: AmenActionPillModel,
        placement: PillPlacement = .bottomTrailing,
        onPhotoBackground: Bool = false,
        onSave: @escaping (Bool) -> Void = { _ in },
        onCompose: @escaping (PillAction, PillComposerSource) -> Void = { _, _ in }
    ) {
        self.model = model
        self.placement = placement
        self.onPhotoBackground = onPhotoBackground
        self.onSave = onSave
        self.onCompose = onCompose
        self._isSaved = State(initialValue: model.isSaved)
        self._isFollowedUp = State(initialValue: model.isFollowedUp)
    }

    // MARK: Body

    func body(content: Content) -> some View {
        content
            .overlay(alignment: overlayAlignment) {
                AmenActionPillView(
                    model: liveModel,
                    onPhotoBackground: onPhotoBackground,
                    onAction: handleAction
                )
                .padding(pillEdgePadding)
            }
            .sheet(isPresented: $showComposer) {
                if let src = pendingSource {
                    composerSheet(source: src)
                }
            }
    }

    // MARK: - Action Handler

    private func handleAction(_ action: PillAction) {
        switch action {

        case .save:
            // Local toggle — no composer
            let newValue = !isSaved
            withAnimation(.easeOut(duration: 0.18)) {
                isSaved = newValue
            }
            UINotificationFeedbackGenerator().notificationOccurred(newValue ? .success : .warning)
            onSave(newValue)

        case .followUp:
            // Local toggle — no composer
            let newValue = !isFollowedUp
            withAnimation(.easeOut(duration: 0.18)) {
                isFollowedUp = newValue
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        case .more:
            // Internal expansion sentinel handled inside AmenActionPillView; never reaches here
            break

        default:
            // Intent-based action — build PillComposerSource and present AmenUniversalComposer
            guard let intentRaw = action.intentRawValue else { return }
            let src = PillComposerSource(
                objectRef: model.objectRef,
                objectType: model.objectType.rawValue,
                intentRawValue: intentRaw
            )
            onCompose(action, src)
            pendingSource = src
            showComposer = true
        }
    }

    // MARK: - Composer Sheet

    @ViewBuilder
    private func composerSheet(source: PillComposerSource) -> some View {
        // Wires to AmenUniversalComposer (A3) string-API.
        // When A3 migrates to ComposerConfig fully, update this to use
        // ComposerConfig.config(for:) from AmenComposerModels.swift.
        AmenUniversalComposer(
            sourceRef: source.objectRef,
            sourceType: source.objectType,
            initialIntent: source.intentRawValue,
            isPresented: $showComposer
        )
    }

    // MARK: - Layout Helpers

    private var overlayAlignment: Alignment {
        switch placement {
        case .bottomTrailing: return .bottomTrailing
        case .bottomLeading:  return .bottomLeading
        case .bottomCenter:   return .bottom
        }
    }

    private var pillEdgePadding: EdgeInsets {
        switch placement {
        case .bottomTrailing:
            return EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 16)
        case .bottomLeading:
            return EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 0)
        case .bottomCenter:
            return EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
        }
    }
}

// MARK: - View Extension

extension View {

    /// Attaches an `AmenActionPillView` overlay to any view.
    ///
    /// - Parameters:
    ///   - model: The resolved `AmenActionPillModel` for the displayed object.
    ///   - placement: Where to anchor the pill (default `.bottomTrailing`).
    ///   - onPhotoBackground: Pass `true` when the pill floats over a hero photo.
    ///   - onSave: Called with the new `isSaved` bool when the user taps Save.
    ///   - onCompose: Called with the `PillAction` + `PillComposerSource` before
    ///     the composer sheet opens. Composer auto-presents regardless unless you
    ///     build a custom container that omits the sheet.
    func amenActionPill(
        model: AmenActionPillModel,
        placement: AmenActionPillContainer.PillPlacement = .bottomTrailing,
        onPhotoBackground: Bool = false,
        onSave: @escaping (Bool) -> Void = { _ in },
        onCompose: @escaping (PillAction, PillComposerSource) -> Void = { _, _ in }
    ) -> some View {
        modifier(
            AmenActionPillContainer(
                model: model,
                placement: placement,
                onPhotoBackground: onPhotoBackground,
                onSave: onSave,
                onCompose: onCompose
            )
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Container — Post card") {
    ScrollView {
        VStack(spacing: 32) {
            // Standard card, bottom-trailing
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .frame(height: 200)
                .overlay {
                    Text("Post Card Content")
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .label))
                }
                .amenActionPill(
                    model: AmenActionPillModel(
                        objectType: .post,
                        objectRef: "posts/preview1",
                        objectOwnerId: "uid_owner",
                        currentUserId: "uid_viewer",
                        isSaved: false,
                        isFollowedUp: false
                    ),
                    placement: .bottomTrailing,
                    onSave: { saved in print("saved: \(saved)") }
                )

            // Over-photo — bottom-center
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.5), .purple.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 240)
                Text("Hero Photo")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .amenActionPill(
                model: AmenActionPillModel(
                    objectType: .event,
                    objectRef: "events/preview2",
                    objectOwnerId: "uid_owner",
                    currentUserId: "uid_viewer",
                    isSaved: false,
                    isFollowedUp: false
                ),
                placement: .bottomCenter,
                onPhotoBackground: true
            )

            // Church profile — bottom-leading
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .frame(height: 160)
                .overlay {
                    Text("Church Profile")
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .label))
                }
                .amenActionPill(
                    model: AmenActionPillModel(
                        objectType: .church,
                        objectRef: "churches/preview3",
                        objectOwnerId: "uid_owner",
                        currentUserId: "uid_viewer",
                        isSaved: true,
                        isFollowedUp: false
                    ),
                    placement: .bottomLeading
                )
        }
        .padding(24)
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif

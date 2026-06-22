// AmenMediaSessionView.swift
// AMENAPP
//
// Finite media session viewer — the anti-doomscroll media experience.
// Sessions have a known end. No infinite autoplay. No variable reward loops.
// Healthy stopping points, reflection checkpoints, and intentional continuation.
//
// Gated by AMENFeatureFlags.shared.mediaFiniteSessionsEnabled

import SwiftUI
import Combine

// MARK: - MediaSession Stubs

enum MediaSessionCheckpointReason {
    case itemsWatched
    case timeElapsed
    case rapidSkipping
}

struct MediaSessionCheckpoint: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let options: [CheckpointOption]

    struct CheckpointOption: Identifiable {
        let id = UUID()
        let label: String
        let icon: String
        let action: CheckpointAction
    }

    enum CheckpointAction {
        case `continue`, reflect, journal, discuss, save, endSession
    }

    static func checkpoint(for reason: MediaSessionCheckpointReason) -> MediaSessionCheckpoint {
        switch reason {
        case .itemsWatched:
            return MediaSessionCheckpoint(
                title: "Taking it in?",
                message: "You've watched a few items. How are you feeling?",
                options: [
                    CheckpointOption(label: "Keep watching", icon: "play.fill", action: .continue),
                    CheckpointOption(label: "Reflect", icon: "moon.stars", action: .reflect),
                    CheckpointOption(label: "I'm done", icon: "xmark", action: .endSession),
                ]
            )
        case .timeElapsed:
            return MediaSessionCheckpoint(
                title: "Still with us?",
                message: "You've been watching for a while. Take a moment to pause.",
                options: [
                    CheckpointOption(label: "Continue", icon: "play.fill", action: .continue),
                    CheckpointOption(label: "Journal", icon: "square.and.pencil", action: .journal),
                    CheckpointOption(label: "End session", icon: "xmark", action: .endSession),
                ]
            )
        case .rapidSkipping:
            return MediaSessionCheckpoint(
                title: "Slowing down?",
                message: "You're moving through content quickly. Try pausing on something.",
                options: [
                    CheckpointOption(label: "Keep going", icon: "play.fill", action: .continue),
                    CheckpointOption(label: "Discuss", icon: "bubble.left.and.bubble.right", action: .discuss),
                    CheckpointOption(label: "End session", icon: "xmark", action: .endSession),
                ]
            )
        }
    }
}

// MARK: - AmenMediaSession Extensions

extension AmenMediaSession {
    var isComplete: Bool { status == .completed || status == .abandoned }
}

extension AmenMediaSession.SessionType {
    var systemIcon: String {
        switch self {
        case .morningInspiration: return "sunrise.fill"
        case .friendsAndFamily:   return "person.2.fill"
        case .creativeDiscovery:  return "sparkles"
        case .worshipAndMusic:    return "music.note"
        case .learningSession:    return "book.fill"
        case .sermonHighlights:   return "mic.fill"
        case .selahReflection:    return "moon.stars.fill"
        case .testimonies:        return "person.fill.checkmark"
        case .churchMoments:      return "building.columns.fill"
        case .encouragement:      return "heart.fill"
        case .custom:             return "slider.horizontal.3"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class AmenMediaSessionViewModel: ObservableObject {

    // MARK: Published State

    @Published private(set) var session: AmenMediaSession
    @Published private(set) var currentMediaId: String?
    @Published var checkpoint: MediaSessionCheckpoint?
    @Published var showCompletionView = false
    @Published var isLoading = false
    @Published var error: String?

    // MARK: Private

    private var checkpointTimer: AnyCancellable?
    private let startedAt: Date = Date()
    private var rapidSkipCount = 0
    private var lastSkipDate = Date.distantPast

    // MARK: Flags

    private var checkpointsEnabled: Bool { AMENFeatureFlags.shared.mediaSessionCheckpointsEnabled }
    private var completionReflectionEnabled: Bool { AMENFeatureFlags.shared.mediaCompletionReflectionEnabled }
    private var doomScrollGuardEnabled: Bool { AMENFeatureFlags.shared.mediaDoomScrollGuardEnabled }

    // MARK: Init

    init(session: AmenMediaSession) {
        self.session = session
        self.currentMediaId = session.itemIds.first
        startCheckpointTimer()
    }

    // MARK: Navigation

    func advance() {
        guard !session.isComplete else {
            onSessionEnd()
            return
        }
        let next = session.currentIndex + 1
        if next >= session.itemIds.count {
            onSessionEnd()
            return
        }
        session.currentIndex = next
        currentMediaId = session.itemIds[safe: next]
        AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "media_advance"))
        evaluateCheckpointNeeded(reason: .itemsWatched)
    }

    func previous() {
        guard session.currentIndex > 0 else { return }
        session.currentIndex -= 1
        currentMediaId = session.itemIds[safe: session.currentIndex]
    }

    func skip() {
        let now = Date()
        if now.timeIntervalSince(lastSkipDate) < 3 { rapidSkipCount += 1 } else { rapidSkipCount = 0 }
        lastSkipDate = now
        if doomScrollGuardEnabled && rapidSkipCount >= 3 {
            rapidSkipCount = 0
            triggerCheckpoint(.rapidSkipping)
        } else {
            advance()
        }
    }

    // MARK: Checkpoint Logic

    func continueAfterCheckpoint() {
        checkpoint = nil
        advance()
    }

    func endSessionFromCheckpoint() {
        checkpoint = nil
        onSessionEnd()
    }

    func reflectFromCheckpoint() {
        checkpoint = nil
        AMENAnalyticsService.shared.track(.feedReflectionPromptEngaged)
    }

    func triggerCheckpoint(_ reason: MediaSessionCheckpointReason) {
        guard checkpointsEnabled else { advance(); return }
        withAnimation(.amenSpringStandard) {
            checkpoint = MediaSessionCheckpoint.checkpoint(for: reason)
        }
        AMENAnalyticsService.shared.track(.feedPacingPromptShown)
    }

    // MARK: Session End

    func onSessionEnd() {
        guard completionReflectionEnabled else { return }
        session.status = .completed
        withAnimation(.amenEaseQuick) {
            showCompletionView = true
        }
        AMENAnalyticsService.shared.track(.feedSessionEnded(durationMinutes: Date().timeIntervalSince(startedAt) / 60, qualityScore: 0.8))
    }

    // MARK: Timer

    private func startCheckpointTimer() {
        guard checkpointsEnabled else { return }
        checkpointTimer = Timer.publish(every: 480, on: .main, in: .common)  // 8 min
            .autoconnect()
            .sink { [weak self] _ in
                self?.evaluateCheckpointNeeded(reason: .timeElapsed)
            }
    }

    private func evaluateCheckpointNeeded(reason: MediaSessionCheckpointReason) {
        guard checkpointsEnabled, checkpoint == nil else { return }
        switch reason {
        case .itemsWatched where session.currentIndex > 0 && session.currentIndex % 3 == 0:
            triggerCheckpoint(.itemsWatched)
        case .timeElapsed:
            triggerCheckpoint(.timeElapsed)
        default:
            break
        }
    }
}

// subscript(safe:) — canonical definition in SafeSubscriptExtension.swift

// MARK: - AmenMediaSessionView

struct AmenMediaSessionView: View {
    @StateObject private var vm: AmenMediaSessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dismiss) private var dismiss
    @State private var showReflectionSheet = false

    let onReflect: (() -> Void)?
    let onJournal: (() -> Void)?
    let onDiscuss: (() -> Void)?

    init(
        session: AmenMediaSession,
        onReflect: (() -> Void)? = nil,
        onJournal: (() -> Void)? = nil,
        onDiscuss: (() -> Void)? = nil
    ) {
        _vm = StateObject(wrappedValue: AmenMediaSessionViewModel(session: session))
        self.onReflect = onReflect
        self.onJournal = onJournal
        self.onDiscuss = onDiscuss
    }

    var body: some View {
        ZStack {
            // Main player surface
            sessionPlayerBody

            // Checkpoint overlay
            if let checkpoint = vm.checkpoint {
                checkpointOverlay(checkpoint)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }

            // Completion overlay
            if vm.showCompletionView {
                sessionCompletionView
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .ignoresSafeArea(edges: .top)
        .animation(reduceMotion ? nil : .amenEaseQuick, value: vm.checkpoint != nil)
        .animation(reduceMotion ? nil : .amenEaseQuick, value: vm.showCompletionView)
        .sheet(isPresented: $showReflectionSheet) {
            AmenMediaReflectionSheet(
                mediaId: vm.currentMediaId,
                sessionId: vm.session.id,
                mediaTitle: nil,
                sessionIntent: vm.session.sessionType.displayName,
                onSaved: { showReflectionSheet = false },
                onAddToJournal: { text in
                    showReflectionSheet = false
                    onJournal?()
                }
            )
        }
    }

    // MARK: Session Player

    private var sessionPlayerBody: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Session progress header
                sessionHeader

                // Media area — flat and opaque, no glass here
                mediaArea
                    .frame(maxHeight: .infinity)

                // Bottom spacer so media content does not hide under the floating dock
                Color.clear.frame(height: 104)
            }
            .background(Color(.systemBackground))

            // Floating glass control dock — chrome only, floats above media
            sessionControlDock
        }
    }

    // MARK: Session Header

    private var sessionHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background {
                        if reduceTransparency { Circle().fill(Color(.systemBackground)) }
                    }
                    .amenGlassEffect(in: Circle())
            }
            .accessibilityLabel("Close session")

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.session.sessionType.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Item \(vm.session.currentIndex + 1) of \(vm.session.itemIds.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Progress indicator
            SessionProgressCapsule(
                current: vm.session.currentIndex,
                total: vm.session.itemIds.count
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color(.systemBackground))
    }

    // MARK: Media Area

    private var mediaArea: some View {
        ZStack {
            if let postId = vm.currentMediaId {
                Color(.secondarySystemBackground)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.systemScaled(40, weight: .light))
                                .foregroundStyle(.secondary)
                            Text(postId)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    )
                    .id(postId)
            } else {
                Color(.systemBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .gesture(swipeGesture)
    }

    // MARK: Swipe Gesture (within finite queue only)

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                if value.translation.height < -60 {
                    vm.skip()   // swipe up = skip
                } else if value.translation.height > 60 {
                    vm.previous()  // swipe down = previous
                }
            }
    }

    // MARK: Control Dock (Floating Glass — iOS 26)
    //
    // Glass is applied to the chrome (buttons + capsule pill) only.
    // The media content area behind this dock remains flat and opaque.
    // reduceTransparency → solid fill fallback via GlassEffectContainer's
    // built-in system behaviour; no manual branching needed.

    private var sessionControlDock: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {

                // Previous
                Button {
                    vm.previous()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "chevron.up")
                            .font(.systemScaled(18, weight: .regular))
                        Text("Prev")
                            .font(.caption2)
                    }
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 52)
                }
                .amenGlassEffect()
                .accessibilityLabel("Previous item")
                .disabled(vm.session.currentIndex == 0)

                // Reflect
                Button {
                    vm.reflectFromCheckpoint()
                    if AMENFeatureFlags.shared.mediaReflectionSheetEnabled {
                        showReflectionSheet = true
                    } else {
                        onReflect?()
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "moon.stars.fill")
                            .font(.systemScaled(18, weight: .regular))
                        Text("Reflect")
                            .font(.caption2)
                    }
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                }
                .amenGlassEffect()
                .accessibilityLabel("Reflect on this item")

                // Save
                Button {
                    AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "save"))
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "bookmark.fill")
                            .font(.systemScaled(18, weight: .regular))
                        Text("Save")
                            .font(.caption2)
                    }
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 52)
                }
                .amenGlassEffect()
                .accessibilityLabel("Save this item")

                // End session
                Button {
                    vm.onSessionEnd()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.systemScaled(18, weight: .regular))
                        Text("End")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 52)
                }
                .amenGlassEffect()
                .accessibilityLabel("End session")

                // Next — intentional continuation pill
                nextButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
        .shadow(
            color: .black.opacity(reduceTransparency ? 0 : 0.14),
            radius: 24,
            x: 0,
            y: 10
        )
        // Show/hide uses .amenSpring per kit convention
        .animation(.amenSpringStandard, value: vm.session.currentIndex)
    }

    private var nextButton: some View {
        Button {
            vm.advance()
        } label: {
            HStack(spacing: 6) {
                Text("Next")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.systemScaled(13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(Color.black, in: Capsule())
        }
        .accessibilityLabel("Continue to next item")
        .disabled(vm.session.isComplete)
        // Next button is its own tappable region — no extra glassEffect layer on top of Capsule
    }

    // sessionAction helper kept for any future call sites; no longer used by the dock itself.
    private func sessionAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(20, weight: .regular))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Checkpoint Overlay

    private func checkpointOverlay(_ checkpoint: MediaSessionCheckpoint) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { } // absorbs taps

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Text(checkpoint.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        Text(checkpoint.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // Options
                    VStack(spacing: 10) {
                        ForEach(checkpoint.options) { option in
                            checkpointOptionButton(option, checkpoint: checkpoint)
                        }
                    }
                }
                .padding(24)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
    }

    private func checkpointOptionButton(_ option: MediaSessionCheckpoint.CheckpointOption, checkpoint: MediaSessionCheckpoint) -> some View {
        Button {
            switch option.action {
            case .continue:  vm.continueAfterCheckpoint()
            case .reflect:
                vm.reflectFromCheckpoint()
                if AMENFeatureFlags.shared.mediaReflectionSheetEnabled { showReflectionSheet = true }
                else { onReflect?() }
            case .journal:   vm.reflectFromCheckpoint(); onJournal?()
            case .discuss:   vm.reflectFromCheckpoint(); onDiscuss?()
            case .save:      AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "save"))
            case .endSession: vm.endSessionFromCheckpoint()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(option.action == .endSession ? .secondary : .primary)
                    .accessibilityHidden(true)
                Text(option.label)
                    .font(.subheadline.weight(option.action == .continue ? .semibold : .regular))
                    .foregroundStyle(option.action == .endSession ? .secondary : .primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                option.action == .continue
                    ? Color.black : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        option.action == .continue ? .clear : Color(.separator).opacity(0.5),
                        lineWidth: 0.5
                    )
            )
            .foregroundStyle(option.action == .continue ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
    }

    // MARK: Session Completion View

    private var sessionCompletionView: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // Completion icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.systemScaled(64, weight: .light))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                // Message
                VStack(spacing: 10) {
                    Text("Session complete")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("You watched \(vm.session.itemIds.count) items from \(vm.session.sessionType.displayName).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Reflection actions
                VStack(spacing: 12) {
                    completionAction(icon: "moon.stars.fill", title: "Reflect", subtitle: "Take a moment with what you watched") {
                        onReflect?()
                    }
                    completionAction(icon: "square.and.pencil", title: "Open Journal", subtitle: "Write down what stood out") {
                        onJournal?()
                    }
                    completionAction(icon: "bubble.left.and.bubble.right.fill", title: "Discuss", subtitle: "Talk about it with someone") {
                        onDiscuss?()
                    }
                }

                Spacer()

                // Exit
                Button("Done") {
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .accessibilityLabel("Close session and return to home")

                Spacer()
            }
            .padding(.horizontal, 28)
        }
    }

    private func completionAction(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.systemScaled(22, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(subtitle)")
    }
}

// MARK: - Session Progress Capsule

struct SessionProgressCapsule: View {
    let current: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(current + 1) / Double(total)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 80, height: 6)
            Capsule()
                .fill(Color.black)
                .frame(width: max(6, 80 * fraction), height: 6)
                .animation(.amenSpringStandard, value: current)
        }
        .accessibilityLabel("Progress: item \(current + 1) of \(total)")
        .accessibilityValue("\(Int(fraction * 100)) percent complete")
    }
}

// MARK: - Session Intent Picker

/// Shown before starting a session to let the user choose what kind of media experience they want.
struct AmenMediaSessionIntentPicker: View {
    let onSelect: (AmenMediaSession.SessionType) -> Void
    @Environment(\.dismiss) private var dismiss

    private let intentGrid: [AmenMediaSession.SessionType] = AmenMediaSession.SessionType.allCases

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(intentGrid, id: \.self) { sessionType in
                        MediaSessionIntentCard(type: sessionType) {
                            onSelect(sessionType)
                            dismiss()
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Start a session")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct MediaSessionIntentCard: View {
    let type: AmenMediaSession.SessionType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: type.systemIcon)
                    .font(.systemScaled(24, weight: .regular))
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(type.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(type.defaultMaxItems) items · \(type.defaultMaxItems * 2) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.displayName): \(type.defaultMaxItems) items, approximately \(type.defaultMaxItems * 2) minutes")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Media Session") {
    AmenMediaSessionView(
        session: AmenMediaSession(
            id: "session_demo",
            ownerUid: "uid_demo",
            sessionType: .morningInspiration,
            intent: "Morning encouragement",
            communityIds: [],
            itemIds: ["m1", "m2", "m3", "m4", "m5"],
            currentIndex: 0,
            status: .active,
            finiteQueue: true,
            maxItems: 5,
            maxDurationSeconds: 600,
            reflectionPromptShown: false,
            sourceSurface: "home"
        )
    )
}

#Preview("Intent Picker") {
    AmenMediaSessionIntentPicker(onSelect: { _ in })
}
#endif

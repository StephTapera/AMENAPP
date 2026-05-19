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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            checkpoint = MediaSessionCheckpoint.checkpoint(for: reason)
        }
        AMENAnalyticsService.shared.track(.feedPacingPromptShown)
    }

    // MARK: Session End

    func onSessionEnd() {
        guard completionReflectionEnabled else { return }
        session.status = .completed
        withAnimation(.easeOut(duration: 0.3)) {
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

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - AmenMediaSessionView

struct AmenMediaSessionView: View {
    @StateObject private var vm: AmenMediaSessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .animation(.easeOut(duration: 0.25), value: vm.checkpoint != nil)
        .animation(.easeOut(duration: 0.25), value: vm.showCompletionView)
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
        VStack(spacing: 0) {
            // Session progress header
            sessionHeader

            // Media area
            mediaArea
                .frame(maxHeight: .infinity)

            // Control dock
            sessionControlDock
        }
        .background(Color(.systemBackground))
    }

    // MARK: Session Header

    private var sessionHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial, in: Circle())
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
                AmenMediaDetailLoaderView(
                    postID: postId,
                    initialMediaIndex: 0,
                    sourceContext: .saved,
                    onClose: nil
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

    // MARK: Control Dock

    private var sessionControlDock: some View {
        HStack(spacing: 0) {
            // Previous
            sessionAction(icon: "chevron.up", label: "Previous") { vm.previous() }
                .disabled(vm.session.currentIndex == 0)

            Spacer()

            // Reflect
            sessionAction(icon: "moon.stars.fill", label: "Reflect") {
                vm.reflectFromCheckpoint()
                if AMENFeatureFlags.shared.mediaReflectionSheetEnabled {
                    showReflectionSheet = true
                } else {
                    onReflect?()
                }
            }

            Spacer()

            // Save
            sessionAction(icon: "bookmark.fill", label: "Save") {
                AMENAnalyticsService.shared.track(.feedMeaningfulInteraction(type: "save"))
            }

            Spacer()

            // End session
            sessionAction(icon: "xmark.circle", label: "End session") {
                vm.onSessionEnd()
            }

            Spacer()

            // Next (intentional continuation)
            nextButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var nextButton: some View {
        Button {
            vm.advance()
        } label: {
            HStack(spacing: 6) {
                Text("Next")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.black, in: Capsule())
        }
        .accessibilityLabel("Continue to next item")
        .disabled(vm.session.isComplete)
    }

    private func sessionAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
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
                    .font(.system(size: 16, weight: .medium))
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
                    .font(.system(size: 64, weight: .light))
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
                    .font(.system(size: 22, weight: .regular))
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
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: current)
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
                    .font(.system(size: 24, weight: .regular))
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

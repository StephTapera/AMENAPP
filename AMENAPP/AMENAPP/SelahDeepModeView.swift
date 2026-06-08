import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseAnalytics

// MARK: - Selah Deep Mode (Pause)
// Distraction-free contemplative experience. Surfaces a single moment
// with ambient gradients and a gentle reflection prompt.

struct SelahDeepModeView: View {
    let item: SelahMediaItem?
    let contextWindow: SelahContextWindow?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var reflectionText = ""
    @State private var showReflectionEntry = false
    @State private var savedToMemory = false
    @State private var ambientPhase = 0.0
    @State private var currentSession: LocalSelahSession?
    @FocusState private var reflectionFocused: Bool

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            ambientBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topControls

                if let item {
                    Spacer()
                    mediaFocus(item: item)
                    Spacer()
                    promptSection(item: item)
                    Spacer(minLength: 40)
                } else {
                    emptyPauseState
                }
            }
        }
        .onAppear {
            loadOrCreateSession()
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                ambientPhase = 1
            }
        }
        .onDisappear {
            pauseSessionIfActive()
        }
        .onChange(of: reflectionText) { _, newValue in
            currentSession?.updateReflection(newValue)
            try? modelContext.save()
        }
    }

    // MARK: - Subviews

    private var topControls: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .accessibilityLabel("Exit Pause mode")
            Spacer()
            Label("Pause", systemImage: "moon.stars")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func mediaFocus(item: SelahMediaItem) -> some View {
        VStack(spacing: 20) {
            // Media thumbnail or scripture
            ZStack {
                if !item.mediaURL.isEmpty {
                    AsyncImage(url: URL(string: item.mediaURL)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 280, height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                                .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
                        } else {
                            meditationPlaceholder
                        }
                    }
                } else {
                    meditationPlaceholder
                }
            }

            // Scripture anchor
            if let ref = item.scriptureRef, !ref.isEmpty {
                Text(ref)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
            }

            // Caption in contemplative style
            if !item.caption.isEmpty {
                Text(item.caption)
                    .font(.title3.weight(.light))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 32)
                    .lineSpacing(4)
            }
        }
    }

    private var meditationPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.4), Color.purple.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 280, height: 280)
            Image(systemName: "moon.stars.fill")
                .font(.systemScaled(64, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func promptSection(item: SelahMediaItem) -> some View {
        VStack(spacing: 16) {
            let prompt = contextPrompt(for: item)
            Text(prompt)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            if showReflectionEntry {
                TextEditor(text: $reflectionText)
                    .frame(height: 100)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .padding(.horizontal, 24)
                    .focused($reflectionFocused)
                    .onAppear { reflectionFocused = true }

                HStack(spacing: 16) {
                    Button("Cancel") {
                        showReflectionEntry = false
                        reflectionText = ""
                        currentSession?.updateReflection("")
                        currentSession?.pause()
                        try? modelContext.save()
                    }
                    .foregroundStyle(.secondary)

                    Button("Save to Memory") {
                        saveReflectionAsMemory(item: item)
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.purple))
                    .disabled(reflectionText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else if savedToMemory {
                Label("Saved to Memory", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                HStack(spacing: 16) {
                    Button {
                        showReflectionEntry = true
                    } label: {
                        Label("Reflect", systemImage: "pencil.line")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.purple.opacity(0.8)))
                    }

                    Button {
                        saveToMemoryDirectly(item: item)
                    } label: {
                        Label("Remember", systemImage: "brain")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.purple.opacity(0.12)))
                    }
                }
            }
        }
    }

    private var emptyPauseState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "moon.stars.fill")
                .font(.systemScaled(72, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            Text("Pause")
                .font(.largeTitle.weight(.light))
                .foregroundStyle(.primary)
            Text("Open a media moment to enter deep contemplation, or tap one from your memory.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var ambientBackground: some View {
        ZStack {
            Color(.systemBackground)
            RadialGradient(
                colors: [Color.indigo.opacity(reduceMotion ? 0.06 : 0.09 + ambientPhase * 0.04),
                         Color.clear],
                center: .topTrailing, startRadius: 0, endRadius: 400
            )
            RadialGradient(
                colors: [Color.purple.opacity(reduceMotion ? 0.04 : 0.06 + ambientPhase * 0.03),
                         Color.clear],
                center: .bottomLeading, startRadius: 0, endRadius: 350
            )
        }
    }

    // MARK: - Helpers

    private func contextPrompt(for item: SelahMediaItem) -> String {
        if let ref = item.scriptureRef, !ref.isEmpty {
            return "Sit with \(ref) for a moment. What is it saying to you today?"
        }
        if let tag = item.meaningTags.first {
            return "This moment carries a theme of \(tag.categoryEnum.rawValue.lowercased()). What does that stir in you?"
        }
        return "Be still. What do you notice in this moment?"
    }

    private func saveReflectionAsMemory(item: SelahMediaItem) {
        let memory = SelahMediaMemory(
            title: reflectionText.prefix(60).description,
            bodyText: reflectionText,
            linkedMediaIds: [item.id ?? ""].filter { !$0.isEmpty },
            linkedScriptureRefs: [item.scriptureRef].compactMap { $0 },
            meaningTags: item.meaningTags
        )
        let sessionRef = currentSession
        currentSession?.complete()
        Analytics.logEvent("selah_session_completed", parameters: nil)
        try? modelContext.save()
        Task {
            do {
                try await SelahMediaService.shared.saveMemory(memory)
                savedToMemory = true
                showReflectionEntry = false
            } catch {
                sessionRef?.phase = .failed
                Analytics.logEvent("selah_session_failed", parameters: nil)
                try? modelContext.save()
            }
        }
    }

    private func saveToMemoryDirectly(item: SelahMediaItem) {
        let memory = SelahMediaMemory(
            title: item.caption.isEmpty ? "Pause moment" : String(item.caption.prefix(60)),
            bodyText: "",
            linkedMediaIds: [item.id ?? ""].filter { !$0.isEmpty },
            linkedScriptureRefs: [item.scriptureRef].compactMap { $0 },
            meaningTags: item.meaningTags
        )
        Task {
            try? await SelahMediaService.shared.saveMemory(memory)
            withAnimation { savedToMemory = true }
        }
    }

    // MARK: - Session Management

    private func loadOrCreateSession() {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        let itemId = item?.id
        let descriptor = FetchDescriptor<LocalSelahSession>(
            predicate: #Predicate<LocalSelahSession> { session in
                session.userId == uid && session.continuationEligibility == true
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let candidates = (try? modelContext.fetch(descriptor)) ?? []
        let continuable = candidates.filter { $0.phase.isContinuable }

        if let existing = continuable.first(where: { $0.mediaItemId == itemId }) {
            currentSession = existing
            existing.resume()
            Analytics.logEvent("selah_session_resumed", parameters: nil)
            if !existing.reflectionText.isEmpty {
                reflectionText = existing.reflectionText
                showReflectionEntry = true
            }
        } else {
            let session = LocalSelahSession(
                userId: uid,
                promptText: item.map { contextPrompt(for: $0) } ?? "Be still.",
                mediaItemId: itemId,
                scriptureRef: item?.scriptureRef
            )
            modelContext.insert(session)
            session.start()
            Analytics.logEvent("selah_session_started", parameters: nil)
            currentSession = session
        }
        try? modelContext.save()
    }

    private func pauseSessionIfActive() {
        guard let session = currentSession, session.phase == .active else { return }
        session.pause()
        Analytics.logEvent("selah_session_paused", parameters: nil)
        try? modelContext.save()
    }
}

#if DEBUG
import SwiftUI

// MARK: - Amen Liquid Glass Spiritual Reaction Simulation

struct AmenLiquidGlassSpiritualReactionSimulation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedTab: SimulationTab = .feed
    @State private var posts = SpiritualPost.samplePosts
    @State private var focusedPost = SpiritualPost.samplePosts[2]
    @State private var commentText = ""
    @State private var commentPreview: [String] = []
    @State private var discernmentContext: DiscernmentPresentation?
    @State private var showcasedEffect: SpiritualEffectKind?
    @State private var effectSeed = UUID()

    private let engine = SpiritualReactionTriggerEngine()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    tabPicker
                    tabContent
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $discernmentContext) { context in
                SpiritualDiscernmentSheet(context: context) { action in
                    handleDiscernmentAction(action, context: context)
                }
                .presentationDetents([.height(360), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spiritual Protection & Discernment")
                .font(.system(.title2, design: .default, weight: .semibold))
                .foregroundStyle(Color.black)

            Text("Amen Safety OS Reaction Engine")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.55))

            Text("A standalone Liquid Glass simulation of spiritually aligned reactions, discernment friction, and contextual Easter egg effects.")
                .font(.subheadline)
                .foregroundStyle(Color.black.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenGlassCard(cornerRadius: 30)
    }

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(SimulationTab.allCases) { tab in
                Button {
                    withAnimation(tabAnimation) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.black.opacity(0.76))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedTab == tab ? Color.black : Color.white.opacity(0.65))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tab.title) simulation section")
            }
        }
        .padding(6)
        .amenGlassCard(cornerRadius: 999, shadow: false)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .feed:
            VStack(spacing: 18) {
                ForEach($posts) { $post in
                    SpiritualPostCard(
                        post: $post,
                        mode: .feed,
                        onDiscernmentRequested: { trigger in
                            discernmentContext = DiscernmentPresentation(
                                trigger: trigger,
                                originalText: post.body,
                                suggestedRewrite: trigger.suggestedRewrite(for: post.body)
                            )
                        }
                    )
                }
            }
        case .comments:
            commentsDemo
        case .safetyOS:
            safetyDemo
        case .effects:
            effectsDemo
        }
    }

    private var commentsDemo: some View {
        let liveTriggers = engine.analyze(commentText)

        return VStack(spacing: 18) {
            SpiritualPostCard(
                post: .constant(focusedPost),
                mode: .commentFocus,
                onDiscernmentRequested: { trigger in
                    discernmentContext = DiscernmentPresentation(
                        trigger: trigger,
                        originalText: commentText.isEmpty ? focusedPost.body : commentText,
                        suggestedRewrite: trigger.suggestedRewrite(for: commentText)
                    )
                }
            )

            if !commentPreview.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Comment preview")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.55))

                    ForEach(commentPreview, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(Color.black.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.8)))
                    }
                }
                .padding(18)
                .amenGlassCard(cornerRadius: 28)
            }

            SpiritualCommentComposer(
                text: $commentText,
                triggers: liveTriggers,
                onSend: {
                    handleCommentSend(triggers: liveTriggers)
                }
            )
        }
    }

    private var safetyDemo: some View {
        VStack(spacing: 18) {
            ForEach(SpiritualPost.safetyShowcasePosts) { sample in
                let triggers = engine.analyze(sample.body)
                VStack(alignment: .leading, spacing: 14) {
                    SpiritualPostCard(
                        post: .constant(sample),
                        mode: .safetyShowcase,
                        onDiscernmentRequested: { trigger in
                            discernmentContext = DiscernmentPresentation(
                                trigger: trigger,
                                originalText: sample.body,
                                suggestedRewrite: trigger.suggestedRewrite(for: sample.body)
                            )
                        }
                    )

                    if let first = triggers.first(where: \.shouldShowDiscernmentSheet) {
                        Button {
                            discernmentContext = DiscernmentPresentation(
                                trigger: first,
                                originalText: sample.body,
                                suggestedRewrite: first.suggestedRewrite(for: sample.body)
                            )
                        } label: {
                            Label("Open discernment sheet", systemImage: "shield.lefthalf.filled")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.black.opacity(0.78))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.82)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var effectsDemo: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Preview the reaction layer effects in isolation.")
                .font(.subheadline)
                .foregroundStyle(Color.black.opacity(0.72))

            ForEach(SpiritualEffectKind.allCases) { effect in
                Button {
                    withAnimation(tabAnimation) {
                        showcasedEffect = effect
                        effectSeed = UUID()
                    }
                } label: {
                    HStack {
                        Text(effect.title)
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text(effect.subtitle)
                            .font(.footnote)
                            .foregroundStyle(Color.black.opacity(0.5))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.8)))
                }
                .buttonStyle(.plain)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.75))
                    .frame(height: 220)

                if let showcasedEffect {
                    EffectPreviewSurface(effect: showcasedEffect, reduceMotion: reduceMotion)
                        .id(effectSeed)
                } else {
                    Text("Select an effect to preview.")
                        .font(.subheadline)
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
            .amenGlassCard(cornerRadius: 28)
        }
        .padding(20)
        .amenGlassCard(cornerRadius: 30)
    }

    private var tabAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.82)
    }

    private func handleCommentSend(triggers: [SpiritualTriggerResult]) {
        if let trigger = triggers.first(where: \.shouldShowDiscernmentSheet) {
            discernmentContext = DiscernmentPresentation(
                trigger: trigger,
                originalText: commentText,
                suggestedRewrite: trigger.suggestedRewrite(for: commentText)
            )
            return
        }

        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        commentPreview.insert(trimmed, at: 0)
        commentText = ""
    }

    private func handleDiscernmentAction(_ action: SpiritualDiscernmentAction, context: DiscernmentPresentation) {
        switch action {
        case .editWithGrace:
            commentText = context.suggestedRewrite ?? commentText
        case .saveDraft:
            let trimmed = context.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { break }
            commentPreview.insert("Draft saved: \(trimmed)", at: 0)
        case .postAnyway:
            let trimmed = context.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { break }
            commentPreview.insert(trimmed, at: 0)
            if commentText == context.originalText {
                commentText = ""
            }
        case .rewriteGently:
            commentText = context.suggestedRewrite ?? context.originalText
        case .pauseAndPray:
            commentText = "I want to pause and pray before I say more."
        }
        discernmentContext = nil
    }
}

// MARK: - Post Card

private struct SpiritualPostCard: View {
    @Binding var post: SpiritualPost
    let mode: SpiritualPostCardMode
    let onDiscernmentRequested: (SpiritualTriggerResult) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedReaction: SpiritualReactionType?
    @State private var activeEffect: SpiritualEffectKind?
    @State private var effectID = UUID()
    @State private var microcopy: String?

    private let engine = SpiritualReactionTriggerEngine()

    var body: some View {
        let triggers = engine.analyze(post.body)

        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 16) {
                header
                bodyText
                triggerArea(triggers: triggers)
                reactionBar(triggers: triggers)
                if mode != .safetyShowcase {
                    commentPreview(triggers: triggers)
                }
                metaBar(triggers: triggers)
            }
            .padding(20)
            .background(
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.white)
                    if triggers.contains(where: { $0.type == .scriptureReference }) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.07), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 14)
                            .mask(
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)

            if let microcopy {
                AmenMicrocopyToast(text: microcopy)
                    .padding(.top, -12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let activeEffect {
                EffectPreviewSurface(effect: activeEffect, reduceMotion: reduceMotion)
                    .allowsHitTesting(false)
                    .id(effectID)
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: selectedReaction) { _, _ in
            dismissMicrocopyLater()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.55))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(post.authorName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.black)

                Text(post.timestamp)
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.48))
            }

            Spacer()

            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.4))
        }
    }

    private var bodyText: some View {
        Text(post.body)
            .font(.body)
            .foregroundStyle(Color.black.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func triggerArea(triggers: [SpiritualTriggerResult]) -> some View {
        if !triggers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(triggers) { trigger in
                            SpiritualTriggerChip(trigger: trigger)
                        }
                    }
                }

                if let scripture = triggers.first(where: { $0.type == .scriptureReference }) {
                    SimScriptureContextCapsule(trigger: scripture)
                } else if let prayer = triggers.first(where: { $0.type == .prayerRequest }) {
                    SimPrayerRequestCapsule(trigger: prayer)
                } else if let testimony = triggers.first(where: { $0.type == .testimony }) {
                    SimTestimonyMomentCapsule(trigger: testimony)
                } else if let wisdom = triggers.first(where: { $0.type == .wisdomPrompt }) {
                    SimWisdomPromptCapsule(trigger: wisdom)
                }
            }
        }
    }

    private func reactionBar(triggers: [SpiritualTriggerResult]) -> some View {
        let priorityOrder = prioritizedReactions(from: triggers)

        return SpiritualReactionBar(
            reactions: priorityOrder,
            counts: post.reactions,
            selectedReaction: selectedReaction,
            onTap: { reaction in
                selectedReaction = reaction
                post.reactions[reaction, default: 0] += selectedReaction == reaction ? 1 : 0
                let payload = reactionPayload(for: reaction, triggers: triggers)
                microcopy = payload.microcopy
                playEffect(payload.effect)
            }
        )
    }

    @ViewBuilder
    private func commentPreview(triggers: [SpiritualTriggerResult]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(Color.black.opacity(0.06))

            Text(commentLine(for: triggers))
                .font(.subheadline)
                .foregroundStyle(Color.black.opacity(0.66))
        }
    }

    private func metaBar(triggers: [SpiritualTriggerResult]) -> some View {
        HStack(spacing: 10) {
            Button {
                microcopy = saveMicrocopy(for: triggers)
                dismissMicrocopyLater()
            } label: {
                Label("Save", systemImage: "bookmark")
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
            }

            Button {
                if triggers.contains(where: { $0.type == .prayerRequest }) {
                    microcopy = "This may be personal. Share with care."
                } else if triggers.contains(where: { $0.lane == .amber }) {
                    microcopy = "Share with context?"
                } else {
                    microcopy = "Shared with care"
                }
                dismissMicrocopyLater()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.black.opacity(0.76))
        .buttonStyle(GlassCapsuleButtonStyle())
    }

    private func prioritizedReactions(from triggers: [SpiritualTriggerResult]) -> [SpiritualReactionType] {
        if triggers.contains(where: { $0.type == .prayerRequest }) {
            return [.praying, .amen, .encouraged, .wisdom, .heart, .praiseGod]
        }

        if triggers.contains(where: { $0.type == .testimony }) {
            return [.amen, .praiseGod, .encouraged, .heart, .wisdom, .praying]
        }

        if triggers.contains(where: { $0.type == .wisdomPrompt }) {
            return [.wisdom, .praying, .amen, .encouraged, .heart, .praiseGod]
        }

        return SpiritualReactionType.allCases
    }

    private func reactionPayload(for reaction: SpiritualReactionType, triggers: [SpiritualTriggerResult]) -> (microcopy: String, effect: SpiritualEffectKind) {
        switch reaction {
        case .amen:
            return ("Amen received", .amenPulse)
        case .praying:
            return ("Prayer joined", .prayerThreadGlow)
        case .encouraged:
            return ("Encouragement received", triggers.contains(where: { $0.type == .testimony }) ? .gratitudeBloom : .amenPulse)
        case .wisdom:
            return ("Wisdom marked", .livingWordShimmer)
        case .praiseGod:
            return ("Praise God received", .gratitudeBloom)
        case .heart:
            return ("Encouragement received", .amenPulse)
        }
    }

    private func saveMicrocopy(for triggers: [SpiritualTriggerResult]) -> String {
        if triggers.contains(where: { $0.type == .scriptureReference }) {
            return "Saved for study"
        }
        if triggers.contains(where: { $0.type == .prayerRequest }) {
            return "Saved to pray"
        }
        if triggers.contains(where: { $0.type == .testimony }) {
            return "Saved testimony"
        }
        return "Saved"
    }

    private func commentLine(for triggers: [SpiritualTriggerResult]) -> String {
        if triggers.contains(where: { $0.type == .prayerRequest }) {
            return "Prayer-heavy moment. Praying is prioritized in the reaction row."
        }
        if triggers.contains(where: { $0.type == .scriptureReference }) {
            return "Scripture stays inline with context instead of hijacking the layout."
        }
        if let concern = triggers.first(where: \.shouldShowDiscernmentSheet) {
            return concern.message
        }
        return "The interaction layer adds calm context without blocking normal expression."
    }

    private func playEffect(_ effect: SpiritualEffectKind) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.82)) {
            activeEffect = effect
            effectID = UUID()
        }
        dismissMicrocopyLater()
    }

    private func dismissMicrocopyLater() {
        let delay = reduceMotion ? 0.8 : 1.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.2)) {
                microcopy = nil
                activeEffect = nil
            }
        }
    }
}

// MARK: - Composer

private struct SpiritualCommentComposer: View {
    @Binding var text: String
    let triggers: [SpiritualTriggerResult]
    let onSend: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var showPauseState = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !triggers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(triggers) { trigger in
                            SpiritualTriggerChip(trigger: trigger)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Comment composer")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.5))

                TextField("Respond with care", text: $text, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(Color.black)
                    .lineLimit(isFocused ? 4 : 2)
                    .focused($isFocused)

                HStack(spacing: 10) {
                    Button {
                        onSend()
                    } label: {
                        Text(showPauseState ? "Pause" : "Send")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(PrimaryComposerButtonStyle())
                    .accessibilityLabel(showPauseState ? "Pause before sending comment" : "Send comment")
                }
            }
            .padding(18)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: isFocused ? 30 : 26, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: isFocused ? 30 : 26, style: .continuous)
                        .fill(Color.white.opacity(0.82))
                    if showPauseState {
                        PeaceSlowdownOverlay()
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: isFocused ? 30 : 26, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 14, y: 6)
        }
        .onChange(of: triggers) { _, newValue in
            let shouldPause = newValue.contains(where: { $0.type == .shameTone || $0.type == .conflictTone })
            if shouldPause {
                triggerPause()
            } else {
                showPauseState = false
            }
        }
    }

    private func triggerPause() {
        showPauseState = true
        let delay = reduceMotion ? 0.4 : 1.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            showPauseState = false
        }
    }
}

// MARK: - Reaction Bar

private struct SpiritualReactionBar: View {
    let reactions: [SpiritualReactionType]
    let counts: [SpiritualReactionType: Int]
    let selectedReaction: SpiritualReactionType?
    let onTap: (SpiritualReactionType) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(reactions, id: \.self) { reaction in
                    SpiritualReactionButton(
                        reaction: reaction,
                        count: counts[reaction, default: 0],
                        isSelected: selectedReaction == reaction,
                        onTap: { onTap(reaction) }
                    )
                }
            }
        }
    }
}

private struct SpiritualReactionButton: View {
    let reaction: SpiritualReactionType
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        Button {
            animateTap()
            onTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: reaction.symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(reaction.title)
                    .font(.footnote.weight(.semibold))
                Text("\(count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            .foregroundStyle(Color.black.opacity(isSelected ? 0.96 : 0.76))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.black.opacity(0.08) : Color.white.opacity(0.84))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
            )
            .scaleEffect(isPressed ? 0.96 : (isSelected ? 1.04 : 1.0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(reaction.title) reaction, \(count) reactions")
    }

    private func animateTap() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.12)) {
            isPressed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.28, dampingFraction: 0.72)) {
                isPressed = false
            }
        }
    }
}

// MARK: - Trigger Chips and Capsules

private struct SpiritualTriggerChip: View {
    let trigger: SpiritualTriggerResult

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(trigger.lane.tint.opacity(0.85))
                .frame(width: 6, height: 6)
            Text(trigger.title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.black.opacity(0.74))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.85)))
        .overlay(Capsule(style: .continuous).stroke(Color.black.opacity(0.05), lineWidth: 0.8))
    }
}

private struct SimScriptureContextCapsule: View {
    let trigger: SpiritualTriggerResult

    var body: some View {
        capsule(
            title: "Scripture detected",
            subtitle: "Open · Add context · Keep as text",
            effect: LivingWordShimmerEffect()
        )
    }
}

private struct SimPrayerRequestCapsule: View {
    let trigger: SpiritualTriggerResult

    var body: some View {
        capsule(
            title: "Prayer detected",
            subtitle: "Join prayer",
            effect: PrayerThreadGlowEffect()
        )
    }
}

private struct SimTestimonyMomentCapsule: View {
    let trigger: SpiritualTriggerResult

    var body: some View {
        capsule(
            title: "Testimony moment",
            subtitle: "Amen · Praise God · Encouraged",
            effect: GratitudeBloomEffect()
        )
    }
}

private struct SimWisdomPromptCapsule: View {
    let trigger: SpiritualTriggerResult

    var body: some View {
        capsule(
            title: "Discernment moment",
            subtitle: "Pause · Pray · Respond",
            effect: Optional<EmptyView>.none
        )
    }
}

private func capsule<Effect: View>(title: String, subtitle: String, effect: Effect?) -> some View {
    HStack(alignment: .center, spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color.black.opacity(0.55))
        }
        Spacer(minLength: 12)
    }
    .foregroundStyle(Color.black.opacity(0.82))
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
        ZStack {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.84))
            if let effect {
                effect.opacity(0.75)
            }
        }
    )
    .overlay(Capsule(style: .continuous).stroke(Color.black.opacity(0.05), lineWidth: 0.8))
}

// MARK: - Discernment Sheet

private struct SpiritualDiscernmentSheet: View {
    let context: DiscernmentPresentation
    let onAction: (SpiritualDiscernmentAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Discernment Moment")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.black)

                Text(context.trigger.sheetSubtitle)
                    .font(.headline)
                    .foregroundStyle(Color.black.opacity(0.75))

                Text("Your post is still yours. Amen is offering a pause before it reaches someone else.")
                    .font(.body)
                    .foregroundStyle(Color.black.opacity(0.72))

                if let suggestedRewrite = context.suggestedRewrite {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Rewrite preview")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.55))

                        Text("Original")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.5))
                        Text("\"\(context.originalText)\"")
                            .font(.subheadline)
                            .foregroundStyle(Color.black.opacity(0.84))

                        Text("Suggested")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.5))
                        Text("\"\(suggestedRewrite)\"")
                            .font(.subheadline)
                            .foregroundStyle(Color.black.opacity(0.84))
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.78)))
                }

                VStack(spacing: 10) {
                    ForEach(context.trigger.sheetActions, id: \.self) { action in
                        Button {
                            onAction(action)
                        } label: {
                            Text(action.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(action == .editWithGrace ? Color.white : Color.black.opacity(0.78))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 48)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(action == .editWithGrace ? Color.black : Color.white.opacity(0.84))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
        .background(Color.white.ignoresSafeArea())
    }
}

// MARK: - Effects

private struct EffectPreviewSurface: View {
    let effect: SpiritualEffectKind
    let reduceMotion: Bool

    var body: some View {
        switch effect {
        case .amenPulse:
            AmenPulseEffect(reduceMotion: reduceMotion)
        case .prayerThreadGlow:
            PrayerThreadGlowEffect()
        case .livingWordShimmer:
            LivingWordShimmerEffect()
        case .peaceSlowdown:
            PeaceSlowdownOverlay()
        case .gratitudeBloom:
            GratitudeBloomEffect()
        }
    }
}

private struct AmenPulseEffect: View {
    let reduceMotion: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.08), lineWidth: 18)
                .scaleEffect(animate && !reduceMotion ? 1.2 : 0.65)
                .opacity(animate ? 0 : 0.85)
                .frame(width: 120, height: 120)

            Text("Amen")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.7))
                .offset(y: animate && !reduceMotion ? -24 : 0)
                .opacity(animate ? 0 : 1)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.9)) {
                animate = true
            }
        }
    }
}

private struct PrayerThreadGlowEffect: View {
    @State private var glow = false

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.04))
                .frame(width: 180, height: 72)
                .shadow(color: Color.black.opacity(glow ? 0.12 : 0.03), radius: glow ? 20 : 8, y: 0)

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.black.opacity(0.16))
                        .frame(width: 8, height: 8)
                        .offset(y: glow ? -18 : 10)
                        .opacity(glow ? 0 : 1)
                        .animation(.easeOut(duration: 0.9).delay(Double(index) * 0.08), value: glow)
                }
            }
        }
        .onAppear {
            glow = true
        }
    }
}

private struct LivingWordShimmerEffect: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.clear)
                .overlay(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.9), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 80)
                    .offset(x: phase * width)
                )
                .mask(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9)) {
                phase = 1
            }
        }
    }
}

private struct PeaceSlowdownOverlay: View {
    @State private var visible = false

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.black.opacity(visible ? 0.035 : 0.015))
            .overlay(
                Text("Peace check")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.35))
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2)) {
                    visible = true
                }
            }
    }
}

private struct GratitudeBloomEffect: View {
    @State private var bloom = false

    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [
                        Color.black.opacity(bloom ? 0.05 : 0.01),
                        .clear
                    ],
                    center: .center,
                    startRadius: 8,
                    endRadius: bloom ? 160 : 40
                )
            )
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    bloom = true
                }
            }
    }
}

// MARK: - Models

enum SpiritualTriggerType: CaseIterable {
    case scriptureReference
    case prayerRequest
    case testimony
    case wisdomPrompt
    case shameTone
    case conflictTone
}

struct SpiritualTriggerResult: Identifiable, Equatable {
    let id = UUID()
    let type: SpiritualTriggerType
    let title: String
    let message: String
    let recommendedActions: [String]
    let priority: Int
    let shouldShowDiscernmentSheet: Bool

    var lane: AmenSafetyLane {
        switch type {
        case .scriptureReference, .prayerRequest, .testimony:
            return .green
        case .wisdomPrompt:
            return .blue
        case .shameTone, .conflictTone:
            return .amber
        }
    }

    var sheetSubtitle: String {
        switch type {
        case .shameTone:
            return "This may land as shame instead of correction."
        case .conflictTone:
            return "This may escalate conflict."
        default:
            return "This may land differently than intended."
        }
    }

    var sheetActions: [SpiritualDiscernmentAction] {
        switch type {
        case .conflictTone:
            return [.rewriteGently, .pauseAndPray, .postAnyway]
        case .shameTone:
            return [.editWithGrace, .saveDraft, .postAnyway]
        default:
            return [.postAnyway]
        }
    }

    func suggestedRewrite(for originalText: String) -> String? {
        switch type {
        case .shameTone:
            return "I disagree, but I want to respond with care. Can we talk through this?"
        case .conflictTone:
            return "I want to slow down and respond clearly. Can we work through this without escalating?"
        case .wisdomPrompt:
            return "I need wisdom before I respond, and I want to choose my words carefully."
        default:
            return nil
        }
    }
}

enum SpiritualReactionType: String, CaseIterable, Hashable {
    case amen
    case praying
    case encouraged
    case wisdom
    case praiseGod
    case heart

    var title: String {
        switch self {
        case .amen: "Amen"
        case .praying: "Praying"
        case .encouraged: "Encouraged"
        case .wisdom: "Wisdom"
        case .praiseGod: "Praise God"
        case .heart: "Heart"
        }
    }

    var symbol: String {
        switch self {
        case .amen: "hands.sparkles"
        case .praying: "sparkles"
        case .encouraged: "sun.max"
        case .wisdom: "book.closed"
        case .praiseGod: "music.note"
        case .heart: "heart"
        }
    }
}

struct SpiritualPost: Identifiable, Equatable {
    let id: String
    let authorName: String
    let body: String
    let timestamp: String
    var reactions: [SpiritualReactionType: Int]

    static let samplePosts: [SpiritualPost] = [
        SpiritualPost(
            id: "1",
            authorName: "Moriah",
            body: "I was lost for a long time, but God brought me back slowly. I’m thankful.",
            timestamp: "2m ago",
            reactions: [.amen: 18, .encouraged: 9, .praiseGod: 6]
        ),
        SpiritualPost(
            id: "2",
            authorName: "Elijah",
            body: "Psalm 139 says God knows me fully and still loves me.",
            timestamp: "14m ago",
            reactions: [.wisdom: 8, .amen: 13, .heart: 5]
        ),
        SpiritualPost(
            id: "3",
            authorName: "Naomi",
            body: "Please pray for me. I’m having a hard week.",
            timestamp: "28m ago",
            reactions: [.praying: 21, .heart: 7, .amen: 11]
        ),
        SpiritualPost(
            id: "4",
            authorName: "Micah",
            body: "You should be ashamed of yourself for thinking that.",
            timestamp: "1h ago",
            reactions: [.heart: 1, .wisdom: 1]
        ),
        SpiritualPost(
            id: "5",
            authorName: "Abigail",
            body: "I need wisdom before I respond to this situation.",
            timestamp: "3h ago",
            reactions: [.wisdom: 16, .praying: 8, .amen: 6]
        )
    ]

    static let safetyShowcasePosts: [SpiritualPost] = [
        SpiritualPost(
            id: "s1",
            authorName: "Grace",
            body: "You should be ashamed of yourself for posting that.",
            timestamp: "Now",
            reactions: [:]
        ),
        SpiritualPost(
            id: "s2",
            authorName: "Jonah",
            body: "You always do this. Shut up and listen for once.",
            timestamp: "Now",
            reactions: [:]
        )
    ]
}

extension AmenSafetyLane {
    var tint: Color {
        switch self {
        case .green:  return Color.black.opacity(0.55)
        case .blue:   return Color.black.opacity(0.42)
        case .amber:  return Color.black.opacity(0.3)
        case .red:    return Color.black.opacity(0.22)
        }
    }
}

enum SpiritualDiscernmentAction: String {
    case editWithGrace
    case saveDraft
    case postAnyway
    case rewriteGently
    case pauseAndPray

    var title: String {
        switch self {
        case .editWithGrace: "Edit with grace"
        case .saveDraft: "Save draft"
        case .postAnyway: "Post anyway"
        case .rewriteGently: "Rewrite gently"
        case .pauseAndPray: "Pause and pray"
        }
    }
}

private struct DiscernmentPresentation: Identifiable {
    let id = UUID()
    let trigger: SpiritualTriggerResult
    let originalText: String
    let suggestedRewrite: String?
}

private enum SimulationTab: String, CaseIterable, Identifiable {
    case feed
    case comments
    case safetyOS = "safety"
    case effects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: "Feed"
        case .comments: "Comments"
        case .safetyOS: "Safety OS"
        case .effects: "Effects"
        }
    }
}

private enum SpiritualPostCardMode {
    case feed
    case commentFocus
    case safetyShowcase
}

private enum SpiritualEffectKind: CaseIterable, Identifiable {
    case amenPulse
    case prayerThreadGlow
    case livingWordShimmer
    case peaceSlowdown
    case gratitudeBloom

    var id: String { title }

    var title: String {
        switch self {
        case .amenPulse: "Amen Pulse"
        case .prayerThreadGlow: "Prayer Thread Glow"
        case .livingWordShimmer: "Living Word Shimmer"
        case .peaceSlowdown: "Peace Slowdown"
        case .gratitudeBloom: "Gratitude Bloom"
        }
    }

    var subtitle: String {
        switch self {
        case .amenPulse: "Soft ripple and floating Amen"
        case .prayerThreadGlow: "Capsule glow and prayer beads"
        case .livingWordShimmer: "Scripture shimmer"
        case .peaceSlowdown: "Calm friction layer"
        case .gratitudeBloom: "Subtle testimony bloom"
        }
    }
}

// MARK: - Engine

final class SpiritualReactionTriggerEngine {
    // Future production wiring:
    // Post/comment text -> lightweight local heuristics here -> callable Amen Safety OS
    // Cloud Function returns canonical labels -> client merges labels with these UI affordances.
    func analyze(_ text: String) -> [SpiritualTriggerResult] {
        let normalized = text.lowercased()
        var results: [SpiritualTriggerResult] = []

        if containsAny(normalized, patterns: ["psalm 139", "john 3:16", "romans 8", "proverbs 3:5", "matthew 6"]) {
            results.append(
                SpiritualTriggerResult(
                    type: .scriptureReference,
                    title: "Scripture detected",
                    message: "Amen found a possible Scripture reference.",
                    recommendedActions: ["Open", "Add context", "Keep as text"],
                    priority: 40,
                    shouldShowDiscernmentSheet: false
                )
            )
        }

        if containsAny(normalized, patterns: ["pray for me", "prayers", "please pray", "need prayer", "praying for you"]) {
            results.append(
                SpiritualTriggerResult(
                    type: .prayerRequest,
                    title: "Prayer detected",
                    message: "This sounds like a prayer request.",
                    recommendedActions: ["Join prayer"],
                    priority: 45,
                    shouldShowDiscernmentSheet: false
                )
            )
        }

        if containsAny(normalized, patterns: ["god brought me", "i was lost", "i came back", "testimony", "grateful to god", "thankful"]) {
            results.append(
                SpiritualTriggerResult(
                    type: .testimony,
                    title: "Testimony moment",
                    message: "This may be encouraging the community through testimony.",
                    recommendedActions: ["Amen", "Praise God", "Encouraged"],
                    priority: 35,
                    shouldShowDiscernmentSheet: false
                )
            )
        }

        if containsAny(normalized, patterns: ["need wisdom", "help me discern", "should i", "what should i do", "before i respond"]) {
            results.append(
                SpiritualTriggerResult(
                    type: .wisdomPrompt,
                    title: "Discernment moment",
                    message: "This sounds like a wisdom prompt.",
                    recommendedActions: ["Pause", "Pray", "Respond"],
                    priority: 50,
                    shouldShowDiscernmentSheet: false
                )
            )
        }

        if containsAny(normalized, patterns: ["ashamed", "you are disgusting", "fake christian", "god hates you", "worthless"]) {
            results.append(
                SpiritualTriggerResult(
                    type: .shameTone,
                    title: "Discernment moment",
                    message: "This may land as shame instead of correction.",
                    recommendedActions: ["Edit with grace", "Post anyway", "Save draft"],
                    priority: 100,
                    shouldShowDiscernmentSheet: true
                )
            )
        }

        if containsAny(normalized, patterns: ["you always", "you never", "shut up", "idiot", "i hate"]) {
            results.append(
                SpiritualTriggerResult(
                    type: .conflictTone,
                    title: "Peace check",
                    message: "This may escalate conflict.",
                    recommendedActions: ["Slow down", "Rewrite gently", "Post anyway"],
                    priority: 95,
                    shouldShowDiscernmentSheet: true
                )
            )
        }

        return results.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.title < rhs.title
            }
            return lhs.priority > rhs.priority
        }
    }

    private func containsAny(_ text: String, patterns: [String]) -> Bool {
        patterns.contains { text.contains($0) }
    }
}

// MARK: - Styles

private struct GlassCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.68 : 0.84)))
            .overlay(Capsule(style: .continuous).stroke(Color.black.opacity(0.05), lineWidth: 0.8))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct PrimaryComposerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white)
            .background(Capsule(style: .continuous).fill(Color.black.opacity(configuration.isPressed ? 0.86 : 1)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

// MARK: - Preview

#Preview {
    AmenLiquidGlassSpiritualReactionSimulation()
}

/*
 Production wiring notes:
 Post/comment text
 -> client-side lightweight trigger scan
 -> Amen Safety OS callable Cloud Function
 -> server returns canonical trigger labels
 -> client renders Liquid Glass UI reaction layer
 -> user can post, edit, save draft, or continue
 -> moderation/safety logs are written server-side
 -> spiritual reaction effects remain client-side UI only
 */
#endif

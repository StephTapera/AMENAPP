// BereanInteractiveUI.swift
// AMENAPP
//
// A unified collection of premium Berean AI micro-interaction components,
// each translated from the reference design prompts into AMEN's exact design language:
//
//   BereanOnboardingFlow     — step-cycling text hierarchy with slide transitions
//                              (Framer Motion onboarding ref → native SwiftUI)
//   BereanThinkingTaskPills  — AI "thinking" task pills with matchedGeometryEffect
//                              reorder + checkmark pop (swipe/tap reorder ref)
//   BereanInputOverlay       — blurred chat overlay triggered from + button
//                              (Grok blurred menu ref → AMEN Berean context)
//   BereanMorphingToolbar    — morphing capsule action pill that stretches
//                              when an action is selected (action pill ref)
//
// All components use AMEN's exact tokens:
//   Background:     #F2F2F7 near-white
//   Coral accent:   RGB(0.88, 0.38, 0.28)
//   Purple accent:  RGB(0.58, 0.25, 0.95)
//   Typography:     Georgia for display, system for UI
//   Glass:          .ultraThinMaterial + white overlay
//   Springs:        response 0.42–0.55, damping 0.72–0.82

import SwiftUI
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AMEN Berean Design Tokens
// ─────────────────────────────────────────────────────────────────────────────

private enum BUI {
    // Palette
    static let bg           = Color(red: 0.949, green: 0.949, blue: 0.969)  // #F2F2F7
    static let coral        = Color(red: 0.88, green: 0.38, blue: 0.28)
    static let coraltint    = Color(red: 0.88, green: 0.38, blue: 0.28).opacity(0.12)
    static let violet       = Color(red: 0.58, green: 0.25, blue: 0.95)
    static let ink          = Color(red: 0.11, green: 0.10, blue: 0.10)
    static let inkSoft      = Color(red: 0.42, green: 0.40, blue: 0.40)
    static let inkFaint     = Color(red: 0.68, green: 0.66, blue: 0.64)
    static let cardWhite    = Color.white
    static let pillSurface  = Color(red: 0.93, green: 0.92, blue: 0.91)
    static let pillBorder   = Color(red: 0.84, green: 0.82, blue: 0.80)

    // Springs
    static func snap() -> Animation { .spring(response: 0.42, dampingFraction: 0.76) }
    static func bounce() -> Animation { .spring(response: 0.52, dampingFraction: 0.70) }
    static func settle() -> Animation { .spring(response: 0.62, dampingFraction: 0.82) }

    // Typography
    static let displayFont  = Font.custom("Georgia", size: 34).weight(.light)
    static let headlineFont = Font.system(size: 17, weight: .semibold)
    static let bodyFont     = Font.system(size: 15, weight: .regular)
    static let captionFont  = Font.system(size: 12, weight: .medium)
    static let chipFont     = Font.system(size: 13, weight: .medium)

    // Geometry
    static let cardRadius: CGFloat   = 20
    static let pillRadius: CGFloat   = 100
    static let hPad: CGFloat         = 22
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 1. BereanOnboardingFlow
// ─────────────────────────────────────────────────────────────────────────────
//
// Adaptation: Framer Motion bold text-hierarchy onboarding → SwiftUI.
//
// Each step shows large typographic text where KEY WORDS are in AMEN coral/ink,
// supporting words are muted. Steps advance with a slide-up-and-out / slide-
// in-from-below asymmetric transition (matching the Framer Motion ref behavior).
//
// Step 2 → 3 is the "append" moment: existing text shifts up with layout
// animation and a new appended clause fades in below — achieved here via
// SwiftUI's .transition(.move + .opacity) within a Group with .animation.

struct BereanOnboardingFlow: View {

    // MARK: Step definition

    struct OnboardingStep: Identifiable {
        let id: Int
        let segments: [TextSegment]
        let ctaLabel: String
        let ctaIcon: String?
        /// When true this step appends new text BELOW the previous step's text
        let isAppendStep: Bool

        struct TextSegment: Identifiable {
            let id = UUID()
            let text: String
            let style: Style
            enum Style {
                case muted       // inkFaint
                case primary     // ink
                case accent      // coral
                case icon(String) // SF Symbol inline
            }
        }
    }

    private let steps: [OnboardingStep] = [
        // Step 0 — Faith sets the foundation
        OnboardingStep(
            id: 0,
            segments: [
                .init(text: "Scripture shaped ", style: .muted),
                .init(text: "how we think,", style: .primary),
                .init(text: " plan, and ", style: .muted),
                .init(text: "live.", style: .accent)
            ],
            ctaLabel: "Continue", ctaIcon: nil, isAppendStep: false
        ),
        // Step 1 — Every believer has a unique journey
        OnboardingStep(
            id: 1,
            segments: [
                .init(text: "Every believer has their own ", style: .muted),
                .init(text: "unique ", style: .primary),
                .init(text: "scroll", style: .icon("scroll")),
                .init(text: " season of growth", style: .primary)
            ],
            ctaLabel: "Continue", ctaIcon: nil, isAppendStep: false
        ),
        // Step 2 — Append step: adds clause below step 1's text
        OnboardingStep(
            id: 2,
            segments: [
                .init(text: ", and it's not random — it's a ", style: .muted),
                .init(text: "guided journey.", style: .primary)
            ],
            ctaLabel: "Continue", ctaIcon: nil, isAppendStep: true
        ),
        // Step 3 — CTA
        OnboardingStep(
            id: 3,
            segments: [
                .init(text: "Unlock wisdom by pairing your ", style: .muted),
                .init(text: "faith", style: .icon("cross")),
                .init(text: " with ", style: .muted),
                .init(text: "deep study", style: .accent),
                .init(text: " every day.", style: .muted)
            ],
            ctaLabel: "Begin Studying", ctaIcon: "book.open.fill", isAppendStep: false
        )
    ]

    @State private var currentStep = 0
    @State private var showAppendedText = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            BUI.bg.ignoresSafeArea()

            // Atmospheric orbs
            atmosphericOrbs

            VStack(spacing: 0) {
                Spacer()

                // ── Text area ──────────────────────────────────────────────────
                Group {
                    if currentStep == 2 {
                        // Append step: display step 1's text (held on screen) +
                        // appended clause sliding in below
                        VStack(alignment: .leading, spacing: 10) {
                            buildTextRow(steps[1].segments)
                                .transition(.identity) // stays put

                            if showAppendedText {
                                buildTextRow(steps[2].segments)
                                    .transition(
                                        reduceMotion
                                        ? .opacity
                                        : .asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal:   .move(edge: .top).combined(with: .opacity)
                                          )
                                    )
                            }
                        }
                        .padding(.horizontal, BUI.hPad)
                        .animation(reduceMotion ? .none : BUI.settle(), value: showAppendedText)
                        .transition(.identity) // outer container doesn't move
                    } else {
                        // Normal step: full text slides in from bottom, exits up
                        buildTextRow(steps[min(currentStep, steps.count - 1)].segments)
                            .padding(.horizontal, BUI.hPad)
                            .id(currentStep)   // forces SwiftUI to treat each step as new identity
                            .transition(
                                reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal:   .move(edge: .top).combined(with: .opacity)
                                  )
                            )
                    }
                }
                .animation(reduceMotion ? .none : BUI.bounce(), value: currentStep)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 56)

                // ── Step dots ─────────────────────────────────────────────────
                BereanStepDots(total: 4, current: min(currentStep, 3))
                    .padding(.bottom, 32)

                // ── CTA Button ────────────────────────────────────────────────
                BereanOnboardingCTA(
                    label: currentStep >= steps.count - 1 ? "Begin Studying" : "Continue",
                    icon: currentStep >= steps.count - 1 ? "book.open.fill" : nil,
                    isFinal: currentStep >= steps.count - 1
                ) {
                    advanceStep()
                }
                .padding(.horizontal, BUI.hPad)
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: Text builder
    // Builds multi-colored text using AttributedString — avoids deprecated Text+Text
    // concatenation and ViewBuilder control-flow restrictions.
    // Icon segments are rendered inline as SFSymbol attachments.

    private func buildTextRow(_ segments: [OnboardingStep.TextSegment]) -> some View {
        var attributed = AttributedString()
        for seg in segments {
            attributed.append(makeAttributedSegment(seg))
        }
        return Text(attributed)
            .font(.system(size: 28, weight: .semibold, design: .default))
            .lineSpacing(6)
    }

    private func makeAttributedSegment(_ seg: OnboardingStep.TextSegment) -> AttributedString {
        switch seg.style {
        case .muted:
            var a = AttributedString(seg.text)
            a.foregroundColor = UIColor(BUI.inkFaint)
            return a
        case .primary:
            var a = AttributedString(seg.text)
            a.foregroundColor = UIColor(BUI.ink)
            return a
        case .accent:
            var a = AttributedString(seg.text)
            a.foregroundColor = UIColor(BUI.coral)
            return a
        case .icon(let name):
            // SF Symbol attachment
            let attachment = NSTextAttachment()
            let config = UIImage.SymbolConfiguration(textStyle: .body)
            attachment.image = UIImage(systemName: name, withConfiguration: config)?
                .withTintColor(UIColor(BUI.coral), renderingMode: .alwaysOriginal)
            let iconPart = AttributedString(NSAttributedString(attachment: attachment))
            // Space + label text after the icon
            var labelPart = AttributedString(" \(seg.text)")
            labelPart.foregroundColor = UIColor(BUI.ink)
            return iconPart + labelPart
        }
    }

    private func advanceStep() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if currentStep == 1 {
            // Step 1 → 2: keep text, append new clause
            withAnimation(reduceMotion ? .none : BUI.settle()) {
                currentStep = 2
            }
            // Slight delay so layout change settles first, then append text appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(reduceMotion ? .none : BUI.bounce()) {
                    showAppendedText = true
                }
            }
        } else if currentStep == 2 {
            withAnimation(reduceMotion ? .none : BUI.bounce()) {
                showAppendedText = false
                currentStep = 3
            }
        } else if currentStep < steps.count - 1 {
            withAnimation(reduceMotion ? .none : BUI.bounce()) {
                currentStep += 1
            }
        }
        // step 3 = final — parent dismisses
    }

    // MARK: Atmospheric orbs (matching BereanOnboardingView exactly)

    @State private var orbL = false
    @State private var orbR = false

    private var atmosphericOrbs: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 1.0, green: 0.35, blue: 0.35).opacity(0.25), .clear],
                    center: .center, startRadius: 0, endRadius: 220
                ))
                .frame(width: 440, height: 440)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .offset(x: -90, y: 100)
                .blur(radius: 70)
                .scaleEffect(orbL ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: orbL)
                .onAppear { orbL = true }
                .allowsHitTesting(false)

            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 0.58, green: 0.25, blue: 0.95).opacity(0.20), .clear],
                    center: .center, startRadius: 0, endRadius: 200
                ))
                .frame(width: 400, height: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 90, y: 80)
                .blur(radius: 65)
                .scaleEffect(orbR ? 1.10 : 1.0)
                .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: orbR)
                .onAppear { orbR = true }
                .allowsHitTesting(false)
        }
    }
}

// MARK: Step dots

private struct BereanStepDots: View {
    let total: Int
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? BUI.coral : BUI.inkFaint.opacity(0.35))
                    .frame(width: i == current ? 22 : 6, height: 6)
                    .animation(BUI.snap(), value: current)
            }
        }
    }
}

// MARK: CTA Button

private struct BereanOnboardingCTA: View {
    let label: String
    let icon: String?
    let isFinal: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(isFinal ? BUI.cardWhite : BUI.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isFinal
                ? AnyShapeStyle(BUI.coral)
                : AnyShapeStyle(.ultraThinMaterial)
            )
            .overlay(
                Capsule()
                    .stroke(
                        isFinal ? Color.clear : BUI.pillBorder,
                        lineWidth: 1
                    )
            )
            .clipShape(Capsule())
            .shadow(
                color: isFinal ? BUI.coral.opacity(0.28) : .black.opacity(0.05),
                radius: isFinal ? 16 : 4, x: 0, y: isFinal ? 6 : 2
            )
        }
        .buttonStyle(BereanCTAPressStyle())
    }
}

private struct BereanCTAPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 2. BereanThinkingTaskPills
// ─────────────────────────────────────────────────────────────────────────────
//
// Adaptation: SwiftUI task-pill AI "thinking" reorder → Berean processing UI.
//
// Shows Berean's active reasoning steps as pill cards.
// When Berean "checks off" a step, it pops to the top with matchedGeometryEffect.
// Checkmark uses a scale-bounce pop (0.8 → 1.1 → 1.0).
// Tasks represent real Berean reasoning: Scripture lookup, Cross-reference,
// Theological context, Compose answer.

struct BereanThinkingTaskPills: View {

    struct BereanTask: Identifiable, Equatable {
        let id: UUID
        var label: String
        var subLabel: String
        var icon: String
        var isChecked: Bool
        var checkProgress: CGFloat   // 0→1 drives the checkmark pop
    }

    @State private var tasks: [BereanTask] = [
        .init(id: UUID(), label: "Searching Scripture",
              subLabel: "Cross-referencing relevant passages",
              icon: "text.book.closed.fill", isChecked: false, checkProgress: 0),
        .init(id: UUID(), label: "Theological context",
              subLabel: "Examining historical + doctrinal layers",
              icon: "scroll.fill", isChecked: false, checkProgress: 0),
        .init(id: UUID(), label: "Composing your answer",
              subLabel: "Crafting a balanced, grounded response",
              icon: "sparkles", isChecked: false, checkProgress: 0)
    ]

    @Namespace private var pillNamespace
    @State private var isSimulating = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                // Berean "thinking" indicator — pulsing coral dot
                ZStack {
                    Circle()
                        .fill(BUI.coral.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "brain")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BUI.coral)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Berean is thinking")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BUI.ink)
                    Text("Working through your question")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(BUI.inkFaint)
                }
                Spacer()
                // Pulsing thinking dots
                BereanThinkingDots()
            }
            .padding(.horizontal, BUI.hPad)
            .padding(.vertical, 14)

            Divider()
                .opacity(0.25)
                .padding(.horizontal, BUI.hPad)

            // Task pill list — reorders with matchedGeometryEffect
            VStack(spacing: 10) {
                ForEach(tasks) { task in
                    BereanTaskPill(
                        task: task,
                        namespace: pillNamespace,
                        onTap: { toggleTask(task) }
                    )
                }
            }
            .padding(.horizontal, BUI.hPad)
            .padding(.vertical, 16)
            .animation(
                .spring(response: 0.58, dampingFraction: 0.72),
                value: tasks.map(\.id)
            )

            // Simulate button
            Button {
                simulateThinking()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .medium))
                    Text("Simulate Berean Thinking")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(BUI.inkSoft)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(BUI.pillSurface)
                        .overlay(Capsule().stroke(BUI.pillBorder.opacity(0.5), lineWidth: 0.75))
                )
            }
            .buttonStyle(BereanCTAPressStyle())
            .padding(.bottom, 18)
            .disabled(isSimulating)
        }
        .background(
            RoundedRectangle(cornerRadius: BUI.cardRadius, style: .continuous)
                .fill(BUI.cardWhite)
                .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 6)
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Logic

    private func toggleTask(_ task: BereanTask) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }

        // Toggle checked
        withAnimation(BUI.bounce()) {
            tasks[idx].isChecked.toggle()
        }

        // Animate checkmark pop: 0 → 1 via two-phase animation
        tasks[idx].checkProgress = 0
        withAnimation(.spring(response: 0.30, dampingFraction: 0.55)) {
            tasks[idx].checkProgress = 1.1   // overshoot
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
                tasks[idx].checkProgress = 1.0  // settle
            }
        }

        // Move to top if checked, back to original position if unchecked
        if tasks[idx].isChecked {
            let item = tasks.remove(at: idx)
            withAnimation(.spring(response: 0.58, dampingFraction: 0.72)) {
                tasks.insert(item, at: 0)
            }
        } else {
            // Restore alphabetical/original order — move to end of checked group
            let item = tasks.remove(at: idx)
            withAnimation(.spring(response: 0.58, dampingFraction: 0.72)) {
                tasks.append(item)
            }
        }
    }

    func simulateThinking() {
        isSimulating = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Pick first unchecked task; if all checked, reset all
        if tasks.allSatisfy({ $0.isChecked }) {
            withAnimation(BUI.bounce()) {
                for i in tasks.indices { tasks[i].isChecked = false; tasks[i].checkProgress = 0 }
            }
            // Re-sort
            let origOrder = ["Searching Scripture", "Theological context", "Composing your answer"]
            withAnimation(.spring(response: 0.58, dampingFraction: 0.72)) {
                tasks.sort { a, b in
                    (origOrder.firstIndex(of: a.label) ?? 99) < (origOrder.firstIndex(of: b.label) ?? 99)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { isSimulating = false }
            return
        }

        // Sequential check: tick tasks one by one with 0.55s stagger
        let uncheckedIndices = tasks.indices.filter { !tasks[$0].isChecked }
        for (delay, idx) in uncheckedIndices.enumerated() {
            let fireAt = Double(delay) * 0.55
            DispatchQueue.main.asyncAfter(deadline: .now() + fireAt) {
                toggleTask(tasks[idx])
            }
        }
        let totalDuration = Double(uncheckedIndices.count) * 0.55 + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            isSimulating = false
        }
    }
}

// MARK: BereanTaskPill

private struct BereanTaskPill: View {
    let task: BereanThinkingTaskPills.BereanTask
    let namespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Check circle — pops on completion
                ZStack {
                    Circle()
                        .fill(task.isChecked ? BUI.coral : Color.clear)
                        .frame(width: 28, height: 28)

                    Circle()
                        .stroke(task.isChecked ? BUI.coral : BUI.pillBorder, lineWidth: 1.5)
                        .frame(width: 28, height: 28)

                    if task.isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .scaleEffect(task.checkProgress)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.30, dampingFraction: 0.60), value: task.isChecked)

                // Labels
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: task.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(task.isChecked ? BUI.coral : BUI.inkSoft)
                        Text(task.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(task.isChecked ? BUI.coral : BUI.ink)
                    }
                    Text(task.subLabel)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(BUI.inkFaint)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(task.isChecked ? BUI.coraltint : BUI.pillSurface.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                task.isChecked ? BUI.coral.opacity(0.25) : BUI.pillBorder.opacity(0.45),
                                lineWidth: 0.75
                            )
                    )
            )
            // matchedGeometryEffect makes the pill slide smoothly rather than teleport
            .matchedGeometryEffect(id: task.id, in: namespace)
        }
        .buttonStyle(BereanCTAPressStyle())
    }
}

// MARK: Thinking dots

private struct BereanThinkingDots: View {
    @State private var active = 0
    let timer = Timer.publish(every: 0.38, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == active ? BUI.coral : BUI.inkFaint.opacity(0.40))
                    .frame(width: 5, height: 5)
                    .scaleEffect(i == active ? 1.3 : 1.0)
                    .animation(BUI.snap(), value: active)
            }
        }
        .onReceive(timer) { _ in
            active = (active + 1) % 3
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 3. BereanInputOverlay
// ─────────────────────────────────────────────────────────────────────────────
//
// Adaptation: Grok blurred menu overlay → Berean chat context.
//
// Tapping the "+" pill in the Berean input bar:
//   • The chat surface blurs (animated .blur modifier + dark scrim)
//   • A menu of Berean-specific quick actions fades+slides in with staggered delay
//   • Tapping anywhere outside dismisses with reverse animation
//
// Menu items are AMEN Berean context actions (not camera/photos — this is a
// scripture assistant): Bible Passage, Saved Prompts, Deep Study, Voice Input.

struct BereanInputOverlay: View {

    struct QuickAction: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let color: Color
    }

    private let actions: [QuickAction] = [
        .init(icon: "text.book.closed.fill",   label: "Bible Passage",   color: BUI.coral),
        .init(icon: "bookmark.fill",            label: "Saved Prompts",   color: Color(red: 0.38, green: 0.28, blue: 0.78)),
        .init(icon: "moon.stars.fill",          label: "Deep Study",      color: Color(red: 0.22, green: 0.44, blue: 0.36)),
        .init(icon: "waveform",                 label: "Voice Input",     color: Color(red: 0.58, green: 0.38, blue: 0.22))
    ]

    @State private var isMenuOpen = false
    @State private var messageText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── Base chat layer (blurs when menu is open) ─────────────────────
            chatBase
                .blur(radius: isMenuOpen ? 18 : 0)
                .animation(.spring(response: 0.40, dampingFraction: 0.82), value: isMenuOpen)

            // ── Dark scrim overlay ─────────────────────────────────────────────
            if isMenuOpen {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismissMenu() }
                    .animation(.easeInOut(duration: 0.22), value: isMenuOpen)
            }

            // ── Menu content (staggered items) ────────────────────────────────
            if isMenuOpen {
                VStack(alignment: .leading, spacing: 0) {

                    // "Recents >" breadcrumb
                    Text("Quick Actions  ›")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BUI.inkSoft)
                        .padding(.leading, BUI.hPad)
                        .padding(.bottom, 12)
                        .transition(fadeSlideTransition(delay: 0))

                    // Action items — staggered
                    VStack(spacing: 8) {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { i, action in
                            BereanQuickActionRow(action: action) {
                                dismissMenu()
                            }
                            .transition(
                                fadeSlideTransition(delay: Double(i) * 0.055)
                            )
                        }
                    }
                    .padding(.horizontal, BUI.hPad)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 100) // lift above input bar
                .animation(.spring(response: 0.42, dampingFraction: 0.76), value: isMenuOpen)
            }

            // ── Bottom input bar (always visible) ────────────────────────────
            inputBar
        }
        .background(BUI.bg.ignoresSafeArea())
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isMenuOpen)
    }

    // MARK: Chat base (simplified for overlay prototype)

    private var chatBase: some View {
        VStack(spacing: 0) {
            // Nav bar area
            HStack {
                Spacer()
                // "B" serif Berean wordmark
                Text("Berean")
                    .font(Font.custom("Georgia", size: 20).weight(.light))
                    .foregroundStyle(BUI.ink)
                Spacer()
            }
            .padding(.top, 12)
            .padding(.horizontal, BUI.hPad)

            // Suggested prompt chips
            VStack(spacing: 10) {
                ForEach(["Explain John 1:1", "What is the Trinity?", "Help me pray for peace"], id: \.self) { prompt in
                    Text(prompt)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(BUI.inkSoft)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(BUI.cardWhite)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(BUI.pillBorder.opacity(0.5), lineWidth: 0.75)
                                )
                        )
                }
            }
            .padding(.horizontal, BUI.hPad)
            .padding(.top, 32)

            Spacer()
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            // + button — toggles the overlay
            Button {
                if isMenuOpen { dismissMenu() } else { openMenu() }
            } label: {
                ZStack {
                    Circle()
                        .fill(isMenuOpen ? BUI.coral : BUI.pillSurface)
                        .overlay(
                            Circle()
                                .stroke(BUI.pillBorder.opacity(0.5), lineWidth: 0.75)
                        )
                    Image(systemName: isMenuOpen ? "xmark" : "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isMenuOpen ? .white : BUI.inkSoft)
                        .rotationEffect(.degrees(isMenuOpen ? 45 : 0))
                        .animation(BUI.snap(), value: isMenuOpen)
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(BereanCTAPressStyle())

            // Text field
            TextField("Ask anything…", text: $messageText)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(BUI.ink)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().stroke(BUI.pillBorder.opacity(0.40), lineWidth: 0.75))
                )

            // Send
            Button {} label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(BUI.coral))
            }
            .buttonStyle(BereanCTAPressStyle())
            .opacity(messageText.isEmpty ? 0.4 : 1.0)
            .animation(.easeOut(duration: 0.12), value: messageText.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.80), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: -4)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 20)
    }

    // MARK: Helpers

    private func openMenu() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        inputFocused = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            isMenuOpen = true
        }
    }

    private func dismissMenu() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
            isMenuOpen = false
        }
    }

    private func fadeSlideTransition(delay: Double) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity)
                       .animation(.spring(response: 0.42, dampingFraction: 0.76).delay(delay)),
            removal: .opacity.animation(.easeOut(duration: 0.14))
        )
    }
}

// MARK: Quick Action Row

private struct BereanQuickActionRow: View {
    let action: BereanInputOverlay.QuickAction
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(action.color.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: action.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(action.color)
                }
                Text(action.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BUI.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BUI.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BUI.cardWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(BUI.pillBorder.opacity(0.4), lineWidth: 0.75)
                    )
            )
        }
        .buttonStyle(BereanCTAPressStyle())
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 4. BereanMorphingToolbar
// ─────────────────────────────────────────────────────────────────────────────
//
// Adaptation: Morphing action-pill capsule toolbar → Berean input affordance.
//
// Resting state: white/offwhite capsule pill with three icon buttons:
//   [Personality Mode]  [Bible Translation]  [Response Depth]
//
// Active state: tapping "Response Depth" morphs the pill — it stretches
// smoothly to reveal a labelled active button (coral fill, white label).
// The other two icons shift left. Tapping again collapses back.
//
// References:
//   Image 44: dark active pill "Files" + two light icon pills in one capsule
//   IMG_1290: "Assign" pill with icon+label button in a card
//
// The "secret sauce": a Capsule() container with matchedGeometryEffect ID
// transitions between the collapsed and expanded geometry automatically,
// creating the stretching/elastic morph seen in the reference video.

struct BereanMorphingToolbar: View {

    @State private var isDepthExpanded = false
    @State private var selectedDepth: DepthMode = .balanced
    @Namespace private var toolbarNamespace

    enum DepthMode: String, CaseIterable {
        case quick   = "Quick"
        case balanced = "Study"
        case deep    = "Deep"
    }

    var body: some View {
        // Outer capsule container — the white pill from the reference
        HStack(spacing: 4) {

            // ── Left icon: Personality mode ────────────────────────────────────
            toolbarIconButton(icon: "person.fill", label: nil, isActive: false) {}

            // ── Center icon: Bible translation ────────────────────────────────
            toolbarIconButton(icon: "book.closed.fill", label: nil, isActive: false) {}

            // ── Right: Response depth — the morphing element ──────────────────
            if isDepthExpanded {
                // Expanded state: label + icon in a dark coral pill
                Button {
                    withAnimation(.spring(response: 0.50, dampingFraction: 0.70)) {
                        isDepthExpanded = false
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: depthIcon(selectedDepth))
                            .font(.system(size: 13, weight: .semibold))
                        Text(selectedDepth.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        // matchedGeometryEffect: the background container morphs
                        // from the small circle to this wide pill
                        Capsule()
                            .fill(BUI.coral)
                            .matchedGeometryEffect(id: "depthBG", in: toolbarNamespace)
                    )
                }
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.7).combined(with: .opacity),
                        removal:   .scale(scale: 0.7).combined(with: .opacity)
                    )
                )
            } else {
                // Collapsed: small icon circle
                Button {
                    withAnimation(.spring(response: 0.50, dampingFraction: 0.70)) {
                        isDepthExpanded = true
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Image(systemName: depthIcon(selectedDepth))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(BUI.ink.opacity(0.72))
                        .frame(width: 38, height: 38)
                        .background(
                            Circle()
                                .fill(BUI.pillSurface)
                                .matchedGeometryEffect(id: "depthBG", in: toolbarNamespace)
                        )
                }
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.7).combined(with: .opacity),
                        removal:   .scale(scale: 0.7).combined(with: .opacity)
                    )
                )
            }
        }
        .padding(5)
        .background(
            Capsule()
                .fill(BUI.cardWhite)
                .overlay(Capsule().stroke(BUI.pillBorder.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
                .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        )
        // Depth mode selector — appears below the toolbar when expanded
        .overlay(alignment: .bottom) {
            if isDepthExpanded {
                depthModeSelector
                    .offset(y: 56)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
                    .animation(BUI.bounce(), value: isDepthExpanded)
            }
        }
    }

    // MARK: Depth mode selector card

    private var depthModeSelector: some View {
        HStack(spacing: 6) {
            ForEach(DepthMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(BUI.snap()) { selectedDepth = mode }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: depthIcon(mode))
                            .font(.system(size: 10, weight: .semibold))
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(selectedDepth == mode ? .white : BUI.inkSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(selectedDepth == mode ? BUI.coral : BUI.pillSurface)
                            .overlay(
                                Capsule()
                                    .stroke(selectedDepth == mode ? .clear : BUI.pillBorder.opacity(0.45), lineWidth: 0.75)
                            )
                    )
                }
                .buttonStyle(BereanCTAPressStyle())
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(BUI.cardWhite)
                .overlay(Capsule().stroke(BUI.pillBorder.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 6)
        )
    }

    // MARK: Helpers

    @ViewBuilder
    private func toolbarIconButton(
        icon: String,
        label: String?,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isActive ? BUI.coral : BUI.ink.opacity(0.65))
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(isActive ? BUI.coraltint : BUI.pillSurface)
                        .overlay(
                            Circle()
                                .stroke(BUI.pillBorder.opacity(0.45), lineWidth: 0.75)
                        )
                )
        }
        .buttonStyle(BereanCTAPressStyle())
    }

    private func depthIcon(_ mode: DepthMode) -> String {
        switch mode {
        case .quick:    return "bolt.fill"
        case .balanced: return "equal.circle.fill"
        case .deep:     return "sparkles"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - BereanInteractiveDemoView (Preview host)
// ─────────────────────────────────────────────────────────────────────────────
//
// A standalone scrollable demo that presents all four components so they
// can be tested in one place. In production, each component is integrated
// individually into BereanAIAssistantView and BereanOnboardingView.

struct BereanInteractiveDemoView: View {
    @State private var showOnboarding = false

    var body: some View {
        ZStack {
            BUI.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {

                    // Section header
                    VStack(spacing: 4) {
                        Text("Berean")
                            .font(Font.custom("Georgia", size: 32).weight(.light))
                            .foregroundStyle(BUI.ink)
                        Text("Interactive UI components")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(BUI.inkFaint)
                    }
                    .padding(.top, 32)

                    // ── 1. Onboarding Flow ─────────────────────────────────────
                    sectionLabel("Onboarding Flow")

                    // Compact card preview — tap to open full onboarding
                    Button {
                        showOnboarding = true
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(BUI.coraltint)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(BUI.coral)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Begin Berean Onboarding")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(BUI.ink)
                                Text("4-step typographic flow with step dots")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(BUI.inkFaint)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BUI.inkFaint)
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: BUI.cardRadius, style: .continuous)
                                .fill(BUI.cardWhite)
                                .overlay(
                                    RoundedRectangle(cornerRadius: BUI.cardRadius, style: .continuous)
                                        .stroke(BUI.pillBorder.opacity(0.5), lineWidth: 0.75)
                                )
                                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                        )
                    }
                    .buttonStyle(BereanCTAPressStyle())
                    .padding(.horizontal, BUI.hPad)

                    // ── 2. Thinking Task Pills ─────────────────────────────────
                    sectionLabel("Thinking / Processing")
                    BereanThinkingTaskPills()
                        .padding(.horizontal, BUI.hPad)

                    // ── 3. Morphing Toolbar ────────────────────────────────────
                    sectionLabel("Morphing Input Toolbar")
                    VStack(spacing: 8) {
                        Text("Tap the rightmost icon to morph the pill")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(BUI.inkFaint)
                        BereanMorphingToolbar()
                    }
                    .padding(.bottom, 12)

                    // ── 4. Input Overlay (full screen demo) ────────────────────
                    sectionLabel("Blurred Input Overlay")
                    NavigationLink {
                        BereanInputOverlay()
                            .navigationBarHidden(true)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(BUI.violet.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(BUI.violet)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open Input Overlay Demo")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(BUI.ink)
                                Text("Tap + in the input bar to trigger blur menu")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(BUI.inkFaint)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BUI.inkFaint)
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: BUI.cardRadius, style: .continuous)
                                .fill(BUI.cardWhite)
                                .overlay(
                                    RoundedRectangle(cornerRadius: BUI.cardRadius, style: .continuous)
                                        .stroke(BUI.pillBorder.opacity(0.5), lineWidth: 0.75)
                                )
                                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                        )
                    }
                    .buttonStyle(BereanCTAPressStyle())
                    .padding(.horizontal, BUI.hPad)

                    Spacer(minLength: 60)
                }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            BereanOnboardingFlow()
        }
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(BUI.inkFaint)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BUI.hPad)
            .padding(.top, 6)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────────────────────────────────────

#Preview {
    NavigationStack {
        BereanInteractiveDemoView()
    }
}

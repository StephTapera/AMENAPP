// AILAccessibilitySetupView.swift
// AMENAPP — Accessibility Intelligence Layer (AIL)
//
// A one-time, friendly walkthrough that introduces the accessibility options in
// warm, plain language. Each choice is written straight through the frozen
// AILProfileService setters, so nothing is stored here — the profile follows the
// account (UserDefaults + Firestore) automatically.
//
// Shows once: gated by @AppStorage("ail.setup.completed.v1"). A "Skip" path and a
// final "Done" both mark it complete. Everything can be changed later in Settings.
//
// IRON RULES (do not relax):
//  • Accessibility is FREE at every tier. No copy implies an upgrade or paywall,
//    and there are NO tier checks. The closing copy says so out loud.
//  • Profile portability: all state lives in AILProfileService.shared.
//  • Plain-language copy throughout — warm and concrete, no jargon.
//  • Reduce Transparency → opaque surfaces.

import SwiftUI

// MARK: - AILAccessibilitySetupView

struct AILAccessibilitySetupView: View {

    /// Marks the walkthrough as seen so it only appears once per install/account.
    @AppStorage("ail.setup.completed.v1") private var setupCompleted = false

    /// The frozen, account-synced profile service.
    @State private var service = AILProfileService.shared

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var step = 0

    /// Ordered walkthrough steps.
    private let lastStep = 5

    var body: some View {
        @Bindable var bindable = service

        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $step) {
                    welcomeStep.tag(0)
                    readingStep.tag(1)
                    translateStep.tag(2)
                    calmStep.tag(3)
                    buttonsStep.tag(4)
                    doneStep.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .animation(reduceTransparency ? nil : .easeInOut, value: step)

                controls
            }
            .background(stepBackground)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { finish() }
                        .accessibilityHint("Closes the walkthrough. You can change any setting later.")
                }
            }
        }
    }

    // MARK: - Background (opaque under Reduce Transparency)

    @ViewBuilder
    private var stepBackground: some View {
        if reduceTransparency {
            Color(.systemBackground).ignoresSafeArea()
        } else {
            Color(.systemGroupedBackground).ignoresSafeArea()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        stepScaffold(
            symbol: "hand.wave",
            title: "Let's make this comfortable",
            body: "A few quick choices to help the app fit you. These options are free for everyone, and you can change them anytime."
        ) {
            EmptyView()
        }
    }

    private var readingStep: some View {
        stepScaffold(
            symbol: "textformat.alt",
            title: "How would you like posts written?",
            body: "We can keep the author's words, or rewrite them in plainer language. Scripture is always shown as written."
        ) {
            Picker("Reading Level", selection: Binding(
                get: { service.profile.readingLevel },
                set: { service.setReadingLevel($0) }
            )) {
                ForEach(ReadingLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Choose how plainly posts are written for you.")
        }
    }

    private var translateStep: some View {
        stepScaffold(
            symbol: "character.bubble",
            title: "Want posts in your language?",
            body: "When something is written in another language, we can translate it for you automatically."
        ) {
            Toggle("Translate posts automatically", isOn: Binding(
                get: { service.profile.autoTranslate },
                set: { service.setAutoTranslate($0) }
            ))
            .accessibilityHint("When on, posts in other languages are translated for you.")
        }
    }

    private var calmStep: some View {
        stepScaffold(
            symbol: "leaf",
            title: "Prefer a calmer screen?",
            body: "Calm Mode quiets things down — less motion and fewer things competing for your attention."
        ) {
            Toggle("Turn on Calm Mode", isOn: Binding(
                get: { service.profile.calmMode },
                set: { service.setCalmMode($0) }
            ))
            .accessibilityHint("When on, the app uses calmer visuals with less movement.")
        }
    }

    private var buttonsStep: some View {
        stepScaffold(
            symbol: "hand.point.up.left",
            title: "Want larger, easier buttons?",
            body: "Make buttons and tap areas bigger so they're easier to reach. You can fine-tune this later, right on your phone."
        ) {
            Picker("Button size", selection: Binding(
                get: { service.profile.largerTouchTargets },
                set: { service.setTouchTargets($0) }
            )) {
                ForEach(A11yProfile.TouchTargets.allCases, id: \.self) { size in
                    Text(touchTargetName(size)).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Choose a comfortable tap size.")
        }
    }

    private var doneStep: some View {
        stepScaffold(
            symbol: "checkmark.seal",
            title: "You're all set",
            body: "That's it. These options are free for everyone and you can change any of them anytime in Settings."
        ) {
            VStack(spacing: 12) {
                Button {
                    finish()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Saves your choices and closes the walkthrough.")
            }
        }
    }

    // MARK: - Step scaffold (shared layout)

    private func stepScaffold<Content: View>(
        symbol: String,
        title: String,
        body: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .padding(.top, 36)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                content()
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Bottom controls

    private var controls: some View {
        HStack {
            if step > 0 {
                Button("Back") {
                    withAnimation(reduceTransparency ? nil : .easeInOut) {
                        step = max(0, step - 1)
                    }
                }
            }
            Spacer()
            if step < lastStep {
                Button("Next") {
                    withAnimation(reduceTransparency ? nil : .easeInOut) {
                        step = min(lastStep, step + 1)
                    }
                }
                .font(.headline)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(controlsBackground)
    }

    @ViewBuilder
    private var controlsBackground: some View {
        if reduceTransparency {
            Color(.systemBackground).ignoresSafeArea(edges: .bottom)
        } else {
            Color(.systemGroupedBackground).opacity(0.0)
        }
    }

    // MARK: - Completion

    private func finish() {
        setupCompleted = true
        dismiss()
    }

    // MARK: - Plain-language helpers

    private func touchTargetName(_ value: A11yProfile.TouchTargets) -> String {
        switch value {
        case .off:   return "Normal"
        case .large: return "Large"
        case .xl:    return "Extra Large"
        }
    }
}

// MARK: - Preview

#Preview("AILAccessibilitySetupView") {
    AILAccessibilitySetupView()
}

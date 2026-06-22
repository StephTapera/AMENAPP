// BereanOSOnboardingView.swift
// AMENAPP — Berean OS
//
// Three-screen first-run onboarding for the Berean Wisdom Operating System.
// Completion is recorded in UserDefaults under "bereanOSOnboardingCompleted".

import SwiftUI

// MARK: - BereanOSOnboardingView

struct BereanOSOnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0

    private let pages: [(icon: String, title: String, body: String)] = [
        (
            "brain.head.profile",
            "Berean OS",
            "Research anything. Build knowledge projects. Make better decisions. Grounded in truth and your values."
        ),
        (
            "magnifyingglass",
            "From Questions to Knowledge",
            "Create projects that remember context. Run research that cites sources. Get multi-perspective analysis on any decision."
        ),
        (
            "checkmark.shield.fill",
            "Wisdom, Not Just Answers",
            "Every AI response shows its confidence level. Every claim is traceable. You stay in control."
        )
    ]

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 24) {
                        Spacer()

                        Image(systemName: pages[i].icon)
                            .font(.systemScaled(72))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)

                        Text(pages[i].title)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)

                        Text(pages[i].body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Spacer()

                        if i == pages.count - 1 {
                            Button("Get Started") {
                                markCompleted()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityLabel("Get started with Berean OS")
                        } else {
                            Button("Continue") {
                                withAnimation {
                                    currentPage = i + 1
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityLabel("Continue to next page")
                        }

                        Spacer().frame(height: 40)
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .animation(.easeInOut, value: currentPage)

            // Skip button
            Button("Skip") {
                markCompleted()
            }
            .padding()
            .accessibilityLabel("Skip onboarding")
        }
    }

    // MARK: - Private

    private func markCompleted() {
        UserDefaults.standard.set(true, forKey: "bereanOSOnboardingCompleted")
        isPresented = false
    }
}

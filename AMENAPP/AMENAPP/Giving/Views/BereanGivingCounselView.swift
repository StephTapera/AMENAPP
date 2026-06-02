// BereanGivingCounselView.swift
// AMENAPP
//
// Berean as a giving discernment guide — not a conversion funnel.
// Calm, inspectable, source-grounded recommendations.
// Never promises blessing. Never pressures. Always allows "reflect first."

import SwiftUI

struct BereanGivingCounselView: View {
    let profile: GivingProfile
    let candidates: [GivingOrganization]
    let initialBudget: Int

    @StateObject private var vm = BereanGivingViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var promptFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Header
                    bereanHeader

                    // Budget selector
                    budgetSelector

                    // Custom prompt
                    promptInput

                    // Submit button
                    if vm.response == nil || vm.isLoading {
                        submitButton
                    }

                    // Response
                    if vm.isLoading {
                        loadingView
                    } else if let response = vm.response {
                        responseView(response)
                    }

                    // Guardrail note
                    guardrailNote
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Berean Counsel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if vm.response != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("New session") { vm.clearSession() }
                    }
                }
            }
        }
        .onAppear {
            vm.profile = profile
            vm.candidates = candidates
            vm.budgetDollars = initialBudget
        }
    }

    // MARK: - Berean Header

    private var bereanHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.25, green: 0.20, blue: 0.10),
                                Color(red: 0.55, green: 0.42, blue: 0.15),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text("Berean Giving Counsel")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text("Discernment guide, not a fundraiser.")
                    .font(.system(size: 13))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            Spacer()
        }
        .padding(16)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        )
    }

    // MARK: - Budget Selector

    private var budgetSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Monthly budget")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(1.2)

            HStack(spacing: 8) {
                ForEach(vm.budgetOptions, id: \.self) { amount in
                    Button {
                        withAnimation(.spring(duration: 0.22)) {
                            vm.budgetDollars = amount
                        }
                    } label: {
                        Text("$\(amount)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(vm.budgetDollars == amount ? AmenTheme.Colors.textInverse : AmenTheme.Colors.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(vm.budgetDollars == amount
                                          ? AmenTheme.Colors.textPrimary
                                          : AmenTheme.Colors.backgroundSecondary)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(vm.budgetDollars == amount ? [.isSelected] : [])
                }
            }
        }
    }

    // MARK: - Prompt Input

    private var promptInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Or ask something specific")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(1.2)

            TextField(
                "e.g. I want to give locally. What makes sense?",
                text: $vm.promptText,
                axis: .vertical
            )
            .font(.system(size: 15))
            .focused($promptFocused)
            .padding(14)
            .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .lineLimit(1...4)
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            promptFocused = false
            Task { await vm.submitPrompt() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                Text(vm.promptText.isEmpty
                     ? "Ask Berean about $\(vm.budgetDollars)"
                     : "Get counsel")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(AmenTheme.Colors.textInverse)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AmenTheme.Colors.buttonPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(vm.isLoading)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Berean is thinking…")
                .font(.system(size: 14))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("Checking verified organizations against your values.")
                .font(.system(size: 12))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Response

    private func responseView(_ response: BereanGivingResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary
            VStack(alignment: .leading, spacing: 6) {
                Label("What Berean heard", systemImage: "ear")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                Text(response.summary)
                    .font(.system(size: 15))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineSpacing(3)
            }
            .padding(14)
            .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Recommendations
            ForEach(response.recommendations) { rec in
                recommendationCard(rec)
            }

            // Closing reflection
            VStack(alignment: .leading, spacing: 6) {
                Label("A closing thought", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                Text(response.closingReflection)
                    .font(.system(size: 14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .italic()
                    .lineSpacing(2)
                Text("Take your time.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .padding(14)
            .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func recommendationCard(_ rec: BereanGivingRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Fit label
            HStack {
                Text(rec.fitLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                Spacer()
                if rec.destinationType == .reflect {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }

            // Org name or type
            if let org = rec.org {
                Text(org.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            } else if rec.destinationType == .reflect {
                Text("Reflect first")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }

            // Reason
            Text(rec.reason)
                .font(.system(size: 14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineSpacing(2)

            // Scripture (collapsible)
            if let ref = rec.scriptureRef, let text = rec.scriptureText {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        vm.toggleScripture(id: rec.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                            Text(ref)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                            Image(systemName: vm.showScripture.contains(rec.id) ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    if vm.showScripture.contains(rec.id) {
                        Text("\u{201C}\(text)\u{201D}")
                            .font(.custom("Georgia", size: 14))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .italic()
                            .lineSpacing(3)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.spring(duration: 0.24), value: vm.showScripture.contains(rec.id))
            }

            // Action buttons
            if rec.destinationType != .reflect {
                HStack(spacing: 8) {
                    if let org = rec.org, let donationUrl = org.donationUrl, let url = URL(string: donationUrl) {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            Text(rec.actionLabel)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AmenTheme.Colors.textInverse)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(AmenTheme.Colors.buttonPrimary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {} label: {
                        Text("Save for later")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(AmenTheme.Colors.backgroundSecondary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        )
        .amenShadow(radius: 8, y: 3)
    }

    // MARK: - Guardrail Note

    private var guardrailNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "shield.fill")
                .font(.system(size: 11))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("Berean never promises blessing or reward for giving. It only recommends organizations with verified transparency data. All recommendations are inspectable.")
                .font(.system(size: 11))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .lineSpacing(2)
        }
        .padding(12)
        .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

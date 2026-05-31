//
//  FindYourPeopleFTUEView.swift
//  AMENAPP
//
//  "Find Your People" first-time onboarding sheet.
//
//  Step 0 — Church: typed church name search, optional skip
//  Step 1 — Interests: checkboxes (Scripture Study, Prayer, Community,
//                                   Testimonies, Worship, Bible Study,
//                                   Church Life, Theology)
//  Step 2 — Personalized discovery: PeopleDiscoveryView with church +
//            interest sections seeded immediately
//
//  Design language: ONB tokens (white Liquid Glass) to match the rest
//  of AMEN onboarding.  No blue system tints.
//

import SwiftUI
import CoreLocation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Interest Options

private let kDiscoveryInterests: [(icon: String, label: String)] = [
    ("book.closed.fill",          "Scripture Study"),
    ("hands.sparkles.fill",       "Prayer"),
    ("person.2.fill",             "Community"),
    ("star.fill",                 "Testimonies"),
    ("music.note",                "Worship"),
    ("lightbulb.fill",            "Bible Study"),
    ("building.columns.fill",     "Church Life"),
    ("text.book.closed.fill",     "Theology"),
]

// MARK: - Main FTUE View

struct FindYourPeopleFTUEView: View {

    // Callback once the FTUE finishes (with or without data).
    var onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ftueManager = FTUEPeopleDiscoveryManager.shared

    @State private var step: Int = 0

    // Step 0 — Church
    @State private var churchQuery: String = ""
    @State private var churchSuggestions: [SmartChurchSummary] = []
    @State private var selectedChurchName: String = ""
    @State private var selectedChurchId: String = ""
    @State private var isSearchingChurch = false
    @State private var churchSearchTask: Task<Void, Never>?

    // Step 1 — Interests
    @State private var selectedInterests: Set<String> = []

    // Step 2 — Discovery (shown inline after saving)
    @State private var showDiscovery = false
    @State private var isSaving = false

    // Animation
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                ONB.canvas.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress dots
                    ONBPageDots(total: 3, current: step)
                        .padding(.top, 20)

                    // Step content
                    ZStack {
                        if step == 0 {
                            ONBStepTransition(step: 0) { churchStep }
                        } else if step == 1 {
                            ONBStepTransition(step: 1) { interestsStep }
                        } else {
                            ONBStepTransition(step: 2) { discoveryStep }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { skipAll() }
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(ONB.inkTertiary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if step > 0 && step < 2 {
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.82))) {
                                step -= 1
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.systemScaled(16, weight: .medium))
                                .foregroundStyle(ONB.inkSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Step 0: Church

    private var churchStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 28)

                // Hero icon
                AmenOnboardingHeroIcon(systemName: "building.columns.fill", accent: ONB.accentGold)
                    .padding(.leading, ONB.pagePadding)

                Spacer().frame(height: 20)

                ONBHeroText(
                    headline: "Find your church community.",
                    subheadline: "We'll show you people from your church first. You can skip and find them later."
                )
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 28)

                // Search field (plain ONBGlassCard around a TextField)
                ONBGlassCard(padding: .init(top: 0, leading: 0, bottom: 0, trailing: 0)) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ONB.inkTertiary)
                            .padding(.leading, 16)
                        TextField("Search your church name…", text: $churchQuery)
                            .font(.systemScaled(16, weight: .regular))
                            .foregroundStyle(ONB.inkPrimary)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .onChange(of: churchQuery) { _, newVal in
                                selectedChurchName = ""
                                selectedChurchId   = ""
                                scheduleChurchSearch(query: newVal)
                            }
                        if !churchQuery.isEmpty {
                            Button { churchQuery = ""; churchSuggestions = [] } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.systemScaled(15))
                                    .foregroundStyle(ONB.inkTertiary)
                            }
                            .padding(.trailing, 12)
                        }
                    }
                    .frame(height: 52)
                }
                .padding(.horizontal, ONB.pagePadding)

                // Suggestions dropdown
                if !churchSuggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(churchSuggestions.prefix(5)) { church in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedChurchName = church.name
                                selectedChurchId   = church.id
                                churchQuery        = church.name
                                churchSuggestions  = []
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(ONB.accentGold.opacity(0.12))
                                            .frame(width: 34, height: 34)
                                        Image(systemName: "building.columns.fill")
                                            .font(.systemScaled(13, weight: .medium))
                                            .foregroundStyle(ONB.accentGold)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(church.name)
                                            .font(.systemScaled(14, weight: .semibold))
                                            .foregroundStyle(ONB.inkPrimary)
                                        if !church.address.isEmpty {
                                            Text(church.address)
                                                .font(.systemScaled(12, weight: .regular))
                                                .foregroundStyle(ONB.inkTertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if selectedChurchId == church.id {
                                        Image(systemName: "checkmark")
                                            .font(.systemScaled(12, weight: .semibold))
                                            .foregroundStyle(ONB.accent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if church.id != churchSuggestions.prefix(5).last?.id {
                                Divider().padding(.leading, 62)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: ONB.cardRadius, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: ONB.cardRadius).fill(ONB.glassFill))
                            .overlay(RoundedRectangle(cornerRadius: ONB.cardRadius).strokeBorder(ONB.glassBorder, lineWidth: 1))
                    )
                    .shadow(color: ONB.glassShadow, radius: 10, y: 3)
                    .padding(.horizontal, ONB.pagePadding)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if isSearchingChurch {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.75)
                        Text("Searching…")
                            .font(.systemScaled(13))
                            .foregroundStyle(ONB.inkTertiary)
                    }
                    .padding(.horizontal, ONB.pagePadding)
                    .padding(.top, 10)
                }

                Spacer().frame(height: 40)

                ONBPrimaryButton(
                    title: selectedChurchName.isEmpty ? "Skip for now" : "Continue",
                    trailingIcon: selectedChurchName.isEmpty ? "" : "arrow.right"
                ) {
                    advanceToInterests()
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 48)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Step 1: Interests

    private var interestsStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 28)

                AmenOnboardingHeroIcon(systemName: "sparkles", accent: ONB.accent)
                    .padding(.leading, ONB.pagePadding)

                Spacer().frame(height: 20)

                ONBHeroText(
                    headline: "What brings you to AMEN?",
                    subheadline: "We'll suggest people who share your spiritual focus. Pick as many as you like."
                )
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 28)

                // 2-column chip grid
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(kDiscoveryInterests, id: \.label) { item in
                        InterestChipButton(
                            icon: item.icon,
                            label: item.label,
                            isSelected: selectedInterests.contains(item.label)
                        ) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if selectedInterests.contains(item.label) {
                                selectedInterests.remove(item.label)
                            } else {
                                selectedInterests.insert(item.label)
                            }
                        }
                    }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 36)

                ONBPrimaryButton(
                    title: "Find My People",
                    isLoading: isSaving,
                    isEnabled: true,
                    trailingIcon: "arrow.right"
                ) {
                    Task { await saveAndProceed() }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 12)

                ONBSecondaryButton(title: "Skip interests") { Task { await saveAndProceed() } }
                    .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 48)
            }
        }
    }

    // MARK: - Step 2: Personalized Discovery

    private var discoveryStep: some View {
        PeopleDiscoveryViewNew()
            .overlay(alignment: .bottom) {
                // Sticky "Done" pill so the user can exit the sheet
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    dismiss()
                    onComplete()
                } label: {
                    Text("Done — go to my feed")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(ONB.inkPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.regularMaterial)
                                .overlay(Capsule(style: .continuous).fill(Color.black.opacity(0.05)))
                                .overlay(Capsule(style: .continuous).fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.60), Color.white.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                ))
                                .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.55), lineWidth: 1))
                                .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
                                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
                .background(
                    LinearGradient(
                        colors: [ONB.canvas.opacity(0), ONB.canvas],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 110)
                    .allowsHitTesting(false)
                    .padding(.bottom, -24),
                    alignment: .bottom
                )
            }
    }

    // MARK: - Helpers

    private func advanceToInterests() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.82))) {
            step = 1
        }
    }

    private func saveAndProceed() async {
        guard !isSaving else { return }
        isSaving = true
        await ftueManager.complete(
            churchName: selectedChurchName,
            churchId:   selectedChurchId,
            interests:  Array(selectedInterests)
        )
        isSaving = false
        withAnimation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.82))) {
            step = 2
        }
    }

    private func skipAll() {
        ftueManager.markCompleted()
        dismiss()
        onComplete()
    }

    private func scheduleChurchSearch(query: String) {
        churchSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            churchSuggestions = []
            return
        }
        churchSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearchingChurch = true }
            do {
                let items = try await SmartChurchSearchService.shared.keywordSearch(query: trimmed)
                await MainActor.run {
                    churchSuggestions = items.map(\.church)
                    isSearchingChurch = false
                }
            } catch {
                await MainActor.run { isSearchingChurch = false }
            }
        }
    }
}

// MARK: - Interest Chip Button

private struct InterestChipButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : ONB.accent)
                Text(label)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : ONB.inkPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? ONB.accent : ONB.glassFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.clear : ONB.glassBorder, lineWidth: 1)
                    )
                    .shadow(color: isSelected ? ONB.accent.opacity(0.25) : ONB.glassShadow, radius: 6, y: 2)
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isSelected)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

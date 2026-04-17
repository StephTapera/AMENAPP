// BereanOnboardingComponents.swift
// AMENAPP — Berean Onboarding V3
// Step content views and reusable onboarding components.

import SwiftUI

// MARK: - Step 1

struct BereanStep1View: View {
    let content: BereanOnboardingContent
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            BereanGlassOrb(icon: "cross", size: 110, iconSize: 38, pulse: true)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)

            Text(content.step1Title)
                .font(BereanType.displayTitle())
                .foregroundStyle(BereanColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            Text(content.step1Subtitle)
                .font(BereanType.headline())
                .foregroundStyle(BereanColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(content.step1Bullets.enumerated()), id: \.offset) { _, bullet in
                    BereanBulletRow(text: bullet)
                }
            }
            .bereanGlassCard()
        }
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                appeared = true
            }
        }
    }
}

// MARK: - Step 2

struct BereanStep2View: View {
    let content: BereanOnboardingContent
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(content.step2Title)
                .font(BereanType.sectionTitle())
                .foregroundStyle(BereanColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            VStack(spacing: 2) {
                ForEach(Array(content.step2Features.enumerated()), id: \.offset) { _, feature in
                    BereanFeatureRow(icon: feature.icon, title: feature.title, desc: feature.description)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                appeared = true
            }
        }
    }
}

// MARK: - Step 3

struct BereanStep3View: View {
    let content: BereanOnboardingContent
    let selectedFocuses: Set<BereanFocus>
    let onToggle: (BereanFocus) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appeared = false

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(content.step3Title)
                .font(BereanType.sectionTitle())
                .foregroundStyle(BereanColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)

            Text(content.step3Subtitle)
                .font(BereanType.subheadline())
                .foregroundStyle(BereanColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(BereanFocus.allCases.enumerated()), id: \.element.id) { _, focus in
                    BereanFocusCard(
                        focus: focus,
                        isSelected: selectedFocuses.contains(focus),
                        onTap: { onToggle(focus) }
                    )
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                }
            }
            .padding(.bottom, 16)

            Text(content.step3Footnote)
                .font(BereanType.caption())
                .foregroundStyle(BereanColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }
}

// MARK: - Step 4

struct BereanStep4View: View {
    let content: BereanOnboardingContent
    let selectedFocuses: Set<BereanFocus>
    let starterContext: BereanStarterContext

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appeared = false

    private var displayChips: [String] {
        selectedFocuses.isEmpty ? content.step4Defaults : selectedFocuses.map(\.label).sorted()
    }

    private var strengthColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 10)]
            : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    var body: some View {
        VStack(spacing: 0) {
            BereanGlassOrb(icon: "checkmark", size: 110, iconSize: 32, pulse: true)
                .padding(.top, 8)
                .padding(.bottom, 26)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)

            Text(content.step4Title)
                .font(BereanType.displayTitle())
                .foregroundStyle(BereanColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            Text(content.step4Subtitle)
                .font(BereanType.headline())
                .foregroundStyle(BereanColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            BereanChipWrap(labels: displayChips)
                .padding(.bottom, 16)

            Text(starterContext.greetingVariant)
                .font(BereanType.caption())
                .foregroundStyle(BereanColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            LazyVGrid(columns: strengthColumns, spacing: 10) {
                ForEach(content.step4Strengths, id: \.label) { strength in
                    BereanStrengthTile(icon: strength.icon, label: strength.label)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                appeared = true
            }
        }
    }
}

// MARK: - Rows

struct BereanBulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 5, height: 5)
                .padding(.top, 6)
                .accessibilityHidden(true)

            Text(text)
                .font(BereanType.subheadline())
                .foregroundStyle(BereanColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct BereanFeatureRow: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            BereanGlassIconTile(icon: icon)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(BereanType.subheadline())
                    .foregroundStyle(BereanColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(desc)
                    .font(BereanType.caption())
                    .foregroundStyle(BereanColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(desc)")
    }
}

// MARK: - Cards

struct BereanFocusCard: View {
    let focus: BereanFocus
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: focus.icon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(isSelected ? BereanColor.selectedText : BereanColor.textPrimary)

                Text(focus.label)
                    .font(BereanType.subheadline())
                    .foregroundStyle(isSelected ? BereanColor.selectedText : BereanColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(background)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(focus.label)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("berean_focus_\(focus.rawValue.lowercased())")
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BereanColor.selectedFill)
                .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BereanColor.glassFill))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                )
        }
    }
}

struct BereanStrengthTile: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(BereanColor.textSecondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(label)
                .font(BereanType.caption())
                .foregroundStyle(BereanColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BereanColor.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Chips

struct BereanChipWrap: View {
    let labels: [String]

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 8) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(BereanType.caption())
                    .foregroundStyle(BereanColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .bereanGlassCapsule()
            }
        }
    }
}

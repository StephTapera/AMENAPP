// FindChurch2MatchBadgeView.swift
// AMENAPP — Find Church 2.0, Wave 3
//
// Match badge chip + "Why this church?" explanation sheet.
// Feature-gated by findChurch2_matchExplain (AMENFeatureFlags.shared.findChurch2MatchExplainEnabled).
// Falls back to a simple FitScore-style chip when the flag is off.
//
// Design rules:
//   - Glass: .ultraThinMaterial / .thinMaterial only — no custom Color + opacity stack
//   - No glass-on-glass nesting
//   - Luminous border: Color.white.opacity(0.45) at 0.5pt
//   - Shadow: radius 4, y 2, opacity 0.10
//   - Interactive targets ≥ 44×44pt
//   - @Environment(\.accessibilityReduceMotion) guards all animations
//   - Dynamic Type: .font(.system(.<style>)) — no fixed sizes

import SwiftUI
import Foundation

// MARK: - SF Symbol map for ReasonCategory

private extension MatchExplanation.ReasonChip.ReasonCategory {
    var systemImage: String {
        switch self {
        case .distance:      return "location.fill"
        case .serviceTime:   return "clock.fill"
        case .denomination:  return "building.columns.fill"
        case .worshipStyle:  return "music.note"
        case .lifeStage:     return "person.2.fill"
        case .language:      return "globe"
        case .accessibility: return "figure.roll"
        case .familyFit:     return "house.fill"
        case .community:     return "person.3.fill"
        case .beliefs:       return "book.closed.fill"
        case .custom:        return "sparkles"
        }
    }
}

// MARK: - FindChurch2MatchBadge

/// Small pill chip showing match score. Tapping opens the full explanation sheet.
/// Falls back to a minimal score chip when findChurch2_matchExplain is OFF.
struct FindChurch2MatchBadge: View {
    let match: MatchExplanation
    let showExplainSheet: Bool   // pass AMENFeatureFlags.shared.findChurch2MatchExplainEnabled

    @State private var isSheetPresented = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if showExplainSheet {
            explainBadge
                .sheet(isPresented: $isSheetPresented) {
                    FindChurch2WhyThisChurchSheet(match: match, isPresented: $isSheetPresented)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
        } else {
            simpleBadge
        }
    }

    // Full explain badge — tappable
    private var explainBadge: some View {
        Button {
            isSheetPresented = true
        } label: {
            badgeLabel
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Match score \(match.score) percent. \(match.badgeText). Tap for explanation.")
        .accessibilityHint("Opens why this church was recommended")
    }

    // Simple fallback badge — not tappable
    private var simpleBadge: some View {
        badgeLabel
            .accessibilityLabel("Match score \(match.score) percent. \(match.badgeText).")
    }

    private var badgeLabel: some View {
        HStack(spacing: 4) {
            Text("\(match.score)%")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(scoreColor)
            Text("·")
                .font(.system(.caption))
                .foregroundStyle(.secondary)
            Text(match.badgeText)
                .font(.system(.caption).weight(.medium))
                .foregroundStyle(.primary)
            if showExplainSheet {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(pillBackground)
        .overlay(pillBorder)
        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private var pillBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous).fill(Color(.systemBackground))
        } else {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
        }
    }

    private var pillBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
    }

    private var scoreColor: Color {
        switch match.score {
        case 80...: return Color(red: 1.0, green: 0.78, blue: 0.22)   // gold
        case 60..<80: return Color.green
        default:    return Color.secondary
        }
    }
}

// MARK: - FindChurch2WhyThisChurchSheet

/// Full explanation sheet presented as .sheet above a card.
/// One glass card surface — no nested glass backgrounds.
struct FindChurch2WhyThisChurchSheet: View {
    let match: MatchExplanation
    @Binding var isPresented: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    scoreCircle
                    reasonsSection
                    if !match.mismatches.isEmpty {
                        mismatchesSection
                    }
                    bereanCaption
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(sheetBackground)
            .navigationTitle("Why this church?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                        .font(.system(.body).weight(.semibold))
                }
            }
            .safeAreaInset(edge: .bottom) {
                findFitButton
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(footerBackground)
            }
        }
    }

    // MARK: Score circle

    private var scoreCircle: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 1.0, green: 0.78, blue: 0.22),
                                Color(red: 1.0, green: 0.55, blue: 0.10),
                                Color(red: 1.0, green: 0.78, blue: 0.22)
                            ],
                            center: .center
                        ),
                        lineWidth: 5
                    )
                    .frame(width: 88, height: 88)

                VStack(spacing: 2) {
                    Text("\(match.score)%")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.78, blue: 0.22),
                                    Color(red: 0.85, green: 0.55, blue: 0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .shadow(color: Color(red: 1.0, green: 0.78, blue: 0.22).opacity(0.30), radius: 12, x: 0, y: 4)

            Text(match.badgeText)
                .font(.system(.title3).weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Match score \(match.score) percent. \(match.badgeText).")
    }

    // MARK: Reasons section

    private var reasonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why this church")
                .font(.system(.headline))
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                ForEach(match.topReasons) { chip in
                    ReasonChipRow(chip: chip)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Mismatches section

    private var mismatchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A few differences")
                .font(.system(.headline))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(match.mismatches) { chip in
                    ReasonChipRow(chip: chip)
                }
            }

            Text("Every church is a tradeoff. These are honest differences, not disqualifiers.")
                .font(.system(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Berean caption

    private var bereanCaption: some View {
        let caption: String = {
            switch match.generatedBy {
            case "berean": return "Reviewed by Berean AI based on your preferences"
            case "server": return "Based on your preferences and usage patterns"
            default:       return "Based on your preferences"
            }
        }()

        return HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(.caption2))
                .foregroundStyle(.secondary)
            Text(caption)
                .font(.system(.caption))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 8)
    }

    // MARK: Find fit button

    private var findFitButton: some View {
        Button {
            isPresented = false
        } label: {
            Text("Find your fit")
                .font(.system(.body).weight(.semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.82, blue: 0.28),
                                    Color(red: 1.0, green: 0.60, blue: 0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Find your fit")
        .accessibilityHint("Dismisses this explanation")
    }

    // MARK: Backgrounds

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency {
            Color(.systemBackground).ignoresSafeArea()
        } else {
            Rectangle()
                .fill(.thinMaterial)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var footerBackground: some View {
        if reduceTransparency {
            Color(.systemBackground).ignoresSafeArea(edges: .bottom)
        } else {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - ReasonChipRow (private)

private struct ReasonChipRow: View {
    let chip: MatchExplanation.ReasonChip

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: chip.category.systemImage)
                .font(.system(.subheadline))
                .foregroundStyle(chip.isPositive ? Color.green : Color.orange)
                .frame(width: 28, height: 28)
                .background(iconBackground(isPositive: chip.isPositive))
                .clipShape(Circle())
                .accessibilityHidden(true)

            Text(chip.label)
                .font(.system(.subheadline))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            if chip.weight > 0.6 {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.22))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground)
        .overlay(rowBorder)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chip.isPositive ? "Match: \(chip.label)" : "Difference: \(chip.label)")
    }

    @ViewBuilder
    private func iconBackground(isPositive: Bool) -> some View {
        if isPositive {
            Color.green.opacity(0.15)
        } else {
            Color.orange.opacity(0.15)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Match Badge — explain ON") {
    let match = MatchExplanation(
        score: 82,
        topReasons: [
            .init(category: .distance, label: "1.4 mi away", weight: 0.9, isPositive: true),
            .init(category: .serviceTime, label: "Sunday 10:30 AM", weight: 0.8, isPositive: true),
            .init(category: .worshipStyle, label: "Contemporary worship", weight: 0.7, isPositive: true)
        ],
        mismatches: [
            .init(category: .language, label: "English only (no Spanish)", weight: 0.3, isPositive: false)
        ],
        generatedBy: "berean",
        generatedAt: Date()
    )
    return FindChurch2MatchBadge(match: match, showExplainSheet: true)
        .padding()
}

#Preview("Match Badge — explain OFF") {
    let match = MatchExplanation(
        score: 64,
        topReasons: [
            .init(category: .distance, label: "3.2 mi away", weight: 0.6, isPositive: true),
            .init(category: .denomination, label: "Non-denominational", weight: 0.5, isPositive: true)
        ],
        mismatches: [],
        generatedBy: "local",
        generatedAt: Date()
    )
    return FindChurch2MatchBadge(match: match, showExplainSheet: false)
        .padding()
}
#endif

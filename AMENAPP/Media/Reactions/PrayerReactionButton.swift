import SwiftUI

// MARK: - MediaPrayerReactionButton
// Folded-hands 🙏 button with gold accent that presents a GlassSheet (.small)
// letting the user choose a prayer expiry: None / 1 h / 24 h / 7 d.

@MainActor
struct MediaPrayerReactionButton: View {
    /// Called on confirm; `nil` means no expiry.
    var onPrayerSent: (Date?) -> Void

    @State private var showSheet = false
    @State private var selectedExpiry: PrayerExpiry = .none

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let softGenerator = UIImpactFeedbackGenerator(style: .soft)

    var body: some View {
        Button {
            softGenerator.impactOccurred()
            showSheet = true
        } label: {
            Text("🙏")
                .font(.system(size: 26))
                .frame(width: 44, height: 44)
                .background { prayerButtonBackground }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send prayer reaction")
        .accessibilityHint("Double-tap to choose a prayer duration")
        .glassSheet(isPresented: $showSheet, detent: .small) {
            PrayerTimerSheetContent(
                selectedExpiry: $selectedExpiry,
                onConfirm: { expiry in
                    showSheet = false
                    onPrayerSent(expiry.date)
                },
                onCancel: {
                    showSheet = false
                }
            )
        }
    }

    @ViewBuilder
    private var prayerButtonBackground: some View {
        Circle()
            .strokeBorder(Color.amenGold, lineWidth: 2)
    }
}

// MARK: - PrayerExpiry

enum PrayerExpiry: CaseIterable, Identifiable {
    case none
    case oneHour
    case oneDay
    case sevenDays

    var id: Self { self }

    var label: String {
        switch self {
        case .none:      return "No expiry"
        case .oneHour:   return "1 hour"
        case .oneDay:    return "24 hours"
        case .sevenDays: return "7 days"
        }
    }

    var date: Date? {
        let now = Date.now
        switch self {
        case .none:      return nil
        case .oneHour:   return now.addingTimeInterval(3_600)
        case .oneDay:    return now.addingTimeInterval(86_400)
        case .sevenDays: return now.addingTimeInterval(604_800)
        }
    }
}

// MARK: - PrayerTimerSheetContent

@MainActor
private struct PrayerTimerSheetContent: View {
    @Binding var selectedExpiry: PrayerExpiry
    var onConfirm: (PrayerExpiry) -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 20) {
            // Large prayer emoji header
            Text("🙏")
                .font(.system(size: 48))
                .padding(.top, 24)
                .accessibilityHidden(true)

            Text("Prayer Duration")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            VStack(spacing: 8) {
                ForEach(PrayerExpiry.allCases) { expiry in
                    Button {
                        selectedExpiry = expiry
                    } label: {
                        HStack {
                            Text(expiry.label)
                                .font(.body)
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                            Spacer()
                            if selectedExpiry == expiry {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.amenGold)
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background { rowBackground(isSelected: selectedExpiry == expiry) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expiry.label)
                    .accessibilityAddTraits(selectedExpiry == expiry ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .fill(reduceTransparency ? AnyShapeStyle(Color(.systemFill)) : AnyShapeStyle(LiquidGlassTokens.blurThin))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel prayer")

                Button {
                    onConfirm(selectedExpiry)
                } label: {
                    Text("Send Prayer")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                                .fill(Color.amenGold)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Confirm and send prayer")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func rowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
            .fill(
                isSelected
                    ? AnyShapeStyle(Color.amenGold.opacity(0.15))
                    : (reduceTransparency
                        ? AnyShapeStyle(Color(.systemFill))
                        : AnyShapeStyle(LiquidGlassTokens.blurThin))
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .strokeBorder(Color.amenGold.opacity(0.50), lineWidth: 1)
                }
            }
    }
}

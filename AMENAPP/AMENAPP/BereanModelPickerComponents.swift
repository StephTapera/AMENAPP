// BereanModelPickerComponents.swift
// AMENAPP
//
// Berean AI model selector:
//   BereanModelMode      — enum for core / deep / adaptive
//   BereanModelStore     — singleton with UserDefaults + Firestore persistence
//   BereanModelPickerPill — compact capsule trigger near the composer
//   BereanModelPickerMenu — floating Liquid Glass panel that opens above input

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - BereanModelMode

enum BereanModelMode: String, CaseIterable, Codable, Identifiable {
    case core     = "core"
    case deep     = "deep"
    case adaptive = "adaptive"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core:     return "Berean Core"
        case .deep:     return "Berean Deep"
        case .adaptive: return "Adaptive"
        }
    }

    var subtitle: String {
        switch self {
        case .core:     return "Fast everyday guidance"
        case .deep:     return "Advanced reasoning with discernment"
        case .adaptive: return "Chooses the right depth automatically"
        }
    }

    var requiresPro: Bool {
        switch self {
        case .core:              return false
        case .deep, .adaptive:   return true
        }
    }

    var backendValue: String { rawValue }
}

// MARK: - BereanModelStore

@MainActor
final class BereanModelStore: ObservableObject {
    static let shared = BereanModelStore()
    private static let udKey = "bereanSelectedModelMode_v1"

    @Published var selectedMode: BereanModelMode {
        didSet {
            UserDefaults.standard.set(selectedMode.rawValue, forKey: Self.udKey)
            saveToFirestore(selectedMode)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.udKey) ?? "core"
        selectedMode = BereanModelMode(rawValue: saved) ?? .core
    }

    // MARK: - Usage State / Quota

    @Published var deepCreditsRemaining: Int? = nil
    @Published var quotaExceeded: Bool = false

    func updateUsageState(deepCreditsRemaining: Int?, quotaExceeded: Bool?) {
        self.deepCreditsRemaining = deepCreditsRemaining
        if let q = quotaExceeded { self.quotaExceeded = q }
    }

    func fallbackToCore() {
        selectedMode = .core
    }

    private func saveToFirestore(_ mode: BereanModelMode) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "selectedBereanMode": mode.rawValue,
            "lastModeUpdated": FieldValue.serverTimestamp(),
        ]
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("bereanSettings").document("preferences")
            .setData(data, merge: true)
    }
}

// MARK: - BereanModelPickerPill

struct BereanModelPickerPill: View {
    let selectedMode: BereanModelMode
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Text(selectedMode.title)
                    .font(AMENFont.semiBold(13))
                    .foregroundColor(.primary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.72)))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Berean model: \(selectedMode.title). Tap to change.")
        .accessibilityHint(isExpanded ? "Double tap to close model menu" : "Double tap to open model menu")
        .animation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.80)), value: isExpanded)
    }
}

// MARK: - BereanModelPickerMenu

struct BereanModelPickerMenu: View {
    @Binding var selectedMode: BereanModelMode
    let isProUser: Bool
    let onSelect: (BereanModelMode) -> Void
    let onPaywall: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var visibleModes: [BereanModelMode] {
        var modes: [BereanModelMode] = [.core, .deep]
        if AMENFeatureFlags.shared.bereanAdaptiveModeEnabled {
            modes.append(.adaptive)
        }
        return modes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleModes.enumerated()), id: \.element) { index, mode in
                BereanModelMenuRow(
                    mode: mode,
                    isSelected: selectedMode == mode,
                    isLocked: mode.requiresPro && !isProUser,
                    onTap: {
                        if mode.requiresPro && !isProUser {
                            onPaywall()
                        } else {
                            let feedback = UIImpactFeedbackGenerator(style: .light)
                            feedback.impactOccurred()
                            withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.78))) {
                                selectedMode = mode
                            }
                            onSelect(mode)
                        }
                    }
                )
                if index < visibleModes.count - 1 {
                    Divider()
                        .padding(.horizontal, 16)
                        .opacity(0.5)
                }
            }
        }
        .frame(maxWidth: 340)
        .background(
            reduceTransparency
                ? AnyView(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                : AnyView(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.white.opacity(0.55))
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 24, x: 0, y: 10)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - BereanModelMenuRow

private struct BereanModelMenuRow: View {
    let mode: BereanModelMode
    let isSelected: Bool
    let isLocked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(.primary)
                    Text(mode.subtitle)
                        .font(AMENFont.regular(13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isLocked {
                    Text("Pro")
                        .font(AMENFont.semiBold(11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(mode.title). \(mode.subtitle).\(isLocked ? " Pro required." : isSelected ? " Currently selected." : "")"
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

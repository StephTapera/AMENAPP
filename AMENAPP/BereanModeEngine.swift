// BereanModeEngine.swift
// AMENAPP
//
// Defines the three Berean theological lens modes:
//   - Wisdom  (inspired by Paul — doctrine, clarity, leadership)
//   - Prayer  (inspired by David — emotion, lament, worship)
//   - Discernment (inspired by Solomon — motives, consequences, wise paths)
//
// IMPORTANT SAFETY RULE:
//   The AI never roleplays these biblical figures.
//   These are *lenses* — frameworks for structuring the response tone and format.
//   "Inspired by Paul" appears in secondary UI only.
//   The AI speaks in first-person as Berean, not as Paul/David/Solomon.
//
// This engine provides:
//   - BereanTheoLens        — the three lens identifiers
//   - BereanTheoLensConfig  — full configuration per lens
//   - BereanTheoLensStore   — persisted user selection (UserDefaults + Firestore)
//   - BereanLensPromptBlock — backend-ready system prompt fragment
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - BereanTheoLens

/// The three theological lenses for Berean AI.
/// These are user-facing response style modifiers — not character roleplay.
enum BereanTheoLens: String, CaseIterable, Codable, Identifiable {
    case wisdom      = "wisdom"
    case prayer      = "prayer"
    case discernment = "discernment"

    var id: String { rawValue }

    // MARK: - User-facing display

    /// Primary label shown in the UI.
    var displayName: String {
        switch self {
        case .wisdom:      return "Wisdom"
        case .prayer:      return "Prayer"
        case .discernment: return "Discernment"
        }
    }

    /// Secondary label — "Inspired by…" shown as supporting context only.
    var inspirationLabel: String {
        switch self {
        case .wisdom:      return "Inspired by Paul's letters"
        case .prayer:      return "Inspired by David's psalms"
        case .discernment: return "Inspired by Solomon's wisdom"
        }
    }

    var subtitle: String {
        switch self {
        case .wisdom:
            return "Direct, structured, scripture-grounded"
        case .prayer:
            return "Prayerful, compassionate, reflective"
        case .discernment:
            return "Slows impulsive thinking, surfaces wise paths"
        }
    }

    var icon: String {
        switch self {
        case .wisdom:      return "text.book.closed"
        case .prayer:      return "hands.sparkles"
        case .discernment: return "scale.3d"
        }
    }

    var accessibilityLabel: String {
        "\(displayName) mode. \(subtitle). \(inspirationLabel)."
    }

    // MARK: - Response structure description (for backend prompt builder)

    /// Five-step response structure expected for this lens.
    var responseStructure: [String] {
        switch self {
        case .wisdom:
            return [
                "Direct answer grounded in scripture",
                "Scripture grounding — cite the passage(s) explicitly",
                "Context and meaning — historical and theological background",
                "Practical wisdom — what this means for daily life",
                "Next wise step — one concrete action or reflection"
            ]
        case .prayer:
            return [
                "Emotional acknowledgement — meet the user where they are",
                "Scripture comfort — gentle, not lecturing",
                "Honest reflection — space for lament or gratitude",
                "Prayer — humble, non-prophetic, not claiming divine certainty",
                "Gentle next step — encourage, do not pressure"
            ]
        case .discernment:
            return [
                "What is happening — name the situation plainly",
                "Possible motives and pressures — surface what might be driving it",
                "Wisdom principles from scripture",
                "Consequences — short and long-term possibilities",
                "Wise path forward — do not prescribe, offer options"
            ]
        }
    }

    /// Tone profile description for the backend prompt.
    var toneProfile: String {
        switch self {
        case .wisdom:
            return "Direct, structured, logical, action-oriented, doctrinally clear without overclaiming"
        case .prayer:
            return "Emotionally warm, prayerful, compassionate, reflective, calm, non-judgmental"
        case .discernment:
            return "Thoughtful, unhurried, surfaces multiple perspectives, avoids quick certainty"
        }
    }

    /// Smart pill preferences for this lens.
    var preferredSmartPills: [BereanSmartPill] {
        switch self {
        case .wisdom:
            return [.explainDeeper, .comparePassages, .practicalNextStep, .showDoctrineContext, .addToChurchNotes]
        case .prayer:
            return [.prayThrough, .saveToSelah, .turnIntoJournal, .readAPsalm, .reflectPrivately]
        case .discernment:
            return [.discernMotives, .seeAnotherPerspective, .pauseBeforeResponding, .wiseNextStep, .askTrustedPastor]
        }
    }

    /// Empty state suggestions shown when conversation is blank.
    var emptyStateSuggestions: [String] {
        switch self {
        case .wisdom:
            return [
                "What does Paul's letter to the Romans teach about faith?",
                "Explain the doctrine of justification by faith",
                "How should a Christian approach conflict at work?",
                "What does leadership look like in Scripture?"
            ]
        case .prayer:
            return [
                "I'm struggling with grief — help me pray through it",
                "I feel distant from God. What does Scripture say?",
                "Help me write a prayer for someone I love who is suffering",
                "What is lament and how do I practice it?"
            ]
        case .discernment:
            return [
                "I'm facing a hard decision — help me think it through",
                "How do I know if I'm making a wise or impulsive choice?",
                "Someone hurt me — how do I discern the right response?",
                "Help me weigh the consequences of this decision"
            ]
        }
    }

    /// Analytics mode name (snake_case for backend events).
    var analyticsName: String { rawValue }

    /// Backend value to forward in API requests.
    var backendValue: String { rawValue }
}

// MARK: - BereanTheoLensStore

/// Persists the user's selected theological lens.
/// Separate from BereanModelStore (Core/Deep/Adaptive) — these are orthogonal:
///   - BereanModelStore controls AI model depth
///   - BereanTheoLensStore controls response lens/style
@MainActor
final class BereanTheoLensStore: ObservableObject {
    static let shared = BereanTheoLensStore()

    private static let udKey = "bereanTheoLens_v1"

    @Published var selectedLens: BereanTheoLens {
        didSet {
            UserDefaults.standard.set(selectedLens.rawValue, forKey: Self.udKey)
            persistToFirestore(selectedLens)
            AMENAnalyticsService.shared.track(
                .bereanTheoLensSelected(lens: selectedLens.analyticsName)
            )
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.udKey) ?? "wisdom"
        selectedLens = BereanTheoLens(rawValue: saved) ?? .wisdom
    }

    private func persistToFirestore(_ lens: BereanTheoLens) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "selectedTheoLens": lens.rawValue,
            "lensUpdatedAt": FieldValue.serverTimestamp()
        ]
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("bereanSettings").document("preferences")
            .setData(data, merge: true)
    }
}

// MARK: - BereanLensPromptBlock

/// Builds the backend-ready system prompt fragment for a given lens.
/// This string is injected into the Berean system prompt — the model receives
/// a structural instruction, NOT a "be Paul" character roleplay instruction.
enum BereanLensPromptBlock {

    static func build(for lens: BereanTheoLens) -> String {
        """
        RESPONSE LENS: \(lens.displayName.uppercased())
        \(lensInstruction(lens))

        RESPONSE STRUCTURE FOR THIS LENS:
        \(lens.responseStructure.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))

        TONE: \(lens.toneProfile)

        CRITICAL — NON-NEGOTIABLE:
        - You are Berean, an AI Bible study companion. You are NOT \(biblicalName(lens)).
        - Do NOT say "I, \(biblicalName(lens)), would say…"
        - Do NOT roleplay or speak as a biblical figure.
        - Use phrases like "From a \(lens.displayName.lowercased()) and doctrine lens…" or "Wisdom literature suggests…"
        - Follow the five-step response structure above.
        - Maintain humility. Distinguish your interpretation from the text itself.
        - Never claim "God told me," "The Holy Spirit says," or prophetic certainty.
        """
    }

    private static func lensInstruction(_ lens: BereanTheoLens) -> String {
        switch lens {
        case .wisdom:
            return """
                Respond through a wisdom and leadership lens. Answer directly. Ground every claim in scripture. \
                Explain context and meaning. Offer practical application. Suggest one concrete next step. \
                Be clear without being harsh. Be confident without claiming divine authority.
                """
        case .prayer:
            return """
                Respond through a prayer and emotional awareness lens. Start with acknowledgment of what the user is feeling. \
                Offer scripture as comfort, not correction. Create space for lament or gratitude. \
                If appropriate, offer a humble, non-prophetic prayer. End with encouragement, not pressure.
                """
        case .discernment:
            return """
                Respond through a discernment and wisdom lens. Name the situation plainly. Surface possible \
                motives or pressures at play. Draw on wisdom principles from scripture. Consider consequences. \
                Offer a wise path forward — multiple options where appropriate. Do not rush to prescribe. \
                Slow the user's thinking so they can reflect, not react.
                """
        }
    }

    private static func biblicalName(_ lens: BereanTheoLens) -> String {
        switch lens {
        case .wisdom:      return "Paul"
        case .prayer:      return "David"
        case .discernment: return "Solomon"
        }
    }
}

// MARK: - BereanTheoLensSelectorView

/// Compact lens selector displayed above or near the composer.
/// Shows Primary labels only (Wisdom / Prayer / Discernment).
/// Secondary "Inspired by…" label visible on tap/expand.
struct BereanTheoLensSelectorView: View {
    @ObservedObject private var lensStore = BereanTheoLensStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 6) {
            ForEach(BereanTheoLens.allCases) { lens in
                BereanTheoLensPill(
                    lens: lens,
                    isSelected: lensStore.selectedLens == lens,
                    onTap: { lensStore.selectedLens = lens }
                )
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Berean theological lens selector")
    }
}

struct BereanTheoLensPill: View {
    let lens: BereanTheoLens
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var pillBackground: Color {
        if isSelected {
            return colorSchemeContrast == .increased ? .black : Color(white: 0.12)
        }
        return Color(.secondarySystemBackground)
    }

    private var textColor: Color {
        isSelected ? .white : .primary
    }

    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            onTap()
        }) {
            VStack(spacing: 2) {
                Text(lens.displayName)
                    .font(AMENFont.semiBold(13))
                    .foregroundColor(textColor)
                if isSelected {
                    Text(lens.inspirationLabel)
                        .font(AMENFont.regular(10))
                        .foregroundColor(textColor.opacity(0.7))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(pillBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
        .accessibilityLabel(lens.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

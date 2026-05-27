// AmenAmbientInsightPillView.swift
// AMEN App — Ambient Intelligence Signal Pills
//
// Proactive, non-intrusive signals surfaced from the intelligence layer.
// Calm Liquid Glass capsule. Never loud, never diagnostic, always humble.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Ambient Insight Signal Store

@MainActor
final class AmenAmbientSignalStore: ObservableObject {

    static let shared = AmenAmbientSignalStore()

    @Published private(set) var signals: [AmenAmbientSignal] = []
    private let db = Firestore.firestore()
    private var userId: String { Auth.auth().currentUser?.uid ?? "" }
    private var listener: ListenerRegistration?

    private init() {}

    deinit { listener?.remove() }

    func subscribe(spaceId: String) {
        guard AMENFeatureFlags.shared.ambientAIEnabled else { return }
        listener?.remove()
        listener = db
            .collection("spaces").document(spaceId)
            .collection("ambientSignals")
            .whereField("dismissed", isEqualTo: false)
            .whereField("relevantToUserId", in: [userId, NSNull()])
            .order(by: "createdAt", descending: true)
            .limit(to: 5)
            .addSnapshotListener { [weak self] snap, _ in
                self?.signals = snap?.documents.compactMap { try? $0.data(as: AmenAmbientSignal.self) } ?? []
            }
    }

    func dismiss(_ signal: AmenAmbientSignal, spaceId: String) async {
        signals.removeAll { $0.id == signal.id }
        try? await db
            .collection("spaces").document(spaceId)
            .collection("ambientSignals").document(signal.id)
            .updateData(["dismissed": true])
    }
}

// MARK: - Single Pill View

struct AmenAmbientInsightPillView: View {
    let signal: AmenAmbientSignal
    let spaceId: String
    var onTap: (() -> Void)? = nil

    @State private var isVisible: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accentColor)

            Text(signal.displayBody)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.72))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                Task {
                    await AmenAmbientSignalStore.shared.dismiss(signal, spaceId: spaceId)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.30))
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss insight")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(pillBackground)
        .onTapGesture { onTap?() }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 6)
        .onAppear {
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.26).delay(0.05)) {
                isVisible = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Insight: \(signal.displayBody)")
    }

    private var pillBackground: some View {
        Capsule(style: .continuous)
            .fill(.regularMaterial)
            .overlay(Capsule().fill(Color.white.opacity(0.55)))
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.70), Color.white.opacity(0.22)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
            )
            .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
    }

    private var iconName: String {
        switch signal.signalType {
        case .prayerRequestUpdated:    return "hands.sparkles.fill"
        case .relatedToSermon:         return "book.pages"
        case .convergingTheme:         return "arrow.triangle.2.circlepath"
        case .unresolvedFollowUp:      return "questionmark.circle.fill"
        case .participationDrop:       return "person.crop.circle.badge.minus"
        case .bibleStudyLink:          return "book.closed.fill"
        case .leadershipActionNeeded:  return "crown.fill"
        case .spiritualThemeRecurring: return "sparkles"
        }
    }

    private var accentColor: Color {
        switch signal.signalType {
        case .prayerRequestUpdated, .spiritualThemeRecurring:
            return Color(red: 0.62, green: 0.49, blue: 0.79)
        case .relatedToSermon, .bibleStudyLink:
            return Color(red: 0.43, green: 0.58, blue: 0.86)
        case .convergingTheme, .unresolvedFollowUp:
            return Color(red: 0.79, green: 0.63, blue: 0.27)
        case .participationDrop, .leadershipActionNeeded:
            return Color(red: 0.78, green: 0.38, blue: 0.38)
        }
    }
}

// MARK: - Signal Stack View

struct AmenAmbientInsightStack: View {
    let spaceId: String
    var onSignalTap: ((AmenAmbientSignal) -> Void)? = nil

    @ObservedObject private var store = AmenAmbientSignalStore.shared

    var body: some View {
        if store.signals.isEmpty { EmptyView() } else {
            VStack(spacing: 6) {
                ForEach(store.signals) { signal in
                    AmenAmbientInsightPillView(
                        signal: signal,
                        spaceId: spaceId
                    ) {
                        onSignalTap?(signal)
                    }
                }
            }
            .padding(.horizontal, 16)
            .onAppear { store.subscribe(spaceId: spaceId) }
        }
    }
}

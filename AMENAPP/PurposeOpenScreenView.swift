// PurposeOpenScreenView.swift
// AMENAPP
// Cold-launch intention-setting screen shown once per session before feed scroll.

import SwiftUI
import FirebaseFunctions

// MARK: - Intention model

enum PurposeIntention: String, CaseIterable {
    case connect, learn, pray, encourage, share, explore

    var label: String {
        switch self {
        case .connect:   return "Connect"
        case .learn:     return "Learn"
        case .pray:      return "Pray"
        case .encourage: return "Encourage"
        case .share:     return "Share"
        case .explore:   return "Explore"
        }
    }

    var symbol: String {
        switch self {
        case .connect:   return "person.2.fill"
        case .learn:     return "book.fill"
        case .pray:      return "hands.and.sparkles.fill"
        case .encourage: return "heart.fill"
        case .share:     return "square.and.arrow.up.fill"
        case .explore:   return "magnifyingglass"
        }
    }
}

// MARK: - View

struct PurposeOpenScreenView: View {
    let onDismiss: () -> Void

    @State private var selectedIntention: PurposeIntention? = nil

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Header
                VStack(spacing: 10) {
                    Text("What brings you here today?")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Text("Choosing an intention helps Amen surface what matters most.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer().frame(height: 32)

                // Intention grid
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(PurposeIntention.allCases, id: \.self) { intention in
                        IntentionChip(
                            intention: intention,
                            isSelected: selectedIntention == intention
                        )
                        .onTapGesture { selectedIntention = intention }
                    }
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 32)

                // Begin button
                Button(action: beginSession) {
                    Text("Begin")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(selectedIntention == nil ? Color(.systemGray4) : Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .disabled(selectedIntention == nil)
                .padding(.horizontal, 24)
                .animation(.easeInOut(duration: 0.2), value: selectedIntention)

                // Skip
                Button("Skip") { onDismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                Spacer()
            }
        }
        .onAppear {
            if !AMENFeatureFlags.shared.purposeOpenScreenEnabled {
                onDismiss()
            }
        }
    }

    private func beginSession() {
        guard let intention = selectedIntention else { return }
        // Fire-and-forget signal; errors non-fatal
        Task {
            do {
                let callable = Functions.functions().httpsCallable("recordIntentionSignal")
                _ = try await callable.call(["intention": intention.rawValue])
            } catch {
                // Non-fatal
            }
        }
        onDismiss()
    }
}

// MARK: - Chip subview

private struct IntentionChip: View {
    let intention: PurposeIntention
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: intention.symbol)
                .font(.body)
                .foregroundStyle(isSelected ? .white : .primary)
            Text(intention.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(isSelected ? Color.accentColor : Color(.systemGray6))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Color(.systemGray4),
                            lineWidth: 0.5
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(intention.label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

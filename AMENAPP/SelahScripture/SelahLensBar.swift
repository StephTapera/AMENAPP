//
//  SelahLensBar.swift
//  AMENAPP
//
//  The Selah Lens action bar. Springs in above a tapped verse, classifies the
//  verse theme on appear, then renders the appropriate action buttons in the
//  order specified by the classification response.
//
//  Design rules:
//  - Container: .ultraThinMaterial Capsule, no border, shadow(radius:8, y:4)
//  - Scripture text is MATTE. This bar only ever floats over chrome — never
//    renders glass behind scripture text.
//  - Spring in/out with .spring(response: .snappy) + move+opacity transition.
//  - All button handlers call real closures passed in by the parent.
//  - Haptic feedback on every action tap.
//

import SwiftUI

// MARK: - Color palette (private constants)

private extension Color {
    static let amenGold   = Color(red: 1.0,    green: 0.843, blue: 0.0)    // #FFD700
    static let amenPurple = Color(red: 0.420,  green: 0.129, blue: 0.659)  // #6B21A8
    static let amenBlue   = Color(red: 0.145,  green: 0.388, blue: 0.922)  // #2563EB
    static let amenBlack  = Color(red: 0.059,  green: 0.059, blue: 0.059)  // #0F0F0F
}

// MARK: - SelahLensBar

struct SelahLensBar: View {

    // MARK: Inputs

    let verseId: String
    let verseText: String
    let translation: SelahTranslation

    @ObservedObject var viewModel: SelahLensViewModel

    let onStudySheet:    () -> Void
    let onReflect:       () -> Void
    let onPray:          () -> Void
    let onAddToSession:  () -> Void
    let onCrossRefs:     () -> Void
    let onDismiss:       () -> Void

    // MARK: Private state

    @State private var showMoreMenu: Bool = false

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    // MARK: Body

    var body: some View {
        HStack(spacing: 4) {
            content
            Spacer(minLength: 0)
            dismissButton
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        .transition(
            .move(edge: .top).combined(with: .opacity)
        )
        .animation(.spring(response: 0.36, dampingFraction: 0.72), value: viewModel.state)
        .onAppear {
            haptic.prepare()
            Task {
                await viewModel.classifyVerse(
                    verseId: verseId,
                    translation: translation,
                    verseText: verseText
                )
            }
        }
    }

    // MARK: - Content Switch

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            shimmer
        case .loaded(let response):
            actionRow(for: response)
        case .error:
            errorChip
        }
    }

    // MARK: - Shimmer (loading state)

    private var shimmer: some View {
        HStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { index in
                ShimmerCapsule()
                    .frame(width: CGFloat([52, 64, 56, 52][index]), height: 26)
            }
        }
    }

    // MARK: - Action Row

    private func actionRow(for response: ClassifyVerseThemeResponse) -> some View {
        let primary   = primaryActions(from: response.suggestedActions)
        let secondary = secondaryActions(from: response.suggestedActions)

        return HStack(spacing: 2) {
            ForEach(primary) { action in
                actionButton(action)
            }
            if !secondary.isEmpty {
                moreButton(overflow: secondary)
            }
        }
    }

    // MARK: - Primary / Secondary Split

    /// Shows up to 4 actions inline; the rest go in the "more" menu.
    private func primaryActions(from actions: [SelahLensActionKind]) -> [SelahLensActionKind] {
        // Remove `.more` sentinel from the list — we synthesize it ourselves if needed.
        let filtered = actions.filter { $0 != .more }
        return Array(filtered.prefix(4))
    }

    private func secondaryActions(from actions: [SelahLensActionKind]) -> [SelahLensActionKind] {
        let filtered = actions.filter { $0 != .more }
        guard filtered.count > 4 else { return [] }
        return Array(filtered.dropFirst(4))
    }

    // MARK: - Individual Action Button

    private func actionButton(_ action: SelahLensActionKind) -> some View {
        Button {
            haptic.impactOccurred()
            dispatch(action)
        } label: {
            Label(action.displayLabel, systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(action.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 36, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("selahLens.\(action.rawValue)Button")
    }

    // MARK: - More Button

    private func moreButton(overflow: [SelahLensActionKind]) -> some View {
        Menu {
            ForEach(overflow) { action in
                Button {
                    haptic.impactOccurred()
                    dispatch(action)
                } label: {
                    Label(action.displayLabel, systemImage: action.systemImage)
                }
                .accessibilityIdentifier("selahLens.\(action.rawValue)Button")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, minHeight: 36)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("selahLens.moreButton")
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        Button {
            haptic.impactOccurred(intensity: 0.5)
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss Selah Lens")
        .accessibilityIdentifier("selahLens.dismissButton")
    }

    // MARK: - Error Chip

    private var errorChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Could not load actions")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await viewModel.classifyVerse(verseId: verseId, translation: translation, verseText: verseText) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.amenBlue)
        }
    }

    // MARK: - Action Dispatch

    private func dispatch(_ action: SelahLensActionKind) {
        switch action {
        case .understand:     onStudySheet()
        case .crossReferences: onCrossRefs()
        case .reflect:        onReflect()
        case .pray:           onPray()
        case .addToSession:   onAddToSession()
        case .more:           break // handled by moreButton
        }
    }
}

// MARK: - SelahLensActionKind Extensions

private extension SelahLensActionKind {
    var displayLabel: String {
        switch self {
        case .understand:      return "Understand"
        case .crossReferences: return "Cross-Refs"
        case .reflect:         return "Reflect"
        case .pray:            return "Pray"
        case .addToSession:    return "Add to Session"
        case .more:            return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .understand:      return "book.fill"
        case .crossReferences: return "link"
        case .reflect:         return "pencil.and.outline"
        case .pray:            return "hands.sparkles"
        case .addToSession:    return "play.rectangle.fill"
        case .more:            return "ellipsis"
        }
    }

    var accentColor: Color {
        switch self {
        case .understand:      return .amenBlue
        case .crossReferences: return .amenPurple
        case .reflect:         return .amenGold
        case .pray:            return .amenGold
        case .addToSession:    return .amenBlue
        case .more:            return .secondary
        }
    }
}

// MARK: - ShimmerCapsule (loading placeholder)

private struct ShimmerCapsule: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.secondary.opacity(0.12), location: phase),
                        .init(color: Color.secondary.opacity(0.28), location: phase + 0.4),
                        .init(color: Color.secondary.opacity(0.12), location: phase + 0.8)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.1)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.2
                }
            }
    }
}

// PurityBadgeView.swift
// AMEN App — Community Around Content OS / Intelligence
//
// SwiftUI components for displaying purity ratings and letting users
// configure their purity filter preference.

import SwiftUI

// MARK: - PurityBadgeView

/// A small inline badge that displays the purity rating of a piece of content.
/// Renders nothing (EmptyView) for `.unreviewed` content to avoid cluttering the UI.
struct PurityBadgeView: View {

    let rating: PurityRating

    var body: some View {
        switch rating {
        case .unreviewed:
            EmptyView()

        case .familySafe:
            badge(
                label: "Family Safe",
                systemImage: "checkmark.circle",
                foreground: Color(.systemGreen),
                background: Color(.systemGreen).opacity(0.12)
            )

        case .someConcerns:
            badge(
                label: "Some Concerns",
                systemImage: "exclamationmark.triangle",
                foreground: Color(.systemYellow),
                background: Color(.systemYellow).opacity(0.12)
            )

        case .notRecommended:
            badge(
                label: "Not Recommended",
                systemImage: "xmark.circle",
                foreground: Color(.systemRed),
                background: Color(.systemRed).opacity(0.12)
            )
        }
    }

    // MARK: Private

    @ViewBuilder
    private func badge(
        label: String,
        systemImage: String,
        foreground: Color,
        background: Color
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(label)
                .fontWeight(.semibold)
        }
        .font(.caption2)
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(background, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Content rating: \(label)")
    }
}

// MARK: - ContentPurityFilterSheet

/// A bottom sheet that lets the user choose their purity filter level.
/// Presents four radio-style rows with display names and descriptions.
struct ContentPurityFilterSheet: View {

    @Binding var filterLevel: PurityFilterLevel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PurityFilterLevel.allCases, id: \.rawValue) { level in
                        filterRow(level)
                    }
                } header: {
                    Text("Choose what content you see based on purity ratings.")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                        .textCase(nil)
                        .padding(.bottom, 4)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Content Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(.secondaryLabel))
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Close filter settings")
                }
            }
        }
    }

    // MARK: Private

    @ViewBuilder
    private func filterRow(_ level: PurityFilterLevel) -> some View {
        let isSelected = filterLevel == level
        let isRecommended = level == .familySafe

        Button {
            withAnimation(AppAnimation.stateChange) {
                filterLevel = level
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(level.displayName)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(.label))

                        if isRecommended {
                            Text("Recommended")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color(.systemBlue))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Color(.systemBlue).opacity(0.12),
                                    in: Capsule()
                                )
                        }
                    }

                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(.systemBlue))
                        .imageScale(.medium)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(level.displayName). \(level.description)\(isRecommended ? ". Recommended default." : "")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Double tap to select this content filter level.")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("PurityBadgeView — all ratings") {
    VStack(spacing: 12) {
        PurityBadgeView(rating: .familySafe)
        PurityBadgeView(rating: .someConcerns)
        PurityBadgeView(rating: .notRecommended)
        PurityBadgeView(rating: .unreviewed)
    }
    .padding()
    .background(Color(.systemBackground))
}

#Preview("ContentPurityFilterSheet") {
    struct PreviewWrapper: View {
        @State private var level: PurityFilterLevel = .familySafe
        @State private var isShowing = true

        var body: some View {
            Color(.systemBackground)
                .sheet(isPresented: $isShowing) {
                    ContentPurityFilterSheet(filterLevel: $level)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
        }
    }
    return PreviewWrapper()
}
#endif

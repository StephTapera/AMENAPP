//
//  CalmModeSettingsView.swift
//  AMENAPP
//
//  Settings view for Calm Mode — spiritual digital wellness controls.
//  Surfaced inside Settings > Accessibility or via the Calm Mode toggle.
//

import SwiftUI

// MARK: - CalmModeSettingsView

struct CalmModeSettingsView: View {

    @ObservedObject var manager: CalmModeManager = .shared

    // MARK: Brand tokens
    private let amenGold    = Color(red: 0.937, green: 0.761, blue: 0.318)
    private let background  = Color(red: 0.110, green: 0.110, blue: 0.118) // #1C1C1E
    private let cardRadius: CGFloat = 16

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    calmModeHeaderCard
                    if manager.isEnabled {
                        settingsSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("Calm Mode")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Header Card

    private var calmModeHeaderCard: some View {
        settingCard {
            HStack(spacing: 14) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(manager.isEnabled ? amenGold : .secondary)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: manager.isEnabled)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Calm Mode")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Reduce stimulation. Be present.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { manager.isEnabled },
                    set: { _ in manager.toggle() }
                ))
                .labelsHidden()
                .tint(amenGold)
            }
            .padding(18)
        }
    }

    // MARK: - Settings Section

    @ViewBuilder
    private var settingsSection: some View {
        VStack(spacing: 12) {

            // Hide reaction counts
            toggleCard(
                title: "Hide reaction counts",
                subtitle: "Numbers create comparison",
                isOn: $manager.hideEngagementMetrics
            )

            // Limit scroll session
            settingCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Limit scroll session")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("Pause after \(manager.sessionScrollLimit) posts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $manager.disableInfiniteScroll)
                            .labelsHidden()
                            .tint(amenGold)
                            .onChange(of: manager.disableInfiniteScroll) { _ in
                                Task { await AmenHapticEngine.shared.play(.encouragement) }
                            }
                    }

                    if manager.disableInfiniteScroll {
                        Divider().background(Color.white.opacity(0.08))
                        HStack {
                            Text("Posts per session")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Stepper(
                                "\(manager.sessionScrollLimit)",
                                value: $manager.sessionScrollLimit,
                                in: 5...50,
                                step: 5
                            )
                            .foregroundStyle(amenGold)
                            .tint(amenGold)
                        }
                    }
                }
                .padding(18)
            }

            // Softer animations
            toggleCard(
                title: "Softer animations",
                subtitle: nil,
                isOn: $manager.reducedAnimations
            )

            // Gentle grayscale
            toggleCard(
                title: "Gentle grayscale",
                subtitle: "Reduces visual pull",
                isOn: $manager.grayscaleMode
            )

            // Audio-first mode
            toggleCard(
                title: "Audio-first mode",
                subtitle: "Listen instead of scroll",
                isOn: $manager.audioFirstMode
            )

            // Reset button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    manager.reset()
                }
            } label: {
                Text("Reset to Defaults")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    // MARK: - Reusable Card Helpers

    @ViewBuilder
    private func toggleCard(
        title: String,
        subtitle: String?,
        isOn: Binding<Bool>
    ) -> some View {
        settingCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(amenGold)
                    .onChange(of: isOn.wrappedValue) { _ in
                        Task { await AmenHapticEngine.shared.play(.encouragement) }
                    }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func settingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .overlay(content())
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#if DEBUG
struct CalmModeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationStack {
                CalmModeSettingsView()
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark — Calm Off")

            NavigationStack {
                CalmModeSettingsView(manager: {
                    let m = CalmModeManager.shared
                    m.isEnabled = true
                    m.disableInfiniteScroll = true
                    return m
                }())
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark — Calm On")
        }
    }
}
#endif

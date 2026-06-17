// ThresholdView.swift
// AMEN — THRESHOLD Smart Profile / Identity Switcher
//
// W5: SwiftUI surface wired to W1–W3. Feature-gated by AMENFeatureFlags.thresholdEnabled.
// Presented as a sheet from ProfileView's … menu.
//
// ANTI-ENGAGEMENT: No session-length, DAU, or re-engagement signal is shown or collected.
// The success metric is taps-to-first-intended-action, measured on-device only (W6).
// See ThresholdAntiEngagementNote.swift for the full constraint.

import SwiftUI

// MARK: - ThresholdView

struct ThresholdView: View {

    @State private var vm = ThresholdViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    pickerBody
                }
            }
            .navigationTitle("Switch Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .task { await vm.load() }
    }

    // MARK: - Main Layout

    private var pickerBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(orderedCards, id: \.profileId) { ranked in
                        cardSection(ranked: ranked)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }

            Spacer(minLength: 0)

            addContextButton
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
        }
    }

    // Cards ordered by prediction rank; fall back to profile order when prediction is off.
    private var orderedCards: [RankedProfile] {
        if let ranked = vm.prediction?.ranked, !ranked.isEmpty {
            return ranked
        }
        return vm.profiles.map {
            RankedProfile(profileId: $0.id, score: 0, reason: "Your profile")
        }
    }

    // MARK: - Profile Card

    @ViewBuilder
    private func cardSection(ranked: RankedProfile) -> some View {
        if let profile = vm.profiles.first(where: { $0.id == ranked.profileId }) {
            let isActive = profile.id == vm.activeProfileId
            let isTopPredicted = ranked.profileId == vm.prediction?.ranked.first?.profileId
                && ranked.score > 0
                && !isActive

            VStack(spacing: 4) {
                profileCard(profile: profile, ranked: ranked, isActive: isActive, isTopPredicted: isTopPredicted)

                // Reason chip — only for the top predicted profile, only when not already active
                if isTopPredicted {
                    reasonChip(text: ranked.reason)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                }
            }
        }
    }

    private func profileCard(
        profile: ProfileDescriptor,
        ranked: RankedProfile,
        isActive: Bool,
        isTopPredicted: Bool
    ) -> some View {
        Button {
            guard !isActive else { return }
            Task { await vm.switchTo(profile) }
        } label: {
            GlassEffectContainer(spacing: 0) {
                cardRow(profile: profile, isActive: isActive, isTopPredicted: isTopPredicted)
                    // Top predicted profile: subtle tinted border signals the prediction
                    // without dark-pattern emphasis (no pulse, no forced pre-select).
                    .amenGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        if isTopPredicted {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.30), lineWidth: 1)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(vm.isSwitching || isActive)
        .accessibilityLabel(cardAccessibilityLabel(profile: profile, isActive: isActive))
        .accessibilityHint(isActive ? "" : "Double-tap to switch to this context")
    }

    private func cardRow(
        profile: ProfileDescriptor,
        isActive: Bool,
        isTopPredicted: Bool
    ) -> some View {
        HStack(spacing: 14) {
            avatarCircle(profile: profile)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(profile.type.thresholdDisplayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                    .accessibilityLabel("Active context")
            } else if vm.isSwitching {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Text("Switch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.accentColor)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func avatarCircle(profile: ProfileDescriptor) -> some View {
        ZStack {
            Circle()
                .fill(profile.type.thresholdAccentColor.opacity(0.16))
                .frame(width: 52, height: 52)
            Text(profile.displayName.prefix(1).uppercased())
                .font(.title2.weight(.semibold))
                .foregroundStyle(profile.type.thresholdAccentColor)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Reason Chip

    private func reasonChip(text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.thinMaterial))
        .accessibilityLabel("Suggested because: \(text)")
    }

    // MARK: - Add Context (W6 stub)

    private var addContextButton: some View {
        Button {
            // W6: present AddContextView sheet
        } label: {
            Label("Add Context", systemImage: "plus.circle")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .amenGlassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Create a new ministry, creator, or organization context")
    }

    // MARK: - Accessibility

    private func cardAccessibilityLabel(profile: ProfileDescriptor, isActive: Bool) -> String {
        let suffix = isActive ? ", currently active" : ""
        return "\(profile.displayName), \(profile.type.thresholdDisplayName) context\(suffix)"
    }
}

// MARK: - ProfileType display helpers (Threshold-local)

private extension ProfileType {
    var thresholdDisplayName: String {
        switch self {
        case .personal:  return "Personal"
        case .ministry:  return "Ministry"
        case .creator:   return "Creator"
        case .org:       return "Organization"
        }
    }

    var thresholdAccentColor: Color {
        switch self {
        case .personal:  return .blue
        case .ministry:  return Color(hex: "7C3AED")
        case .creator:   return Color(hex: "F59E0B")
        case .org:       return Color(hex: "059669")
        }
    }
}

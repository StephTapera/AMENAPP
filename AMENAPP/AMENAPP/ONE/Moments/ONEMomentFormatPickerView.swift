// ONEMomentFormatPickerView.swift
// ONE — Moment format selector sheet with per-format default privacy contract.
// P2-D | Presented as a sheet from ONELiquidCameraView or any capture surface.

import SwiftUI

struct ONEMomentFormatPickerView: View {
    @Binding var selectedFormat: ONEMomentType
    @Binding var contract: ONEPrivacyContract

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: ONE.Spacing.sm) {
                    ForEach(ONEMomentType.pickableTypes, id: \.self) { format in
                        formatCard(format)
                    }
                    Color.clear.frame(height: 110)     // clearance for bottom preview bar
                }
                .padding(.horizontal, ONE.Spacing.md)
                .padding(.top, ONE.Spacing.md)
            }
            .navigationTitle("Choose Format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) { privacyPreview }
        }
    }

    // MARK: - Format card

    private func formatCard(_ format: ONEMomentType) -> some View {
        let isSelected = selectedFormat == format
        return Button {
            withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                selectedFormat = format
                contract = defaultContract(for: format)
            }
        } label: {
            HStack(spacing: ONE.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(format.provenanceColor.opacity(0.16))
                    Image(systemName: format.provenanceIcon)
                        .font(.systemScaled(18, weight: .semibold))
                        .foregroundStyle(format.provenanceColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(format.displayName)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(format.formatSubtitle)
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(defaultContract(for: format).audience.displayLabel)
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(format.provenanceColor)
                    .padding(.horizontal, ONE.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(format.provenanceColor.opacity(0.10)))

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.systemScaled(20))
                        .foregroundStyle(format.provenanceColor)
                }
            }
            .padding(ONE.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                    .fill(isSelected ? format.provenanceColor.opacity(0.06) : Color.primary.opacity(0.04))
                    .stroke(isSelected ? format.provenanceColor.opacity(0.25) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(format.displayName): \(format.formatSubtitle)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Privacy preview bar

    private var privacyPreview: some View {
        HStack(spacing: ONE.Spacing.sm) {
            Image(systemName: "lock.fill")
                .font(.systemScaled(11))
                .foregroundStyle(ONE.Colors.privateIndigo)
            Text(contract.audience.displayLabel)
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("·").foregroundStyle(.tertiary)
            Text(contract.lifetime.displayLabel)
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Use This") { dismiss() }
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, ONE.Spacing.md)
                .padding(.vertical, ONE.Spacing.sm)
                .background(Capsule().fill(selectedFormat.provenanceColor))
                .accessibilityLabel("Use \(selectedFormat.displayName) format")
        }
        .padding(.horizontal, ONE.Spacing.md)
        .padding(.vertical, ONE.Spacing.md)
        .padding(.bottom, ONE.Spacing.sm)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.4) }
    }

    // MARK: - Default privacy contract per format

    func defaultContract(for format: ONEMomentType) -> ONEPrivacyContract {
        switch format {
        case .snap, .directMessage:
            return ONEPrivacyContract(
                audience: .closeFriends,
                lifetime: .afterView,
                permissions: ONEMomentPermissions(
                    forwardAllowed: false, saveAllowed: false, quoteAllowed: false,
                    reactAllowed: true,   translateAllowed: true,
                    summarizeAllowed: false, aiTrainingAllowed: false
                ),
                safety: .init(), metricsPrivate: true, reshareAllowed: false
            )
        case .post:
            return .privateDefault
        case .voice:
            return ONEPrivacyContract(
                audience: .closeFriends, lifetime: .afterView,
                permissions: ONEMomentPermissions(
                    forwardAllowed: false, saveAllowed: false, quoteAllowed: true,
                    reactAllowed: true,   translateAllowed: true,
                    summarizeAllowed: false, aiTrainingAllowed: false
                ),
                safety: .init(), metricsPrivate: true, reshareAllowed: false
            )
        case .reflection:
            return ONEPrivacyContract(
                audience: .selfOnly, lifetime: .permanent,
                permissions: .init(), safety: .init(),
                metricsPrivate: true, reshareAllowed: false
            )
        case .locationShare:
            return ONEPrivacyContract(
                audience: .closeFriends, lifetime: .days(7),
                permissions: .init(), safety: .init(),
                metricsPrivate: true, reshareAllowed: false
            )
        case .memory:
            return ONEPrivacyContract(
                audience: .selfOnly, lifetime: .permanent,
                permissions: .init(), safety: .init(),
                metricsPrivate: true, reshareAllowed: false
            )
        case .album:
            return ONEPrivacyContract(
                audience: .closeFriends, lifetime: .permanent,
                permissions: ONEMomentPermissions(
                    forwardAllowed: false, saveAllowed: true, quoteAllowed: false,
                    reactAllowed: true,   translateAllowed: true,
                    summarizeAllowed: false, aiTrainingAllowed: false
                ),
                safety: .init(), metricsPrivate: true, reshareAllowed: false
            )
        case .creatorDrop:
            return ONEPrivacyContract(
                audience: .custom(uids: []), lifetime: .permanent,
                permissions: ONEMomentPermissions(
                    forwardAllowed: false, saveAllowed: false, quoteAllowed: false,
                    reactAllowed: true,   translateAllowed: false,
                    summarizeAllowed: false, aiTrainingAllowed: false
                ),
                safety: .init(), metricsPrivate: false, reshareAllowed: false
            )
        }
    }
}

// MARK: - ONEMomentType UI metadata

extension ONEMomentType {
    var displayName: String {
        switch self {
        case .snap:        return "Snap"
        case .post:        return "Post"
        case .voice:       return "Voice Note"
        case .reflection:  return "Reflection"
        case .locationShare:    return "Location"
        case .memory:      return "Memory"
        case .album:       return "Album"
        case .creatorDrop: return "Creator Drop"
        case .directMessage:          return "Direct Message"
        }
    }

    var formatSubtitle: String {
        switch self {
        case .snap:        return "Disappears after viewing"
        case .post:        return "Standard feed post"
        case .voice:       return "Voice note with transcription"
        case .reflection:  return "Private prompted reflection"
        case .locationShare:    return "Place check-in"
        case .memory:      return "From your vault"
        case .album:       return "Collaborative photo collection"
        case .creatorDrop: return "Subscriber-only content"
        case .directMessage:          return "Direct private message"
        }
    }

    var provenanceIcon: String {
        switch self {
        case .snap:        return "bolt.fill"
        case .post:        return "photo.fill"
        case .voice:       return "mic.fill"
        case .reflection:  return "book.fill"
        case .locationShare:    return "location.fill"
        case .memory:      return "heart.fill"
        case .album:       return "photo.stack.fill"
        case .creatorDrop: return "star.fill"
        case .directMessage:          return "message.fill"
        }
    }

    var provenanceColor: Color {
        switch self {
        case .snap:        return ONE.Colors.ephemeralRed
        case .post:        return ONE.Colors.privateIndigo
        case .voice:       return ONE.Colors.repairGreen
        case .reflection:  return ONE.Colors.witnessGold
        case .locationShare:    return ONE.Colors.repairGreen
        case .memory:      return ONE.Colors.ephemeralRed
        case .album:       return ONE.Colors.privateIndigo
        case .creatorDrop: return ONE.Colors.subscriberGold
        case .directMessage:          return ONE.Colors.privateIndigo
        }
    }

    static var pickableTypes: [ONEMomentType] {
        [.snap, .post, .voice, .reflection, .locationShare, .memory, .album, .creatorDrop, .directMessage]
    }
}

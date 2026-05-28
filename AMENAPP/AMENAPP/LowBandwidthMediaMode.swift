// LowBandwidthMediaMode.swift
// AMENAPP
//
// UI components and settings views for the low-bandwidth media system.
// The LowBandwidthMediaMode enum is defined in AmenHealthyImmersiveMediaSystem.swift.
//
// Gated by AMENFeatureFlags.shared.mediaLowBandwidthModeEnabled

import SwiftUI

// MARK: - Mode Metadata

private struct LowBandwidthModeInfo {
    let mode: LowBandwidthMediaMode
    let icon: String
    let title: String
    let description: String
}

private let modeInfoList: [LowBandwidthModeInfo] = [
    LowBandwidthModeInfo(
        mode: .automatic,
        icon: "network",
        title: "Automatic",
        description: "Adapts to your connection quality"
    ),
    LowBandwidthModeInfo(
        mode: .lowQualityVideo,
        icon: "video.badge.ellipsis",
        title: "Lower quality video",
        description: "Reduces resolution to save data"
    ),
    LowBandwidthModeInfo(
        mode: .audioOnly,
        icon: "headphones",
        title: "Audio only",
        description: "Streams audio — background playback friendly"
    ),
    LowBandwidthModeInfo(
        mode: .transcriptOnly,
        icon: "text.alignleft",
        title: "Text only",
        description: "Ultra-low bandwidth — reads the transcript"
    ),
    LowBandwidthModeInfo(
        mode: .wifiOnly,
        icon: "wifi",
        title: "Wi-Fi only",
        description: "Never streams on cellular data"
    ),
]

// MARK: - LowBandwidthModeSelector

/// A vertically-stacked list of mode options.
/// Each row shows an icon, title, description, and a selection indicator.
struct LowBandwidthModeSelector: View {

    @Binding var selectedMode: LowBandwidthMediaMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ForEach(modeInfoList, id: \.mode.id) { info in
                modeRow(info)
            }
        }
    }

    // MARK: Row

    private func modeRow(_ info: LowBandwidthModeInfo) -> some View {
        let isSelected = selectedMode == info.mode
        return Button {
            if reduceMotion {
                selectedMode = info.mode
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedMode = info.mode
                }
            }
        } label: {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(width: 36, height: 36)
                    Image(systemName: info.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? .white : Color.secondary)
                }
                .accessibilityHidden(true)

                // Labels
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(info.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiaryLabel)))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(info.title). \(info.description).")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - LowBandwidthModeBadge

/// A compact Liquid Glass pill displayed on media when a non-automatic bandwidth mode is active.
struct LowBandwidthModeBadge: View {

    let mode: LowBandwidthMediaMode
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Returns nil when mode is .automatic — callers should hide the badge in that case.
    private var badgeContent: (icon: String, label: String)? {
        switch mode {
        case .automatic:       return nil
        case .lowQualityVideo: return ("wifi.exclamationmark", "Low quality")
        case .audioOnly:       return ("headphones", "Audio only")
        case .transcriptOnly:  return ("text.alignleft", "Text only")
        case .wifiOnly:        return ("wifi", "Wi-Fi only")
        }
    }

    var body: some View {
        if let content = badgeContent {
            HStack(spacing: 4) {
                Image(systemName: content.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(content.label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.regularMaterial))
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            )
            .accessibilityLabel("Bandwidth mode: \(content.label)")
        }
    }
}

// MARK: - LowBandwidthModeSettingsSheet

/// Full settings sheet: mode selector + Save for Offline section.
/// Wraps `LowBandwidthModeSelector` and delegates saves to `OfflineMediaManager`.
struct LowBandwidthModeSettingsSheet: View {

    @Binding var selectedMode: LowBandwidthMediaMode
    let onDismiss: () -> Void

    @ObservedObject private var offlineManager = OfflineMediaManager.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if AMENFeatureFlags.shared.mediaLowBandwidthModeEnabled {
                content
            } else {
                unavailableView
            }
        }
    }

    // MARK: Content

    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    bandwidthSection
                    offlineSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Bandwidth & Offline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    private var bandwidthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Streaming quality",
                subtitle: "Controls how media loads when bandwidth is limited."
            )
            LowBandwidthModeSelector(selectedMode: $selectedMode)
        }
    }

    private var offlineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Save for offline",
                subtitle: "Items saved offline load without a network connection."
            )

            if offlineManager.downloadedItems.isEmpty {
                Text("No items saved for offline use.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(offlineManager.downloadedItems) { item in
                        offlineItemRow(item)
                    }
                }
            }
        }
    }

    private func offlineItemRow(_ item: OfflineMediaItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "Untitled media")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.savedMode.settingsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                offlineManager.removeOfflineItem(mediaId: item.mediaId)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(.systemRed))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Remove \(item.title ?? "item") from offline storage")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Unavailable

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Bandwidth controls are not available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - LowBandwidthMediaMode Helpers

private extension LowBandwidthMediaMode {
    var settingsLabel: String {
        switch self {
        case .automatic:       return "Automatic"
        case .lowQualityVideo: return "Lower quality video"
        case .audioOnly:       return "Audio only"
        case .transcriptOnly:  return "Text only"
        case .wifiOnly:        return "Wi-Fi only"
        }
    }
}

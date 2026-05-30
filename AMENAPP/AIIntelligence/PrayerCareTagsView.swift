// PrayerCareTagsView.swift
// AMEN App — Prayer Safety + Pastoral Escalation (Agent 4)
//
// Care tag picker shown before publishing a prayer request.
// Tags help route prayers to the right community support.
// Optional: users can skip entirely.

import SwiftUI

// MARK: - Care Tags Picker

struct PrayerCareTagsView: View {
    @Binding var selectedTags: Set<PrayerCareTag>
    let maxTags: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Prayer Focus (optional)", systemImage: "tag.fill")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.secondary)

                Spacer()

                if !selectedTags.isEmpty {
                    Button("Clear") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            selectedTags.removeAll()
                        }
                    }
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }

            PrayerCareFlowLayout(spacing: 8) {
                ForEach(PrayerCareTag.allCases, id: \.self) { tag in
                    PrayerCareTagChip(
                        tag: tag,
                        isSelected: selectedTags.contains(tag),
                        canSelect: selectedTags.count < maxTags || selectedTags.contains(tag)
                    ) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                            if selectedTags.contains(tag) {
                                selectedTags.remove(tag)
                            } else if selectedTags.count < maxTags {
                                selectedTags.insert(tag)
                            }
                        }
                    }
                }
            }

            if selectedTags.count >= maxTags {
                Text("Maximum \(maxTags) focus areas selected.")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
        }
    }
}

// MARK: - Tag Chip

private struct PrayerCareTagChip: View {
    let tag: PrayerCareTag
    let isSelected: Bool
    let canSelect: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: tag.systemIcon)
                    .font(.system(size: 11, weight: .semibold))
                Text(tag.displayName)
                    .font(.custom("OpenSans-Regular", size: 13))
            }
            .foregroundStyle(isSelected ? .white : textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? AnyShapeStyle(Color(red: 0.56, green: 0.40, blue: 0.85))
                    : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected
                            ? Color.clear
                            : Color(uiColor: .separator).opacity(0.4),
                        lineWidth: 0.5
                    )
            )
            .opacity(canSelect ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!canSelect && !isSelected)
        .accessibilityLabel("\(tag.displayName) \(isSelected ? "selected" : "not selected")")
    }

    private var textColor: Color {
        canSelect ? Color(uiColor: .label) : Color(uiColor: .secondaryLabel)
    }
}

// MARK: - Prayer Safety Care Banner

/// Shown when the pre-publish scan detects an urgent signal in a prayer request.
struct PrayerSafetyCareBanner: View {
    let result: PrayerSafetyScanResult
    @State private var showResources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("We care about you")
                        .font(.custom("OpenSans-Bold", size: 15))
                    Text("If you're going through something difficult, help is available.")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !result.resourcesToSurface.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showResources.toggle()
                    }
                } label: {
                    HStack {
                        Text("See resources")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(Color(red: 0.16, green: 0.40, blue: 0.76))
                        Image(systemName: showResources ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 0.16, green: 0.40, blue: 0.76))
                    }
                }
                .buttonStyle(.plain)

                if showResources {
                    VStack(spacing: 8) {
                        ForEach(result.resourcesToSurface) { resource in
                            PrayerCareResourceRow(resource: resource)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Resource Row

struct PrayerCareResourceRow: View {
    let resource: PrayerCareResource

    var body: some View {
        Button {
            if let url = resource.actionURL {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: resource.isEmergency ? "phone.fill" : "person.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(resource.isEmergency ? .red : Color(red: 0.16, green: 0.40, blue: 0.76))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(resource.title)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.primary)
                    Text(resource.subtitle)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if resource.actionURL != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(resource.actionURL == nil)
    }
}

// MARK: - Simple Flow Layout

private struct PrayerCareFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let containerWidth = proposal.width ?? 320
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: containerWidth, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

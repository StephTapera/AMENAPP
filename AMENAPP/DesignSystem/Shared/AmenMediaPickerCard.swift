// AmenMediaPickerCard.swift
// AMEN — DesignSystem/Shared
//
// Reusable glass floating card for camera / photos / files attachment.
// Extracted from CreatePostView's local AttachmentPickerFloatingCard;
// can now be adopted by any composer surface without duplicating code.
//
// Usage:
//   AmenMediaPickerCard(onCamera: { ... }, onPhotos: { ... }, onFiles: { ... })
//   — or —
//   AmenMediaPickerCard(items: [.camera, .photos, .files], onSelect: { item in ... })
//
// Glass: .amenGlassEffect(in: RoundedRectangle) for the card surface;
//        .amenGlassEffect(in: Circle()) per icon circle.
// Fallback: solid systemBackground card when reduceTransparency is true.
// No-glass-on-glass: the icon circles use individual glass layers WITHIN the
// card surface. The card itself is a single glass surface (no nesting).

import SwiftUI

// MARK: - Item definition

public enum AmenMediaPickerItem: Hashable, CaseIterable {
    case camera
    case photos
    case files

    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .photos: return "photo.fill"
        case .files:  return "doc.fill"
        }
    }

    var label: String {
        switch self {
        case .camera: return "Camera"
        case .photos: return "Photos"
        case .files:  return "Files"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .camera: return "Take a photo with camera"
        case .photos: return "Choose from photo library"
        case .files:  return "Attach a file"
        }
    }
}

// MARK: - Card view

/// Floating glass picker card with camera / photos / files rows.
/// Width is fixed at 200 pt to match the iOS composer attachment card pattern.
public struct AmenMediaPickerCard: View {
    public let items: [AmenMediaPickerItem]
    public let onSelect: (AmenMediaPickerItem) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        items: [AmenMediaPickerItem] = AmenMediaPickerItem.allCases,
        onSelect: @escaping (AmenMediaPickerItem) -> Void
    ) {
        self.items = items
        self.onSelect = onSelect
    }

    // Convenience init matching the old AttachmentPickerFloatingCard API
    public init(
        onCamera: @escaping () -> Void,
        onPhotos: @escaping () -> Void,
        onFiles: @escaping () -> Void
    ) {
        self.items = AmenMediaPickerItem.allCases
        self.onSelect = { item in
            switch item {
            case .camera: onCamera()
            case .photos: onPhotos()
            case .files:  onFiles()
            }
        }
    }

    public var body: some View {
        let rows = VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                if index > 0 { rowDivider }
                AmenMediaPickerRow(item: item) { onSelect(item) }
            }
        }
        .frame(width: 200)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

        if reduceTransparency {
            rows
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
                        )
                )
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        } else {
            rows
                .amenGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 20, y: 8)
        }
    }

    private var rowDivider: some View {
        Divider()
            .opacity(0.3)
            .padding(.leading, 72)
    }
}

// MARK: - Row

public struct AmenMediaPickerRow: View {
    let item: AmenMediaPickerItem
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(item: AmenMediaPickerItem, action: @escaping () -> Void) {
        self.item = item
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                AmenMediaPickerIconCircle(icon: item.icon)
                Text(item.label)
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityHint(item.accessibilityHint)
    }
}

// MARK: - Icon circle

/// Glass circle icon. Uses .amenGlassEffect per-circle — NOT on the card as a whole.
public struct AmenMediaPickerIconCircle: View {
    let icon: String

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(icon: String) { self.icon = icon }

    public var body: some View {
        if reduceTransparency {
            Image(systemName: icon)
                .font(.systemScaled(18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(.secondarySystemBackground)))
                .clipShape(Circle())
        } else {
            Image(systemName: icon)
                .font(.systemScaled(18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .amenGlassEffect(in: Circle())
        }
    }
}

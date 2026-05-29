// AMENActionSheet.swift
// AMEN App — Liquid Glass bottom action sheet.
//
// Frosted glass background (regularMaterial).  Optional AMENCategoryChips
// strip at the top.  Each row is a full-width tappable item.
// iOS 26+: native glass surface.  iOS 17-25: regularMaterial fallback.

import SwiftUI

// MARK: - Model

struct AMENActionSheetItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void

    init(
        id: String = UUID().uuidString,
        icon: String,
        title: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id            = id
        self.icon          = icon
        self.title         = title
        self.isDestructive = isDestructive
        self.action        = action
    }
}

// MARK: - Sheet View

struct AMENActionSheet: View {
    let items: [AMENActionSheetItem]
    var chips: [AMENCategoryChip] = []
    var onChipSelected: ((String?) -> Void)? = nil

    @State private var selectedChipID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.primary.opacity(0.18))
                .frame(
                    width:  AMENGlassMediaTokens.sheetHandleWidth,
                    height: AMENGlassMediaTokens.sheetHandleHeight
                )
                .padding(.top, 10)
                .padding(.bottom, 8)

            // Optional chip strip
            if !chips.isEmpty {
                AMENCategoryChips(chips: chips, selectedID: $selectedChipID)
                    .padding(.bottom, 4)
                    .onChange(of: selectedChipID) { _, newValue in
                        onChipSelected?(newValue)
                    }
                Divider().padding(.horizontal, AMENGlassMediaTokens.sheetHPad)
            }

            // Action rows
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    actionRow(item)
                    if idx < items.count - 1 {
                        Divider()
                            .padding(.horizontal, AMENGlassMediaTokens.sheetHPad)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .background { sheetSurface }
        .clipShape(
            RoundedRectangle(
                cornerRadius: AMENGlassMediaTokens.sheetCornerRadius,
                style: .continuous
            )
        )
        .presentationDetents([.height(sheetHeight), .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(AMENGlassMediaTokens.sheetCornerRadius)
        .presentationBackground(.regularMaterial)
    }

    // MARK: - Row

    private func actionRow(_ item: AMENActionSheetItem) -> some View {
        Button {
            HapticManager.impact(style: .light)
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                item.action()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: item.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                    .frame(width: 26, alignment: .center)
                    .accessibilityHidden(true)
                Text(item.title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                Spacer()
            }
            .padding(.horizontal, AMENGlassMediaTokens.sheetHPad)
            .frame(height: AMENGlassMediaTokens.sheetRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }

    // MARK: - Background

    @ViewBuilder
    private var sheetSurface: some View {
        if reduceTransparency {
            Color(.systemBackground)
        } else if #available(iOS 26.0, *) {
            Color.clear
                .background(.regularMaterial)
                .overlay(Color.white.opacity(0.05))
        } else {
            Color.clear.background(.regularMaterial)
        }
    }

    // MARK: - Sizing

    private var sheetHeight: CGFloat {
        let chipExtra: CGFloat = chips.isEmpty ? 0 : (AMENGlassMediaTokens.chipHeight + 20)
        return CGFloat(items.count) * AMENGlassMediaTokens.sheetRowHeight + chipExtra + 80
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var show = true

    Color(red: 0.92, green: 0.88, blue: 0.82)
        .ignoresSafeArea()
        .sheet(isPresented: $show) {
            AMENActionSheet(
                items: [
                    AMENActionSheetItem(icon: "square.and.arrow.down", title: "Save") { },
                    AMENActionSheetItem(icon: "character.bubble",       title: "Translate") { },
                    AMENActionSheetItem(icon: "captions.bubble",        title: "Closed Captions") { },
                    AMENActionSheetItem(icon: "qrcode",                 title: "QR Code") { },
                    AMENActionSheetItem(icon: "arrow.2.squarepath",     title: "Remix") { },
                    AMENActionSheetItem(icon: "flag",                   title: "Report", isDestructive: true) { }
                ],
                chips: [
                    AMENCategoryChip(label: "All"),
                    AMENCategoryChip(label: "Faith"),
                    AMENCategoryChip(label: "Prayer")
                ]
            )
        }
}

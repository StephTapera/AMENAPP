//
//  BereanWallpaperPickerSheet.swift
//  AMENAPP
//
//  Curated wallpaper picker for Berean chat.
//

import SwiftUI

struct BereanWallpaperPickerSheet: View {
    @ObservedObject var manager: BereanWallpaperManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                    wallpaperCard(title: "Default", isSelected: manager.selection == .none) {
                        manager.selection = .none
                    } preview: {
                        BereanColor.background
                    }

                    ForEach(manager.availablePresets) { preset in
                        wallpaperCard(title: preset.name, isSelected: manager.selection == .curated(preset.id)) {
                            manager.selection = .curated(preset.id)
                        } preview: {
                            preset.gradient
                        }
                    }
                }
                .padding(.horizontal, 16)

                Text("Your wallpaper never overrides readability. Berean auto-protects contrast.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(white: 0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .background(Color(red: 0.98, green: 0.98, blue: 0.98))
            .navigationTitle("Chat Wallpaper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private func wallpaperCard<Preview: View>(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder preview: @escaping () -> Preview
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                preview()
                    .frame(height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? Color.black.opacity(0.5) : Color.black.opacity(0.08), lineWidth: 1)
                    )

                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.12))
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

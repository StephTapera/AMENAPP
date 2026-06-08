// AmenSyncEntryView.swift
// AMEN Sync — Entry Point
// White Liquid Glass design. Create once, distribute everywhere.

import SwiftUI
import PhotosUI

struct AmenSyncEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AmenSyncViewModel()
    @State private var showStudio = false
    @State private var showDrafts = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isLoadingAssets = false
    @State private var selectedIntent: SyncIntent = .testimony

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        headerSection
                            .padding(.top, 24)

                        intentSection

                        startSection

                        recentDraftsSection

                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(16, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 1))
                            )
                            .foregroundStyle(.primary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showDrafts = true
                    } label: {
                        Image(systemName: "doc.text.fill")
                            .font(.systemScaled(15))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showStudio) {
            AmenSyncStudioView(vm: vm, intent: selectedIntent)
        }
        .sheet(isPresented: $showDrafts) {
            AmenSyncDraftsView()
        }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            isLoadingAssets = true
            Task {
                await vm.uploadAssets(from: items)
                isLoadingAssets = false
                showStudio = true
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.teal.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.systemScaled(22))
                        .foregroundStyle(.teal)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("AMEN Sync")
                        .font(.custom("OpenSans-Bold", size: 22))
                    Text("Create once · Fit everywhere · Share safely")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Intent Selection

    private var intentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What are you creating?")
                .font(.custom("OpenSans-Bold", size: 17))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SyncIntent.allCases) { intent in
                    IntentCard(
                        intent: intent,
                        isSelected: selectedIntent == intent
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                            selectedIntent = intent
                        }
                    }
                }
            }
        }
    }

    // MARK: - Start Section

    private var startSection: some View {
        VStack(spacing: 14) {
            // Add media button
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos])
            ) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black)
                            .frame(width: 44, height: 44)
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.systemScaled(18))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Photos or Videos")
                            .font(.custom("OpenSans-Bold", size: 15))
                        Text("AMEN will auto-fit for every platform")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isLoadingAssets {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Or start text-first
            Button {
                vm.mediaType = .text
                showStudio = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: "text.quote")
                            .font(.systemScaled(18))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start with Text")
                            .font(.custom("OpenSans-Bold", size: 15))
                        Text("Caption, verse, or message")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Recent Drafts

    private var recentDraftsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Platform Destinations")
                    .font(.custom("OpenSans-Bold", size: 17))
                Spacer()
            }

            Text("AMEN Sync automatically prepares your content for all of these formats at once.")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            // Platform grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(SyncPlatform.allCases.prefix(9)) { platform in
                    PlatformBadgeItem(platform: platform)
                }
            }
        }
    }
}

// MARK: - Sync Intent

enum SyncIntent: String, CaseIterable, Identifiable {
    case testimony     = "testimony"
    case prayer        = "prayer"
    case churchPromo   = "churchPromo"
    case teaching      = "teaching"
    case verseReflection = "verseReflection"
    case announcement  = "announcement"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .testimony:       return "Testimony"
        case .prayer:          return "Prayer"
        case .churchPromo:     return "Church Promo"
        case .teaching:        return "Teaching"
        case .verseReflection: return "Verse"
        case .announcement:    return "Announcement"
        }
    }

    var icon: String {
        switch self {
        case .testimony:       return "quote.bubble.fill"
        case .prayer:          return "hands.sparkles.fill"
        case .churchPromo:     return "building.columns.fill"
        case .teaching:        return "graduationcap.fill"
        case .verseReflection: return "book.fill"
        case .announcement:    return "megaphone.fill"
        }
    }

    var color: Color {
        switch self {
        case .testimony:       return .blue
        case .prayer:          return .purple
        case .churchPromo:     return .teal
        case .teaching:        return .brown
        case .verseReflection: return Color(red: 0.5, green: 0.3, blue: 0.7)
        case .announcement:    return .orange
        }
    }
}

// MARK: - Intent Card

struct IntentCard: View {
    let intent: SyncIntent
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: intent.icon)
                    .font(.systemScaled(16))
                    .foregroundStyle(isSelected ? intent.color : .secondary)
                    .frame(width: 24)

                Text(intent.displayName)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(11, weight: .bold))
                        .foregroundStyle(intent.color)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? intent.color.opacity(0.08) : Color.gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected ? intent.color.opacity(0.35) : Color.black.opacity(0.07),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
            .scaleEffect(isSelected ? 1.01 : 1.0)
            .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75)), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Platform Badge

struct PlatformBadgeItem: View {
    let platform: SyncPlatform

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(platform.iconColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: platform.icon)
                    .font(.systemScaled(18))
                    .foregroundStyle(platform.iconColor)
            }

            Text(platform.displayName)
                .font(.custom("OpenSans-Regular", size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

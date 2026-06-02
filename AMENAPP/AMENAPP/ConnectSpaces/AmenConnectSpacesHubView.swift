// AmenConnectSpacesHubView.swift
// AMEN Connect + Spaces — Top-level hub
//
// Entry point routed from the main tab bar (tab 6 — "Spaces").
// Lists stubbed Ministry Spaces and Connect Teaching videos.
// Glass ONLY on section-header bars and card backgrounds.
// All scripture / message bodies remain matte.

import SwiftUI
import FirebaseAuth
import FirebaseAnalytics

// MARK: - Preview stub data

private let previewSpaces: [AmenConnectSpacesSpace] = [
    AmenConnectSpacesSpace(
        id: "space-1",
        name: "Small Group — Psalm 119",
        type: .smallGroup,
        memberIds: ["u1", "u2", "u3"],
        careSensitivity: false,
        createdBy: "u1",
        createdAt: Date(),
        updatedAt: Date()
    ),
    AmenConnectSpacesSpace(
        id: "space-2",
        name: "Sunday Worship Team",
        type: .worship,
        memberIds: ["u1", "u4", "u5"],
        careSensitivity: false,
        createdBy: "u1",
        createdAt: Date(),
        updatedAt: Date()
    ),
    AmenConnectSpacesSpace(
        id: "space-3",
        name: "Prayer Team",
        type: .prayer,
        memberIds: ["u1", "u6"],
        careSensitivity: true,
        createdBy: "u1",
        createdAt: Date(),
        updatedAt: Date()
    )
]

private let previewVideos: [AmenConnectSpacesConnectVideo] = [
    AmenConnectSpacesConnectVideo(
        id: "video-1",
        provenance: AmenConnectSpacesVideoProvenance(
            humanRecorded: true,
            aiEdited: false,
            aiGenerated: false,
            synthVoice: false,
            synthFace: false,
            deepfakeRisk: 0.0,
            verifiedOriginal: true
        ),
        teacherId: "pastor_james",
        transcriptRef: "transcripts/v1",
        claims: [],
        scriptureRefs: [],
        sponsored: false,
        createdAt: Date(),
        updatedAt: Date()
    ),
    AmenConnectSpacesConnectVideo(
        id: "video-2",
        provenance: AmenConnectSpacesVideoProvenance(
            humanRecorded: true,
            aiEdited: false,
            aiGenerated: false,
            synthVoice: false,
            synthFace: false,
            deepfakeRisk: 0.0,
            verifiedOriginal: true
        ),
        teacherId: "pastor_anna",
        transcriptRef: "transcripts/v2",
        claims: [],
        scriptureRefs: [],
        sponsored: false,
        createdAt: Date(),
        updatedAt: Date()
    )
]

// MARK: - Room type icon helper

private func roomTypeIcon(_ type: AmenConnectSpacesRoomType) -> String {
    switch type {
    case .smallGroup:      return "person.3"
    case .prayer:          return "hands.sparkles"
    case .worship:         return "music.note"
    case .missions:        return "globe.americas"
    case .staff:           return "briefcase"
    case .cohort:          return "square.grid.2x2"
    case .accountability:  return "shield.lefthalf.filled"
    }
}

// MARK: - Hub View

struct AmenConnectSpacesHubView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCreateSpace = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Matte background — never glass on the page canvas
                Color(red: 0.027, green: 0.024, blue: 0.031)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        // MARK: Ministry Spaces section
                        sectionHeader(
                            title: "Ministry Spaces",
                            foreground: Color(hex: "D9A441")
                        )

                        VStack(spacing: 12) {
                            ForEach(previewSpaces) { space in
                                NavigationLink(destination: AmenMinistryRoomShellView(space: space)) {
                                    SpaceCardRow(space: space)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(space.name), \(space.memberIds.count) members")
                            }
                        }
                        .padding(.horizontal, 16)

                        // MARK: Connect Teaching section
                        sectionHeader(
                            title: "Connect — Teaching",
                            foreground: Color(hex: "6E4BB5")
                        )

                        VStack(spacing: 12) {
                            ForEach(previewVideos) { video in
                                NavigationLink(destination: AmenConnectPlayerView(video: video)) {
                                    VideoCardRow(video: video)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Teaching by \(video.teacherId), tap to play")
                            }
                        }
                        .padding(.horizontal, 16)

                        // Bottom breathing room above floating tab bar
                        Spacer(minLength: 100)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Spaces & Connect")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSpace = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("Create a new Space")
                }
            }
            .sheet(isPresented: $showCreateSpace) {
                AmenCreateSpaceEnhancedSheet(
                    userId: Auth.auth().currentUser?.uid ?? "",
                    onDismiss: { showCreateSpace = false },
                    onCreated: { _ in showCreateSpace = false }
                )
            }
            .onAppear {
                Analytics.logEvent("spaces_hub_viewed", parameters: [:])
            }
        }
    }

    // MARK: - Section header bar (glass pill)

    @ViewBuilder
    private func sectionHeader(title: String, foreground: Color) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(1.2)
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(foreground.opacity(0.25), lineWidth: 0.5)
                    }
            }
            .padding(.horizontal, 16)
    }
}

// MARK: - Space card row

private struct SpaceCardRow: View {
    let space: AmenConnectSpacesSpace

    var body: some View {
        HStack(spacing: 14) {

            // Room type icon in a glass circle
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .strokeBorder(Color(hex: "D9A441").opacity(0.30), lineWidth: 0.5)
                    }
                    .frame(width: 44, height: 44)

                Image(systemName: roomTypeIcon(space.type))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
            }

            // Name + member count
            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.50))
                    Text("\(space.memberIds.count) members")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.50))

                    if space.careSensitivity {
                        // Privacy indicator for sensitive rooms
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: "D9A441").opacity(0.70))
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.30))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Video card row

private struct VideoCardRow: View {
    let video: AmenConnectSpacesConnectVideo

    var body: some View {
        HStack(spacing: 14) {

            // Play icon in a glass circle
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .strokeBorder(Color(hex: "6E4BB5").opacity(0.30), lineWidth: 0.5)
                    }
                    .frame(width: 44, height: 44)

                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "6E4BB5"))
                    .offset(x: 1) // optical center correction for play triangle
            }

            // Teacher name + provenance badge
            VStack(alignment: .leading, spacing: 6) {
                Text("Teaching by \(video.teacherId)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                // Non-removable provenance badge (Aegis: syntheticMediaLabelsNonRemovable)
                AmenSyntheticMediaLabelView(provenance: video.provenance)
                    .scaleEffect(0.90, anchor: .leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.30))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenConnectSpacesHubView()
        .preferredColorScheme(.dark)
}
#endif

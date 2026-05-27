// CreatorSpacesHub.swift
// AMENAPP — Creator Spaces entry point, lives inside the Resources tab.

import SwiftUI

struct CreatorSpacesHub: View {
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @State private var selectedMode: CSCaptureMode? = nil
    @State private var showCapture = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    headerSection
                    captureModesSection
                    recentCreationsSection
                }
                .padding(.bottom, 32)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Creator Spaces")
            .navigationBarTitleDisplayMode(.large)
            .fullScreenCover(isPresented: $showCapture) {
                if let mode = selectedMode {
                    PresenceCaptureView(mode: mode)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trusted intelligent creativity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            provenancePhilosophyBanner
        }
    }

    private var provenancePhilosophyBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(AmenTheme.Colors.amenGold)

            VStack(alignment: .leading, spacing: 2) {
                Text("Human-made. Provably real.")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text("Every post carries a provenance label. No AI fakes, ever.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AmenTheme.Colors.amenGold.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Capture Modes

    private var captureModesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, 20)
                .padding(.top, 28)

            VStack(spacing: 10) {
                ForEach(CSCaptureMode.allCases) { mode in
                    captureModeCard(mode)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func captureModeCard(_ mode: CSCaptureMode) -> some View {
        Button {
            selectedMode = mode
            showCapture = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(modeAccentColor(mode).opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: mode.systemIcon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(modeAccentColor(mode))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func modeAccentColor(_ mode: CSCaptureMode) -> Color {
        switch mode {
        case .presence: return AmenTheme.Colors.amenBlue
        case .truth:    return AmenTheme.Colors.amenGold
        case .audio:    return AmenTheme.Colors.amenPurple
        }
    }

    // MARK: - Recent Creations (stub — wired in Phase 2)

    private var recentCreationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Creations")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, 20)
                .padding(.top, 28)

            Text("Your posts will appear here after you capture.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
        }
    }
}

// MARK: - AmenTheme extension bridge (fills any missing tokens)

private extension AmenTheme.Colors {
    static var amenBlue: Color   { Color(red: 0.20, green: 0.48, blue: 0.96) }
    static var amenPurple: Color { Color(red: 0.42, green: 0.28, blue: 1.00) }
}

#Preview {
    CreatorSpacesHub()
}

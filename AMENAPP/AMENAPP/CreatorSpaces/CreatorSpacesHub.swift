// CreatorSpacesHub.swift
// AMENAPP — Creator Spaces entry point, lives inside the Resources tab.

import SwiftUI

struct CreatorSpacesHub: View {
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @State private var selectedMode: CSCaptureMode? = nil
    @State private var showCapture = false
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                    captureModesSection
                    recentCreationsSection
                }
                .padding(.bottom, 40)
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
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                appeared = true
            }
            CreatorSpacesAnalytics.track(.creatorSpaceJoined, parameters: ["surface": "creator_hub"])
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Trusted intelligent creativity.")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)

            provenancePhilosophyBanner
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
        }
    }

    private var provenancePhilosophyBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
            }
            .frame(width: 44, height: 44)
            .amenGlassEffect(AmenTheme.Colors.amenGold.opacity(0.18), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Human-made. Provably real.")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)

                Text("Every post carries a provenance label. No AI fakes, ever.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .amenGlassEffect(AmenTheme.Colors.amenGold.opacity(0.10), cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AmenTheme.Colors.amenGold.opacity(0.30), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Capture Modes

    private var captureModesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Create", systemImage: "plus.circle.fill")
                .padding(.top, 32)

            VStack(spacing: 10) {
                ForEach(Array(CSCaptureMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    captureModeCard(mode)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(
                            .spring(response: 0.44, dampingFraction: 0.84)
                            .delay(0.08 + Double(index) * 0.06),
                            value: appeared
                        )
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
            HStack(spacing: 14) {
                ZStack {
                    Image(systemName: mode.systemIcon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(modeAccentColor(mode))
                }
                .frame(width: 46, height: 46)
                .amenGlassEffect(modeAccentColor(mode).opacity(0.18), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.displayName)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                    Text(mode.description)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .amenGlassEffect(modeAccentColor(mode).opacity(0.07), cornerRadius: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(modeAccentColor(mode).opacity(0.18), lineWidth: 0.8)
            )
        }
        .buttonStyle(CreatorCardButtonStyle())
    }

    private func modeAccentColor(_ mode: CSCaptureMode) -> Color {
        switch mode {
        case .presence: return AmenTheme.Colors.amenBlue
        case .truth:    return AmenTheme.Colors.amenGold
        case .audio:    return AmenTheme.Colors.amenPurple
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)
            Text(title)
                .font(AMENFont.semiBold(18))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Recent Creations

    private var recentCreationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Your Creations", systemImage: "photo.stack.fill")
                .padding(.top, 32)
                .opacity(appeared ? 1 : 0)

            emptyCreationsCard
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.spring(response: 0.44, dampingFraction: 0.84).delay(0.28), value: appeared)
        }
    }

    private var emptyCreationsCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.badge.plus")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(AmenTheme.Colors.amenGold.opacity(0.7))

            Text("Your posts will appear here after you capture.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .amenGlassEffect(cornerRadius: 16)
        .padding(.horizontal, 20)
    }
}

// MARK: - Button Style

private struct CreatorCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

#Preview {
    CreatorSpacesHub()
}

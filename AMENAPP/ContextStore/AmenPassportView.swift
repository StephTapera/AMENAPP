// AmenPassportView.swift
// AMEN Universal Migration & Context System — Wave 1 (passport-ui)
//
// The Passport onboarding shell: calm, human, glass. Three entry choices route
// into the manual facet editor, a Berean stub, and an Import stub (other waves
// fill the stubs). Everything is gated on the master context flag; nothing is
// user-visible until it is true.

import SwiftUI

struct AmenPassportView: View {
    @StateObject private var flags = AMENFeatureFlags.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if flags.contextSystemEnabled {
                NavigationStack { content }
            } else {
                disabledState
            }
        }
    }

    // MARK: Enabled content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                VStack(spacing: 12) {
                    // Manual entry — owned by this wave.
                    NavigationLink {
                        ManualFacetEntryView()
                    } label: {
                        PassportChoiceRow(
                            icon: "square.and.pencil",
                            title: "Tell us about yourself",
                            subtitle: "Add a few things by hand. Calm and unhurried.",
                            badge: nil
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!flags.contextManualEntryEnabled)
                    .opacity(flags.contextManualEntryEnabled ? 1 : 0.5)

                    // Berean interview — lightweight placeholder; Wave 2 fills it.
                    NavigationLink {
                        PassportBereanStubView()
                    } label: {
                        PassportChoiceRow(
                            icon: "bird",
                            title: "Talk with Berean",
                            subtitle: "A gentle conversation that fills your Passport.",
                            badge: flags.contextBereanInterviewEnabled ? nil : "Soon"
                        )
                    }
                    .buttonStyle(.plain)

                    // Universal import — lightweight placeholder; Wave 3 fills it.
                    NavigationLink {
                        PassportImportStubView()
                    } label: {
                        PassportChoiceRow(
                            icon: "tray.and.arrow.down",
                            title: "Bring context from another app",
                            subtitle: "Paste or import — you approve every detail first.",
                            badge: flags.contextUniversalImportEnabled ? nil : "Soon"
                        )
                    }
                    .buttonStyle(.plain)
                }

                footnote
            }
            .padding(20)
        }
        .navigationTitle("Passport")
        .navigationBarTitleDisplayMode(.inline)
        .background(passportBackground.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AMEN PASSPORT")
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            Text("Let's get to know you.")
                .font(.largeTitle.weight(.bold))
            Text("Your context lives only where you allow it. Everything you add starts private — you choose what to share, one thing at a time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footnote: some View {
        Text("No content is ever imported automatically. Nothing is ranked. Private facets never leave your device.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    @ViewBuilder
    private var passportBackground: some View {
        if reduceTransparency {
            Color(.systemBackground)
        } else {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: Disabled state

    private var disabledState: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Passport isn't available yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Choice row (glass card; flat content — no glass-on-glass)

private struct PassportChoiceRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let badge: String?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let badge {
                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 0.6))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PassportCardSurface(reduceTransparency: reduceTransparency))
        .contentShape(Rectangle())
    }
}

/// Single-layer glass card surface (no nested glass).
struct PassportCardSurface: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusMedium, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusMedium, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusMedium, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                )
        }
    }
}

// MARK: - Lightweight placeholder destinations (filled by later waves)

/// Berean Migration Interview entry point — Wave 2 replaces this destination.
struct PassportBereanStubView: View {
    var body: some View {
        ContextStubScaffold(
            icon: "bird",
            title: "Talk with Berean",
            message: "A gentle migration conversation will live here. Coming in a later release."
        )
        // TODO(gate: HUMAN-MACHINE) — berean: route to BereanInterviewView once Wave 2 wires the flag (ff_berean_interview_v2).
    }
}

/// Universal import entry point — Wave 3 replaces this destination.
struct PassportImportStubView: View {
    var body: some View {
        ContextStubScaffold(
            icon: "tray.and.arrow.down",
            title: "Bring context from another app",
            message: "Paste or import context here — you'll approve every detail first. Coming in a later release."
        )
        // TODO(gate: HUMAN-MACHINE) — import: route to the universal extractor + FacetApprovalView once Wave 3 wires the flag.
    }
}

private struct ContextStubScaffold: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

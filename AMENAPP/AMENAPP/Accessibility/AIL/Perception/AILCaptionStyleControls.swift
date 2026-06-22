// AILCaptionStyleControls.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Perception Surface (A4)
//
// Plain-language controls that bind every CaptionStyle field to the live profile
// (AILProfileService.shared.profile.captionStyle). Changing any control persists
// immediately through the profile service's didSet → setCaptionStyle path.
//
// IRON RULES: NO tier checks — caption styling is free at every tier. No force-
// unwraps. Labels are everyday words, not jargon ("Bigger words", not "xl").

import SwiftUI

/// A form section exposing the five CaptionStyle preferences with plain-language
/// labels. Reads/writes through the shared profile service so the choice follows
/// the account and is picked up by AILCaptionRenderer everywhere.
struct AILCaptionStyleControls: View {

    @State private var profileService = AILProfileService.shared

    var body: some View {
        Form {
            Section {
                Picker("Caption size", selection: sizeBinding) {
                    ForEach(CaptionStyle.Size.allCases, id: \.self) { size in
                        Text(label(for: size)).tag(size)
                    }
                }
                Picker("Background", selection: backgroundBinding) {
                    ForEach(CaptionStyle.Background.allCases, id: \.self) { bg in
                        Text(label(for: bg)).tag(bg)
                    }
                }
                Toggle("High contrast", isOn: highContrastBinding)
            } header: {
                Text("How captions look")
            } footer: {
                Text("These settings change captions on videos and live audio across the app.")
            }

            Section {
                Picker("Caption speed", selection: speedBinding) {
                    ForEach(CaptionStyle.Speed.allCases, id: \.self) { speed in
                        Text(label(for: speed)).tag(speed)
                    }
                }
                Picker("Position", selection: placementBinding) {
                    ForEach(CaptionStyle.Placement.allCases, id: \.self) { placement in
                        Text(label(for: placement)).tag(placement)
                    }
                }
            } header: {
                Text("How captions behave")
            }

            Section {
                AILCaptionStylePreview(style: profileService.profile.captionStyle)
            } header: {
                Text("Preview")
            }
        }
    }

    // MARK: - Bindings (route every mutation through the profile service)

    private var sizeBinding: Binding<CaptionStyle.Size> {
        Binding(
            get: { profileService.profile.captionStyle.size },
            set: { newValue in
                var style = profileService.profile.captionStyle
                style.size = newValue
                profileService.setCaptionStyle(style)
            }
        )
    }

    private var backgroundBinding: Binding<CaptionStyle.Background> {
        Binding(
            get: { profileService.profile.captionStyle.background },
            set: { newValue in
                var style = profileService.profile.captionStyle
                style.background = newValue
                profileService.setCaptionStyle(style)
            }
        )
    }

    private var highContrastBinding: Binding<Bool> {
        Binding(
            get: { profileService.profile.captionStyle.highContrast },
            set: { newValue in
                var style = profileService.profile.captionStyle
                style.highContrast = newValue
                profileService.setCaptionStyle(style)
            }
        )
    }

    private var speedBinding: Binding<CaptionStyle.Speed> {
        Binding(
            get: { profileService.profile.captionStyle.speed },
            set: { newValue in
                var style = profileService.profile.captionStyle
                style.speed = newValue
                profileService.setCaptionStyle(style)
            }
        )
    }

    private var placementBinding: Binding<CaptionStyle.Placement> {
        Binding(
            get: { profileService.profile.captionStyle.placement },
            set: { newValue in
                var style = profileService.profile.captionStyle
                style.placement = newValue
                profileService.setCaptionStyle(style)
            }
        )
    }

    // MARK: - Plain-language labels

    private func label(for size: CaptionStyle.Size) -> String {
        switch size {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        case .xl:     return "Largest"
        }
    }

    private func label(for background: CaptionStyle.Background) -> String {
        switch background {
        case .none:  return "Clear (no background)"
        case .dim:   return "Soft shade"
        case .solid: return "Solid block"
        }
    }

    private func label(for speed: CaptionStyle.Speed) -> String {
        switch speed {
        case .slow:   return "Slower"
        case .normal: return "Normal"
        case .fast:   return "Faster"
        }
    }

    private func label(for placement: CaptionStyle.Placement) -> String {
        switch placement {
        case .bottom: return "Bottom of screen"
        case .top:    return "Top of screen"
        }
    }
}

// MARK: - Inline preview

/// A tiny, static sample line so the user sees their choice take effect.
private struct AILCaptionStylePreview: View {
    let style: CaptionStyle

    var body: some View {
        AILCaptionRenderer(
            cues: [CaptionCue(startMs: 0, endMs: 2000, text: "This is how your captions will look.")],
            style: style
        )
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

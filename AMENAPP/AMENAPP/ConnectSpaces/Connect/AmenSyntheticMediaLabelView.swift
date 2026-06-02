// AmenSyntheticMediaLabelView.swift
// AMEN Connect
//
// NON-REMOVABLE provenance label.
// Aegis rule enforced: syntheticMediaLabelsNonRemovable
// No close button, no dismiss gesture, no opacity-zero path.
// Permanent for the lifetime of the video view.

import SwiftUI

/// A permanently visible pill label that communicates the provenance classification
/// of a Connect video. This view MUST NOT be wrapped in any conditional, sheet dismiss,
/// or opacity modifier that could hide it while the video is on screen.
struct AmenSyntheticMediaLabelView: View {

    let provenance: AmenConnectSpacesVideoProvenance

    // MARK: - Provenance label computation
    // Priority order: deepfakeRisk threshold → synthFace → synthVoice → aiGenerated
    // → humanRecorded+aiEdited → clean human original
    private var labelString: String {
        if provenance.deepfakeRisk > 0.7 {
            return "🔴 High deepfake risk"
        }
        if provenance.synthFace {
            return "🔴 Synthetic face — deepfake risk"
        }
        if provenance.synthVoice {
            return "🔔 Synthetic voice"
        }
        if provenance.aiGenerated {
            return "⚠️ AI-generated content"
        }
        if provenance.humanRecorded && provenance.aiEdited {
            return "🔵 Human-recorded · AI-edited"
        }
        // Clean human original: humanRecorded && !aiEdited && !aiGenerated && !synthVoice && !synthFace
        return "✅ Human-recorded original"
    }

    var body: some View {
        // Glass pill — amenPurple tint
        Text(labelString)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color(hex: "#6E4BB5"))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(Color(hex: "#6E4BB5").opacity(0.18))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color(hex: "#6E4BB5").opacity(0.40), lineWidth: 1)
                    }
            }
            // Aegis: no opacity path to zero, no close, no dismiss
            .accessibilityLabel("Provenance: \(labelString)")
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Hex color helper (local, non-conflicting)

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        AmenSyntheticMediaLabelView(provenance: AmenConnectSpacesVideoProvenance(
            humanRecorded: true, aiEdited: false, aiGenerated: false,
            synthVoice: false, synthFace: false, deepfakeRisk: 0.1, verifiedOriginal: true))

        AmenSyntheticMediaLabelView(provenance: AmenConnectSpacesVideoProvenance(
            humanRecorded: true, aiEdited: true, aiGenerated: false,
            synthVoice: false, synthFace: false, deepfakeRisk: 0.2, verifiedOriginal: false))

        AmenSyntheticMediaLabelView(provenance: AmenConnectSpacesVideoProvenance(
            humanRecorded: false, aiEdited: false, aiGenerated: true,
            synthVoice: false, synthFace: false, deepfakeRisk: 0.3, verifiedOriginal: false))

        AmenSyntheticMediaLabelView(provenance: AmenConnectSpacesVideoProvenance(
            humanRecorded: false, aiEdited: false, aiGenerated: false,
            synthVoice: true, synthFace: false, deepfakeRisk: 0.4, verifiedOriginal: false))

        AmenSyntheticMediaLabelView(provenance: AmenConnectSpacesVideoProvenance(
            humanRecorded: false, aiEdited: false, aiGenerated: false,
            synthVoice: false, synthFace: true, deepfakeRisk: 0.5, verifiedOriginal: false))

        AmenSyntheticMediaLabelView(provenance: AmenConnectSpacesVideoProvenance(
            humanRecorded: true, aiEdited: true, aiGenerated: false,
            synthVoice: false, synthFace: false, deepfakeRisk: 0.85, verifiedOriginal: false))
    }
    .padding()
    .background(Color(hex: "#070607"))
}
#endif

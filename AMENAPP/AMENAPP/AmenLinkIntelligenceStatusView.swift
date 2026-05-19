import SwiftUI

struct AmenLinkIntelligenceStatusView: View {
    let state: AmenUniversalLinkState

    private var label: String {
        switch state {
        case .detecting: return "Detecting"
        case .fetchingMetadata: return "Fetching"
        case .extractingLinks: return "Extracting"
        case .generatingContext: return "Context"
        case .ready: return "Ready"
        case .partial: return "Partial"
        case .failed: return "Failed"
        case .restricted: return "Restricted"
        case .unsafe: return "Unsafe"
        }
    }

    var body: some View {
        Text(label)
            .font(.systemScaled(10, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

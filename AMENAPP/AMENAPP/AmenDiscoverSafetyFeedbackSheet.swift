import SwiftUI

struct AmenDiscoverSafetyFeedbackSheet: View {
    let onSelect: (AmenDiscoverFeedbackType) -> Void

    var body: some View {
        NavigationStack {
            List(AmenDiscoverFeedbackType.allCases, id: \.self) { feedback in
                Button(label(for: feedback)) { onSelect(feedback) }
            }
            .navigationTitle("Discover Feedback")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func label(for feedback: AmenDiscoverFeedbackType) -> String {
        switch feedback {
        case .notForMe: return "Not for me"
        case .tooIntense: return "Too intense"
        case .repetitive: return "Repetitive"
        case .theologicallyUnclear: return "Theologically unclear"
        case .hideCreator: return "Hide creator"
        case .hideTopic: return "Hide topic"
        case .report: return "Report"
        case .reduceLocal: return "Reduce local recommendations"
        case .reduceAiAssisted: return "Reduce AI-assisted content"
        }
    }
}

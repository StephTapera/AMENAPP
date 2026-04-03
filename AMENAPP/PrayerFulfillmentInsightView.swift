import SwiftUI
import FirebaseFirestore

/// Read-only insight strip shown on prayer posts with community fulfillment data.
struct PrayerFulfillmentInsightView: View {
    let postId: String

    @State private var insightText: String? = nil
    @State private var appeared = false

    var body: some View {
        Group {
            if let text = insightText {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.systemScaled(14))
                        .foregroundStyle(Color.secondary)
                    Text(text)
                        .font(.systemScaled(11))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .opacity(appeared ? 1 : 0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.4)) { appeared = true }
                }
            }
        }
        .task { await loadInsight() }
    }

    private func loadInsight() async {
        let snap = try? await Firestore.firestore()
            .collection("posts").document(postId)
            .collection("insight").document("community")
            .getDocument()
        if let text = snap?.data()?["insightText"] as? String {
            await MainActor.run { insightText = text }
        }
    }
}

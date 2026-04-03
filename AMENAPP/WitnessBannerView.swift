import SwiftUI
import FirebaseAuth

/// Live witness presence pill — appears between post content and action buttons
/// on testimony posts only.
struct WitnessBannerView: View {
    @ObservedObject var service: TestimonyWitnessService

    @State private var pulseOpacity: Double = 1.0
    @State private var appeared = false

    private var count: Int { service.activeWitnesses.count }
    private var currentUid: String? { Auth.auth().currentUser?.uid }

    private var displayText: String {
        let othersCount = service.activeWitnesses.filter { $0.uid != currentUid }.count
        if othersCount == 0 { return "You're the first one here" }
        return "\(count) \(count == 1 ? "person" : "people") in this testimony right now"
    }

    // Top 3 witnesses that are not the current user (for avatar stack)
    private var avatarWitnesses: [TestimonyWitnessService.WitnessPresence] {
        Array(service.activeWitnesses.filter { $0.uid != currentUid }.prefix(3))
    }

    var body: some View {
        HStack(spacing: 8) {
            // Pulsing green dot
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .opacity(pulseOpacity)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        pulseOpacity = 0.15
                    }
                }

            // Avatar stack (up to 3)
            if !avatarWitnesses.isEmpty {
                HStack(spacing: -6) {
                    ForEach(avatarWitnesses) { witness in
                        WitnessAvatarCircle(photoURL: witness.photoURL, uid: witness.uid)
                    }
                }
            }

            // Count text
            Text(displayText)
                .font(.systemScaled(12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.75))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .offset(y: appeared ? 0 : 10)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }
}

private struct WitnessAvatarCircle: View {
    let photoURL: String?
    let uid: String

    var body: some View {
        Group {
            if let urlStr = photoURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: placeholderCircle
                    }
                }
            } else {
                placeholderCircle
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
    }

    private var placeholderCircle: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.25))
            .overlay(
                Text(String(uid.prefix(1)).uppercased())
                    .font(.systemScaled(9, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.6))
            )
    }
}

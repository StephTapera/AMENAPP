import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// Checks if the current user is under 13 (COPPA) and blocks AI features accordingly.
@MainActor
final class MinorSafetyService: ObservableObject {
    static let shared = MinorSafetyService()
    @Published private(set) var isConfirmedUnder13: Bool = false
    @Published private(set) var isLoaded: Bool = false

    private init() {
        Task { await loadAgeStatus() }
    }

    func loadAgeStatus() async {
        guard let uid = Auth.auth().currentUser?.uid else { isLoaded = true; return }
        do {
            let doc = try await Firestore.firestore().collection("users").document(uid).getDocument()
            let data = doc.data() ?? [:]
            // Check birthYear field; default to allowing access if not set
            if let birthYear = data["birthYear"] as? Int {
                let currentYear = Calendar.current.component(.year, from: Date())
                isConfirmedUnder13 = (currentYear - birthYear) < 13
            }
            isLoaded = true
        } catch {
            isLoaded = true // on error, default to allowing access
        }
    }
}

/// Gate view that blocks Berean AI for confirmed COPPA-age users.
struct BereanMinorBlockedView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Berean AI requires parental permission")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("This AI feature is available to users 13 and older. Please speak with a parent or guardian about enabling this feature.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Berean AI is not available for users under 13. Parental permission required.")
    }
}

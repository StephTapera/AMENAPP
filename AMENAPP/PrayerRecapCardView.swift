// PrayerRecapCardView.swift
// AMEN App — Weekly Prayer Journal Recap Card
// Renders the weekly AI-generated recap as a beautiful shareable card

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// ─── MARK: Model ─────────────────────────────────────────────────

struct PrayerRecap: Identifiable, Decodable {
    var id: String = UUID().uuidString
    let greeting: String
    let themes: [String]
    let themesSummary: String
    let answeredPrayers: String
    let burden: String
    let scripture: RecapScripture
    let word: String
    let closingPrayer: String
    let prayerCount: Int?

    struct RecapScripture: Decodable {
        let reference: String
        let verse: String
        let connection: String
    }
}

// ─── MARK: ViewModel ─────────────────────────────────────────────

@MainActor
final class PrayerRecapViewModel: ObservableObject {
    @Published var recap: PrayerRecap?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var userId: String { Auth.auth().currentUser?.uid ?? "demo_user" }

    func load() {
        db.collection("users").document(userId)
            .collection("weeklyRecaps")
            .order(by: "generatedAt", descending: true)
            .limit(to: 1)
            .getDocuments { [weak self] snap, _ in
                if let doc = snap?.documents.first {
                    var data = doc.data()
                    data["id"] = doc.documentID
                    if let jsonData = try? JSONSerialization.data(withJSONObject: data),
                       let decoded = try? JSONDecoder().decode(PrayerRecap.self, from: jsonData) {
                        DispatchQueue.main.async { self?.recap = decoded }
                        return
                    }
                }
                self?.generate()
            }
    }

    func generate() {
        isLoading = true
        errorMessage = nil

        let functions = Functions.functions()
        functions.httpsCallable("generatePrayerRecap").call { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Couldn't generate your recap. Try again."
                    print("Recap error:", error)
                    return
                }
                guard let data = result?.data as? [String: Any],
                      let recapData = data["recap"] as? [String: Any] else { return }
                if let jsonData = try? JSONSerialization.data(withJSONObject: recapData),
                   var decoded = try? JSONDecoder().decode(PrayerRecap.self, from: jsonData) {
                    if let recapId = data["recapId"] as? String { decoded.id = recapId }
                    self?.recap = decoded
                }
            }
        }
    }
}

// ─── MARK: Main View ─────────────────────────────────────────────

struct PrayerRecapCardView: View {
    @StateObject private var vm = PrayerRecapViewModel()

    var body: some View {
        ZStack {
            Color(hex: "080810").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("WEEK IN FAITH")
                                .font(.systemScaled(10, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(hex: "C9A84C").opacity(0.8))
                                .kerning(2)
                            Text("Your Prayer Recap")
                                .font(.systemScaled(22, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        if vm.recap != nil {
                            Button { vm.generate() } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.systemScaled(14, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.4))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                    if vm.isLoading {
                        recapLoadingCard
                    } else if let recap = vm.recap {
                        recapCards(recap)
                    } else if let err = vm.errorMessage {
                        errorCard(err)
                    } else {
                        emptyCard
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear { vm.load() }
    }

    private var recapLoadingCard: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 100)
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func recapCards(_ recap: PrayerRecap) -> some View {
        VStack(spacing: 12) {
            recapSection(accent: Color(hex: "C9A84C")) {
                VStack(alignment: .leading, spacing: 8) {
                    if let count = recap.prayerCount {
                        HStack(spacing: 6) {
                            Text("\(count) prayers this week")
                                .font(.systemScaled(11, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(hex: "C9A84C"))
                            Spacer()
                            Text(Date().formatted(.dateTime.month().day()))
                                .font(.systemScaled(11))
                                .foregroundColor(Color.white.opacity(0.3))
                        }
                    }
                    Text(recap.greeting).font(.systemScaled(16, weight: .semibold)).foregroundColor(.white).lineSpacing(4)
                    Text(recap.themesSummary).font(.systemScaled(14)).foregroundColor(Color.white.opacity(0.65)).lineSpacing(5)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(recap.themes, id: \.self) { theme in
                                Text(theme)
                                    .font(.systemScaled(11, weight: .medium))
                                    .foregroundColor(Color(hex: "C9A84C"))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color(hex: "C9A84C").opacity(0.1))
                                    .cornerRadius(20)
                                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: "C9A84C").opacity(0.25), lineWidth: 0.5))
                            }
                        }
                    }
                }
            }

            recapSection(accent: Color(hex: "22C55E")) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Answered Prayers", systemImage: "checkmark.seal.fill")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundColor(Color(hex: "22C55E"))
                    Text(recap.answeredPrayers).font(.systemScaled(14)).foregroundColor(Color.white.opacity(0.7)).lineSpacing(5)
                }
            }

            recapSection(accent: Color(hex: "7F77DD")) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("What You Carried", systemImage: "heart.fill")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundColor(Color(hex: "7F77DD"))
                    Text(recap.burden).font(.systemScaled(14)).foregroundColor(Color.white.opacity(0.7)).lineSpacing(5)
                }
            }

            recapSection(accent: Color(hex: "378ADD")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recap.scripture.reference).font(.systemScaled(12, weight: .bold)).foregroundColor(Color(hex: "378ADD"))
                    Text("\"\(recap.scripture.verse)\"").font(.systemScaled(15, weight: .medium)).foregroundColor(.white).lineSpacing(6).italic()
                    Text(recap.scripture.connection).font(.systemScaled(12)).foregroundColor(Color.white.opacity(0.4)).lineSpacing(4)
                }
            }

            recapSection(accent: Color(hex: "C9A84C")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WORD FOR THE WEEK AHEAD")
                        .font(.systemScaled(9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "C9A84C").opacity(0.6))
                        .kerning(2)
                    Text(recap.word).font(.systemScaled(15, weight: .semibold)).foregroundColor(.white).lineSpacing(6)
                }
            }

            recapSection(accent: Color.white.opacity(0.15)) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Closing Prayer", systemImage: "hands.and.sparkles.fill")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.4))
                    Text(recap.closingPrayer).font(.systemScaled(14)).foregroundColor(Color.white.opacity(0.65)).lineSpacing(6).italic()
                }
            }

            Button {
                // Share sheet
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up").font(.systemScaled(14, weight: .semibold))
                    Text("Share This Week").font(.systemScaled(15, weight: .semibold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(LinearGradient(colors: [Color(hex: "C9A84C"), Color(hex: "F0D080")],
                                           startPoint: .leading, endPoint: .trailing))
                .cornerRadius(16)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    private func recapSection<Content: View>(accent: Color, @ViewBuilder content: @escaping () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.2), lineWidth: 0.5))
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            Text("📖").font(.systemScaled(44))
            Text("No prayers logged this week")
                .font(.systemScaled(16, weight: .semibold))
                .foregroundColor(.white)
            Text("Start logging your prayers and come back Sunday for your personalized weekly recap.")
                .font(.systemScaled(14))
                .foregroundColor(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .cornerRadius(20)
        .padding(.horizontal, 20)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message).font(.systemScaled(14)).foregroundColor(Color.white.opacity(0.5)).multilineTextAlignment(.center)
            Button("Try Again") { vm.generate() }
                .font(.systemScaled(14, weight: .semibold))
                .foregroundColor(Color(hex: "C9A84C"))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }
}

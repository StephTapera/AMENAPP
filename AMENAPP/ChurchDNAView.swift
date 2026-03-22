// ChurchDNAView.swift
// AMENAPP
//
// Church DNA Detail View:
//   - Hexagonal radar chart (SwiftUI Canvas, 6 axes)
//   - "See theological profile" link in church detail screen
//   - Axis tap → bottom sheet with contributing sermon quotes
//   - Cloud Function: computeChurchDNA (called on-demand, cached in Firestore)

import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

// MARK: - DNA Axis

enum DNAAxis: String, CaseIterable, Identifiable {
    case grace             = "grace_emphasis"
    case word              = "word_centrality"
    case evangelism        = "evangelism_focus"
    case holySpirit        = "holy_spirit_gifts"
    case community         = "community_justice"
    case eschatology       = "eschatology_urgency"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grace:       return "Grace"
        case .word:        return "Word"
        case .evangelism:  return "Evangelism"
        case .holySpirit:  return "Spirit"
        case .community:   return "Community"
        case .eschatology: return "Eschatology"
        }
    }
}

// MARK: - ChurchDNAService

@MainActor
final class ChurchDNAService: ObservableObject {
    static let shared = ChurchDNAService()

    @Published var scores: [String: Int] = [:]
    @Published var isLoading = false
    @Published var updatedAt: Date?

    private let db        = Firestore.firestore()
    private let functions = Functions.functions()

    func load(churchId: String) async {
        // Try Firestore cache first
        if let snap = try? await db.collection("churches").document(churchId).getDocument(),
           let d = snap.data(),
           let scores = d["dnaScores"] as? [String: Int] {
            self.scores    = scores
            if let ts = d["dnaScoresUpdatedAt"] as? Timestamp {
                self.updatedAt = ts.dateValue()
            }
            return
        }
        // Recompute via Cloud Function
        await recompute(churchId: churchId)
    }

    func recompute(churchId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await functions.httpsCallable("computeChurchDNA").call(["churchId": churchId])
            if let data = result.data as? [String: Any],
               let s = data["scores"] as? [String: Int] {
                scores    = s
                updatedAt = Date()
            }
        } catch {
            print("ChurchDNAService error: \(error)")
        }
    }
}

// MARK: - ChurchDNADetailView

struct ChurchDNADetailView: View {
    let churchId: String
    @StateObject private var service = ChurchDNAService()
    @State private var tappedAxis: DNAAxis?
    @State private var showAxisSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Theological Profile")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(.label))
                Spacer()
                if service.isLoading {
                    ProgressView().scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 20)

            // Radar chart
            if !service.scores.isEmpty {
                HexRadarChart(scores: service.scores) { axis in
                    tappedAxis = axis
                    showAxisSheet = true
                }
                .frame(height: 240)
                .padding(.horizontal, 30)

                // Updated at
                if let date = service.updatedAt {
                    Text("Last updated \(date.formatted(.dateTime.month().day().year()))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if !service.isLoading {
                Text("No theological data yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $showAxisSheet) {
            if let axis = tappedAxis {
                DNAAxisDetailSheet(churchId: churchId, axis: axis)
            }
        }
        .task { await service.load(churchId: churchId) }
    }
}

// MARK: - HexRadarChart

private struct HexRadarChart: View {
    let scores: [String: Int]
    let onAxisTap: (DNAAxis) -> Void

    private let axes = DNAAxis.allCases

    private func normalizedValue(for axis: DNAAxis) -> CGFloat {
        CGFloat(scores[axis.rawValue] ?? 0) / 100.0
    }

    var body: some View {
        Canvas { ctx, size in
            let center   = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius   = min(size.width, size.height) / 2 - 20
            let count    = axes.count
            let step     = (2 * CGFloat.pi) / CGFloat(count)
            let startAngle = -CGFloat.pi / 2

            // Draw grid rings at 25/50/75/100%
            for ring in [0.25, 0.5, 0.75, 1.0] {
                var ring_path = Path()
                for i in 0..<count {
                    let angle = startAngle + step * CGFloat(i)
                    let r     = radius * CGFloat(ring)
                    let pt    = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                    if i == 0 { ring_path.move(to: pt) } else { ring_path.addLine(to: pt) }
                }
                ring_path.closeSubpath()
                ctx.stroke(ring_path, with: .color(.primary.opacity(0.2)), lineWidth: 1)
            }

            // Draw data polygon
            var data_path = Path()
            for (i, axis) in axes.enumerated() {
                let angle = startAngle + step * CGFloat(i)
                let r     = radius * normalizedValue(for: axis)
                let pt    = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                if i == 0 { data_path.move(to: pt) } else { data_path.addLine(to: pt) }
            }
            data_path.closeSubpath()
            ctx.stroke(data_path, with: .color(.primary), lineWidth: 2)
        }
        // Axis labels as interactive buttons via overlay
        .overlay {
            GeometryReader { geo in
                let size   = geo.size
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 4
                let step   = (2 * CGFloat.pi) / CGFloat(axes.count)
                let start  = -CGFloat.pi / 2

                ForEach(Array(axes.enumerated()), id: \.element.id) { i, axis in
                    let angle   = start + step * CGFloat(i)
                    let labelR  = radius + 14
                    let x       = center.x + labelR * cos(angle)
                    let y       = center.y + labelR * sin(angle)

                    Button {
                        onAxisTap(axis)
                    } label: {
                        Text(axis.displayName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(.secondaryLabel))
                            .fixedSize()
                    }
                    .position(x: x, y: y)
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - DNAAxisDetailSheet

private struct DNAAxisDetailSheet: View {
    let churchId: String
    let axis: DNAAxis

    @State private var quotes: [String] = []
    @State private var isLoading = true

    private let db = Firestore.firestore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(axis.displayName)
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Text("Sermon notes contributing to this score:")
                .font(.system(size: 13))
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, 20)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if quotes.isEmpty {
                Text("No notes found for this axis.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .padding(.horizontal, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(quotes, id: \.self) { quote in
                            HStack(alignment: .top, spacing: 8) {
                                Rectangle()
                                    .fill(Color(.tertiaryLabel))
                                    .frame(width: 3)
                                    .clipShape(Capsule())
                                Text(quote)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color(.label))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            Spacer()
        }
        .presentationDetents([.medium])
        .task { await loadQuotes() }
    }

    private func loadQuotes() async {
        defer { isLoading = false }
        do {
            let keyword = axis.displayName.lowercased()
            let snap = try await db.collection("notes")
                .whereField("churchId", isEqualTo: churchId)
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()

            var results: [String] = []
            for doc in snap.documents {
                let kps = (doc.data()["keyPoints"] as? [String]) ?? []
                for kp in kps {
                    if kp.lowercased().contains(keyword) {
                        results.append(kp)
                    }
                }
                if results.count >= 3 { break }
            }
            quotes = Array(results.prefix(3))
        } catch {
            print("DNAAxisDetailSheet error: \(error)")
        }
    }
}

// MARK: - ChurchDNALink (entry point for ChurchProfileView)

/// A subtle text link that opens the DNA detail view as a sheet.
struct ChurchDNALink: View {
    let churchId: String
    @State private var showDNA = false

    var body: some View {
        Button {
            showDNA = true
        } label: {
            Text("See theological profile")
                .font(.system(size: 13))
                .foregroundStyle(Color(.secondaryLabel))
                .underline()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDNA) {
            ChurchDNADetailView(churchId: churchId)
                .presentationDetents([.large])
        }
    }
}

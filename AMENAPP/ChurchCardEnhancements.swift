// ChurchCardEnhancements.swift
// AMENAPP
//
// Additive overlays and data for ChurchCard / ChurchProfileView:
//   1. LogoBrandingService — fetches logo URL from Google Places, extracts dominant brand color
//   2. ChurchBannerOverlay — brand tint at 60% opacity + 3px DNA bar at bottom
//   3. ChurchLogoOverlay — 44×44 rounded logo or initials, top-right corner
//   4. SundayVibePill — vibe phrase from Firestore
//   5. SeasonRecommendationText — "Recommended for your current season"
//   6. SundayPulseDot — live 6pt animated dot (Sundays 8:30am–2pm church local time)

import SwiftUI
import CoreImage
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - ChurchEnhancementStore
// Observable per-church data loaded from Firestore: brandColor, logoUrl, sundayVibe, dnaScores, prayerMomentum, livePulse

@MainActor
final class ChurchEnhancementStore: ObservableObject {
    static let shared = ChurchEnhancementStore()

    // churchId → enhancement data
    @Published private var data: [String: ChurchEnhancementData] = [:]

    private let db = Firestore.firestore()
    private var listeners: [String: ListenerRegistration] = [:]

    func data(for churchId: String) -> ChurchEnhancementData? {
        data[churchId]
    }

    func observe(churchId: String) {
        guard listeners[churchId] == nil else { return }
        listeners[churchId] = db.collection("churches").document(churchId)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let d = snap?.data() else { return }
                self.data[churchId] = ChurchEnhancementData(from: d)
            }
    }

    func stopObserving(churchId: String) {
        listeners[churchId]?.remove()
        listeners[churchId] = nil
    }
}

struct ChurchEnhancementData {
    var logoUrl: String?
    var brandColor: String?         // hex string e.g. "#4A90D9"
    var sundayVibe: String?
    var dnaScores: [String: Int]?   // grace_emphasis, word_centrality, etc.
    var livePulse: LivePulse?
    var prayerMomentum: PrayerMomentumData?
    var firstVisitGuide: FirstVisitGuideData?
    var seasonSpecializations: [String]?
    var pastorStyle: String?

    struct LivePulse {
        var score: Double
        var sampleSize: Int
    }

    init() {}

    init(from d: [String: Any]) {
        logoUrl       = d["logoUrl"] as? String
        brandColor    = d["brandColor"] as? String
        sundayVibe    = d["sundayVibe"] as? String
        dnaScores     = d["dnaScores"] as? [String: Int]
        pastorStyle   = d["pastorStyle"] as? String
        seasonSpecializations = d["seasonSpecializations"] as? [String]
        if let lp = d["livePulse"] as? [String: Any],
           let score = lp["score"] as? Double,
           let sample = lp["sampleSize"] as? Int {
            livePulse = LivePulse(score: score, sampleSize: sample)
        }
        if let pm = d["prayerMomentum"] as? [String: Any] {
            prayerMomentum = PrayerMomentumData(from: pm)
        }
        if let guide = d["firstVisitGuide"] as? [String: Any] {
            firstVisitGuide = FirstVisitGuideData(from: guide)
        }
    }
}

// MARK: - ChurchBannerOverlay

/// Overlay on top of existing church hero/card banner.
/// Adds: brand color tint at 60% opacity + DNA theology bar at bottom edge.
struct ChurchBannerOverlay: View {
    let churchId: String
    @StateObject private var store = ChurchEnhancementStore.shared

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Brand tint at 60% opacity
                if let hex = store.data(for: churchId)?.brandColor,
                   let color = Color(hex: hex) {
                    color.opacity(0.6)
                        .allowsHitTesting(false)
                }

                // DNA bar — 3px at very bottom
                if let scores = store.data(for: churchId)?.dnaScores, !scores.isEmpty {
                    ChurchDNABar(scores: scores)
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { store.observe(churchId: churchId) }
        .allowsHitTesting(false)
    }
}

// MARK: - ChurchLogoOverlay

/// 44×44 rounded logo in top-right corner of banner.
struct ChurchLogoOverlay: View {
    let churchId: String
    let churchName: String
    @StateObject private var store = ChurchEnhancementStore.shared

    private var initials: String {
        churchName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    var body: some View {
        Group {
            if let urlStr = store.data(for: churchId)?.logoUrl,
               let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: 44, height: 44)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .onAppear { store.observe(churchId: churchId) }
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color(.secondaryLabel))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
    }
}

// MARK: - ChurchDNABar

private struct ChurchDNABar: View {
    /// Keys: reformed, charismatic, evangelical, liturgical, contemplative
    let scores: [String: Int]

    private let axisColors: [String: Color] = [
        "reformed":      .blue,
        "charismatic":   .orange,
        "evangelical":   .green,
        "liturgical":    .purple,
        "contemplative": .teal,
        // also support dnaScores keys
        "grace_emphasis":      .blue,
        "word_centrality":     .indigo,
        "evangelism_focus":    .green,
        "holy_spirit_gifts":   .orange,
        "community_justice":   .teal,
        "eschatology_urgency": .red,
    ]

    private var total: Int { max(scores.values.reduce(0, +), 1) }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(scores.sorted(by: { $0.key < $1.key })), id: \.key) { key, val in
                    Rectangle()
                        .fill(axisColors[key] ?? .gray)
                        .frame(width: geo.size.width * CGFloat(val) / CGFloat(total))
                }
            }
        }
    }
}

// MARK: - SundayVibePill

/// Small pill tag showing the church's AI-generated Sunday vibe phrase.
struct SundayVibePill: View {
    let churchId: String
    @StateObject private var store = ChurchEnhancementStore.shared

    var body: some View {
        if let vibe = store.data(for: churchId)?.sundayVibe, !vibe.isEmpty {
            Text(vibe)
                .font(.system(size: 11))
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.secondarySystemBackground), in: Capsule())
        }
    }
}

// MARK: - SeasonRecommendationText

/// Single line of tertiary text shown only on boosted cards.
struct SeasonRecommendationText: View {
    let churchId: String
    @StateObject private var store = ChurchEnhancementStore.shared
    @AppStorage("spiritualSeason") private var spiritualSeason = ""

    var body: some View {
        let specs = store.data(for: churchId)?.seasonSpecializations ?? []
        if !spiritualSeason.isEmpty && specs.contains(spiritualSeason) {
            Text("Recommended for your current season")
                .font(.system(size: 12))
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }
}

// MARK: - SundayPulseDot

/// 6pt animated circle on top-left of banner. Only visible Sundays 8:30am–2:00pm church local time.
struct SundayPulseDot: View {
    let churchId: String
    @StateObject private var store = ChurchEnhancementStore.shared
    @State private var pulsing = false

    private var isVisible: Bool {
        let cal = Calendar.current
        let now = Date()
        guard cal.component(.weekday, from: now) == 1 else { return false } // Sunday
        let hour = cal.component(.hour, from: now)
        let min  = cal.component(.minute, from: now)
        let totalMin = hour * 60 + min
        return totalMin >= 510 && totalMin <= 840 // 8:30am = 510, 2:00pm = 840
    }

    private var dotColor: Color {
        guard let score = store.data(for: churchId)?.livePulse?.score else { return .gray }
        if score >= 7 { return .green }
        if score >= 4 { return .orange }
        return .red
    }

    var body: some View {
        if isVisible, store.data(for: churchId)?.livePulse != nil {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .scaleEffect(pulsing ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulsing)
                .onAppear {
                    store.observe(churchId: churchId)
                    pulsing = true
                }
        }
    }
}

// MARK: - PrayerMomentumBadge (for ChurchCard info row)

/// A single word ("rising", "steady", "quieter") appended to the info row.
struct PrayerMomentumBadge: View {
    let churchId: String
    @StateObject private var store = ChurchEnhancementStore.shared
    var onTap: () -> Void = {}

    var body: some View {
        if let pm = store.data(for: churchId)?.prayerMomentum,
           pm.sampleSize >= 20 {
            Button(action: onTap) {
                HStack(spacing: 4) {
                    Text("·")
                        .foregroundStyle(Color(.tertiaryLabel))
                    Text(pm.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - PrayerMomentumData

struct PrayerMomentumData {
    var label: String         // "rising", "steady", "quieter"
    var percentChange: Double
    var sampleSize: Int
    var last6MonthCounts: [Int]  // for sparkline

    init(from d: [String: Any]) {
        label         = (d["label"]         as? String) ?? "steady"
        percentChange = (d["percentChange"] as? Double) ?? 0
        sampleSize    = (d["sampleSize"]    as? Int)    ?? 0
        last6MonthCounts = (d["last6MonthCounts"] as? [Int]) ?? []
    }
}

// MARK: - PrayerMomentumSheet (tappable detail)

struct PrayerMomentumSheet: View {
    let churchId: String
    @StateObject private var store = ChurchEnhancementStore.shared

    var body: some View {
        if let pm = store.data(for: churchId)?.prayerMomentum {
            VStack(alignment: .leading, spacing: 16) {
                Text("Community faith activity")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(.label))

                Text("\(pm.sampleSize) answered prayers reported in the last 90 days")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(.secondaryLabel))

                if !pm.last6MonthCounts.isEmpty {
                    PrayerSparkline(counts: pm.last6MonthCounts)
                        .frame(height: 40)
                        .frame(maxWidth: .infinity)
                }

                Text("Based on anonymous reports from AMEN members who attend this church")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.tertiaryLabel))

                Spacer()
            }
            .padding(24)
            .presentationDetents([.fraction(0.4)])
        }
    }
}

// MARK: - PrayerSparkline

private struct PrayerSparkline: View {
    let counts: [Int]

    var body: some View {
        Canvas { ctx, size in
            guard counts.count > 1 else { return }
            let maxVal = CGFloat(counts.max() ?? 1)
            let step   = size.width / CGFloat(counts.count - 1)
            var path   = Path()
            for (i, count) in counts.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height - (CGFloat(count) / maxVal) * size.height
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else       { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .foreground, lineWidth: 2)
        }
    }
}

// MARK: - FirstVisitGuideData

struct FirstVisitGuideData {
    var parking: String?
    var arrivalTip: String?
    var whatToWear: String?
    var serviceFlow: [String]
    var conversationStarters: [String]
    var cachedAt: Date?

    init(from d: [String: Any]) {
        parking              = d["parking"]     as? String
        arrivalTip           = d["arrivalTip"]  as? String
        whatToWear           = d["whatToWear"]  as? String
        serviceFlow          = (d["serviceFlow"]          as? [String]) ?? []
        conversationStarters = (d["conversationStarters"] as? [String]) ?? []
        if let ts = d["cachedAt"] as? Timestamp { cachedAt = ts.dateValue() }
    }

    var isStale: Bool {
        guard let date = cachedAt else { return true }
        return Date().timeIntervalSince(date) > 30 * 86400 // 30 days
    }
}

// MARK: - Color(hex:) extension

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}

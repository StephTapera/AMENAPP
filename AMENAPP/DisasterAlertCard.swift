// ─────────────────────────────────────────────────────────────────────────────
// DisasterAlertCard.swift
// Embedded in Discover feed — glassmorphic urgent card with prayer/donate CTAs
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Disaster Model

struct DisasterAlert: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var location: String
    var type: String
    var cardHeadline: String
    var cardSubtitle: String
    var urgencyLevel: UrgencyLevel
    var prayerPrompt: String
    var scripture: Scripture
    var callToAction: CallToAction
    var resources: [DisasterResource]
    var communityPrompt: String
    var prayerCount: Int
    var donationCount: Int
    var active: Bool
    var createdAt: Date?

    enum UrgencyLevel: String, Codable {
        case critical, high, moderate
        var color: Color {
            switch self {
            case .critical: return Color(red: 1, green: 0.231, blue: 0.188)   // #FF3B30
            case .high:     return Color(red: 1, green: 0.584, blue: 0)       // #FF9500
            case .moderate: return Color(red: 1, green: 0.839, blue: 0.039)   // #FFD60A
            }
        }
        var label: String {
            switch self {
            case .critical: return "URGENT"
            case .high:     return "ALERT"
            case .moderate: return "UPDATE"
            }
        }
        var icon: String {
            switch self {
            case .critical: return "exclamationmark.triangle.fill"
            case .high:     return "bolt.fill"
            case .moderate: return "info.circle.fill"
            }
        }
    }

    struct Scripture: Codable {
        var reference: String
        var text: String
    }

    struct CallToAction: Codable {
        var prayLabel: String
        var donateLabel: String
        var shareLabel: String
    }

    struct DisasterResource: Codable, Identifiable {
        var id: String { org }
        var org: String
        var url: String
        var type: String
        var description: String
    }
}

// MARK: - Disaster Alert Card (Discover Feed)

struct DisasterAlertCard: View {
    let disaster: DisasterAlert
    @State private var isPraying = false
    @State private var showPrayerSheet = false
    @State private var showFullCard = false
    @State private var prayerCount: Int
    @State private var pulseRing = false
    @StateObject private var vm = DisasterCardViewModel()

    init(disaster: DisasterAlert) {
        self.disaster = disaster
        _prayerCount = State(initialValue: disaster.prayerCount)
    }

    var body: some View {
        Button { showFullCard = true } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showFullCard) {
            DisasterDetailSheet(disaster: disaster)
        }
        .sheet(isPresented: $showPrayerSheet) {
            PrayerIntentSheet(disaster: disaster)
        }
    }

    private var cardContent: some View {
        ZStack(alignment: .topLeading) {

            // Background — dark red/orange glassmorphic
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            disaster.urgencyLevel.color.opacity(0.18),
                            Color.black.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    disaster.urgencyLevel.color.opacity(0.6),
                                    disaster.urgencyLevel.color.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )

            // Pulse ring on critical
            if disaster.urgencyLevel == .critical {
                Circle()
                    .stroke(disaster.urgencyLevel.color.opacity(pulseRing ? 0.0 : 0.5), lineWidth: 2)
                    .frame(width: pulseRing ? 90 : 40, height: pulseRing ? 90 : 40)
                    .position(x: 30, y: 30)
                    .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: pulseRing)
                    .onAppear { pulseRing = true }
            }

            VStack(alignment: .leading, spacing: 14) {

                // Header row
                HStack(spacing: 8) {
                    Image(systemName: disaster.urgencyLevel.icon)
                        .font(.caption.bold())
                        .foregroundStyle(disaster.urgencyLevel.color)

                    Text(disaster.urgencyLevel.label)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(disaster.urgencyLevel.color)
                        .kerning(1.5)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(disaster.urgencyLevel.color.opacity(0.15)))

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9))
                        Text(disaster.location)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }

                // Headline
                Text(disaster.cardHeadline)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                // Subtitle
                Text(disaster.cardSubtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)

                // Scripture snippet
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(disaster.urgencyLevel.color.opacity(0.8))
                        .frame(width: 2)
                        .cornerRadius(1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\"\(disaster.scripture.text)\"")
                            .font(.system(size: 12, weight: .regular, design: .serif))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                            .italic()
                        Text("— \(disaster.scripture.reference)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(disaster.urgencyLevel.color.opacity(0.9))
                    }
                }
                .padding(.vertical, 6)

                // CTA Buttons
                HStack(spacing: 10) {
                    Button {
                        showPrayerSheet = true
                        withAnimation(.spring(response: 0.3)) {
                            isPraying = true
                            prayerCount += 1
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        vm.logPrayer(disasterId: disaster.id ?? "")
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isPraying ? "hands.sparkles.fill" : "hands.sparkles")
                                .font(.system(size: 13))
                            Text(isPraying ? "\(prayerCount) Praying" : disaster.callToAction.prayLabel)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(isPraying ? disaster.urgencyLevel.color : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(isPraying
                                      ? disaster.urgencyLevel.color.opacity(0.15)
                                      : Color.white.opacity(0.12))
                                .overlay(
                                    Capsule().strokeBorder(
                                        isPraying
                                        ? disaster.urgencyLevel.color.opacity(0.5)
                                        : Color.white.opacity(0.2),
                                        lineWidth: 1
                                    )
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    Button { showFullCard = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 13))
                            Text(disaster.callToAction.donateLabel)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(disaster.urgencyLevel.color))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
            .padding(18)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Prayer Intent Sheet

struct PrayerIntentSheet: View {
    let disaster: DisasterAlert
    @Environment(\.dismiss) var dismiss
    @State private var prayerNote = ""
    @State private var submitted = false
    private let db = Firestore.firestore()

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Image(systemName: "hands.sparkles.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(disaster.urgencyLevel.color)
                            Text("Pray for \(disaster.name)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("GUIDED PRAYER")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .kerning(1.5)

                            Text(disaster.prayerPrompt)
                                .font(.system(size: 15, weight: .regular, design: .serif))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineSpacing(4)
                                .italic()
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.white.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(disaster.urgencyLevel.color.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }

                        VStack(spacing: 6) {
                            Text("\"\(disaster.scripture.text)\"")
                                .font(.system(size: 13, weight: .regular, design: .serif))
                                .foregroundStyle(.white.opacity(0.7))
                                .italic()
                                .multilineTextAlignment(.center)
                            Text(disaster.scripture.reference)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(disaster.urgencyLevel.color)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("ADD YOUR PRAYER (OPTIONAL)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .kerning(1.5)

                            TextEditor(text: $prayerNote)
                                .frame(height: 80)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.white.opacity(0.06))
                                )
                        }

                        if submitted {
                            Label("Prayer submitted. 🙏", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                submitPrayer()
                            } label: {
                                Text("I'm Praying")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(disaster.urgencyLevel.color)
                                    )
                            }
                        }
                    }
                    .padding(24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private func submitPrayer() {
        guard let uid = FirebaseAuth.Auth.auth().currentUser?.uid,
              let disasterId = disaster.id else { return }
        withAnimation { submitted = true }

        let prayerData: [String: Any] = [
            "uid": uid,
            "note": prayerNote,
            "prayedAt": FieldValue.serverTimestamp()
        ]
        db.collection("disasters").document(disasterId)
            .collection("prayers").document(uid)
            .setData(prayerData)
        db.collection("disasters").document(disasterId)
            .updateData(["prayerCount": FieldValue.increment(Int64(1))])

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
    }
}

// MARK: - Disaster Detail Sheet

struct DisasterDetailSheet: View {
    let disaster: DisasterAlert
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                urgencyBadge
                                Spacer()
                                Text(disaster.location)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Text(disaster.cardHeadline)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(disaster.cardSubtitle)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        Divider().background(.white.opacity(0.1))

                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel("🙏 Community Prayer")
                            Text(disaster.prayerPrompt)
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(.white.opacity(0.85))
                                .italic()
                                .lineSpacing(5)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("📖 Scripture")
                            Text("\"\(disaster.scripture.text)\"")
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(.white.opacity(0.85))
                                .italic()
                            Text("— \(disaster.scripture.reference)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(disaster.urgencyLevel.color)
                        }

                        Divider().background(.white.opacity(0.1))

                        VStack(alignment: .leading, spacing: 14) {
                            sectionLabel("❤️ Ways to Help")
                            ForEach(disaster.resources) { resource in
                                DisasterResourceRow(resource: resource, accentColor: disaster.urgencyLevel.color)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("✍️ Share in the Community")
                            Text(disaster.communityPrompt)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.7))

                            Button {
                                // Post with disaster tag — future deep link
                            } label: {
                                Label("Post a Prayer or Update", systemImage: "plus.bubble")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(.white.opacity(0.1))
                                    )
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var urgencyBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: disaster.urgencyLevel.icon).font(.caption.bold())
            Text(disaster.urgencyLevel.label)
                .font(.system(size: 10, weight: .black)).kerning(1.5)
        }
        .foregroundStyle(disaster.urgencyLevel.color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(disaster.urgencyLevel.color.opacity(0.15)))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .kerning(0.5)
    }
}

// MARK: - Resource Row

struct DisasterResourceRow: View {
    let resource: DisasterAlert.DisasterResource
    let accentColor: Color

    var icon: String {
        switch resource.type {
        case "financial":  return "dollarsign.circle.fill"
        case "volunteer":  return "person.2.fill"
        case "housing":    return "house.fill"
        default:           return "shippingbox.fill"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accentColor)
                .frame(width: 36, height: 36)
                .background(Circle().fill(accentColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text(resource.org)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(resource.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        )
        .onTapGesture {
            if let url = URL(string: resource.url) {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - Resources Tab: Active Disasters Section

struct DisasterResourcesSection: View {
    @StateObject private var vm = DisasterResourcesViewModel()

    var body: some View {
        Group {
            if !vm.disasters.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CRISIS RESPONSE")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.secondary)
                                .kerning(2)
                            Text("Active Disasters")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                        }
                        Spacer()
                        // Live pulse dot
                        Circle()
                            .fill(Color(red: 1, green: 0.231, blue: 0.188))
                            .frame(width: 8, height: 8)
                    }
                    .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(vm.disasters) { disaster in
                                CompactDisasterCard(disaster: disaster)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear { vm.loadDisasters() }
        .animation(.easeInOut(duration: 0.3), value: vm.disasters.isEmpty)
    }
}

// MARK: - Compact card for Resources horizontal scroll

struct CompactDisasterCard: View {
    let disaster: DisasterAlert
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: disaster.urgencyLevel.icon)
                        .foregroundStyle(disaster.urgencyLevel.color)
                    Text(disaster.urgencyLevel.label)
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(disaster.urgencyLevel.color)
                        .kerning(1.5)
                    Spacer()
                }
                Text(disaster.cardHeadline)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: "hands.sparkles.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("\(disaster.prayerCount) praying")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 180)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(disaster.urgencyLevel.color.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            DisasterDetailSheet(disaster: disaster)
        }
    }
}

// MARK: - View Models

@MainActor
class DisasterCardViewModel: ObservableObject {
    private let db = Firestore.firestore()

    func logPrayer(disasterId: String) {
        guard !disasterId.isEmpty,
              let uid = FirebaseAuth.Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = ["uid": uid, "prayedAt": FieldValue.serverTimestamp()]
        db.collection("disasters").document(disasterId)
            .collection("prayers").document(uid)
            .setData(data, merge: true)
        db.collection("disasters").document(disasterId)
            .updateData(["prayerCount": FieldValue.increment(Int64(1))])
    }
}

@MainActor
class DisasterResourcesViewModel: ObservableObject {
    @Published var disasters: [DisasterAlert] = []
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func loadDisasters() {
        guard listener == nil else { return }
        listener = db.collection("disasters")
            .whereField("active", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 5)
            .addSnapshotListener { [weak self] snap, _ in
                self?.disasters = snap?.documents.compactMap {
                    try? $0.data(as: DisasterAlert.self)
                } ?? []
            }
    }

    deinit { listener?.remove() }
}

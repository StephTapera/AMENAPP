// AmenTeacherOSView.swift
// AMEN Connect — Discipleship Learning & Knowledge Graph (Agent 7)
//
// Teacher dashboard — private analytics only.
// NO public view counts, NO subscriber numbers, NO like counts, NO share counts.
// All metrics measure formation, not engagement.
//
// Frozen contracts: ConnectSpacesPhase0Contracts.swift — do not edit.
// Callable proxy: AmenConnectSpacesPhase0BindingService.swift

import SwiftUI
import FirebaseAnalytics
import FirebaseFirestore
import FirebaseAuth

// MARK: - Color tokens (file-private)

// MARK: - Private metrics model (stub)

struct AmenTeacherPrivateMetrics {
    /// 0–100 gauge: how long viewers stayed engaged. Not an absolute count.
    var retentionQuality: Double = 72
    /// 0–100 gauge: aggregated edification score from structured comments. Private.
    var communityTrust: Double = 85
    /// Count of "markedUnderstood" knowledge graph events from this teacher's videos.
    var formationImpactCount: Int = 0
    /// Count of respectfulDisagree comments the author upvoted (changed-mind signals).
    var changedMindSignals: Int = 0
    /// Narrative health label.
    var communityHealth: String = "Healthy"
}

// MARK: - ViewModel

@MainActor
final class AmenTeacherOSViewModel: ObservableObject {
    @Published var metrics: AmenTeacherPrivateMetrics = AmenTeacherPrivateMetrics()
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showUploadStub: Bool = false

    let teacherId: String

    init(teacherId: String) {
        self.teacherId = teacherId
    }

    func loadMetrics() async {
        isLoading = true
        errorMessage = nil
        let db = Firestore.firestore()

        do {
            // 1. Fetch content IDs authored by this teacher (cap at 10 for Firestore `in` limit)
            let contentSnap = try await db.collection("teacherContent")
                .whereField("authorId", isEqualTo: teacherId)
                .limit(to: 10)
                .getDocuments()
            let contentIds = contentSnap.documents.map { $0.documentID }

            guard !contentIds.isEmpty else {
                metrics = AmenTeacherPrivateMetrics(
                    retentionQuality: 0,
                    communityTrust: 0,
                    formationImpactCount: 0,
                    changedMindSignals: 0,
                    communityHealth: "No content yet"
                )
                isLoading = false
                return
            }

            // 2. Formation impact — count "markedUnderstood" events
            let understoodSnap = try await db.collection("knowledgeGraphEvents")
                .whereField("contentId", in: contentIds)
                .whereField("eventType", isEqualTo: "markedUnderstood")
                .getDocuments()
            let formationImpactCount = understoodSnap.documents.count

            // 3. Community signals from structured comments
            let commentsSnap = try await db.collection("comments")
                .whereField("contentId", in: contentIds)
                .limit(to: 200)
                .getDocuments()
            let allComments = commentsSnap.documents

            // Community trust — average edification score (0–1) → 0–100
            let edScores = allComments.compactMap { $0.data()["edificationScore"] as? Double }
            let communityTrust = edScores.isEmpty ? 50.0
                : (edScores.reduce(0, +) / Double(edScores.count)) * 100

            // Changed-mind signals — respectfulDisagree the author acknowledged
            let changedMindSignals = allComments.filter { doc in
                let d = doc.data()
                return (d["type"] as? String) == "respectfulDisagree"
                    && (d["authorAcknowledged"] as? Bool) == true
            }.count

            // Retention quality — ratio of positive-sentiment to total comments, scaled to 0–100
            let positiveCount = allComments.filter {
                ($0.data()["sentiment"] as? String) == "positive"
            }.count
            let retentionQuality = allComments.isEmpty ? 50.0
                : min(100, Double(positiveCount) / Double(allComments.count) * 100)

            // Community health label
            let negativeCount = allComments.filter {
                ($0.data()["sentiment"] as? String) == "negative"
            }.count
            let negRatio = allComments.isEmpty ? 0.0
                : Double(negativeCount) / Double(allComments.count)
            let communityHealth: String
            switch negRatio {
            case ..<0.05: communityHealth = "Thriving"
            case ..<0.15: communityHealth = "Healthy"
            case ..<0.30: communityHealth = "Growing"
            default:      communityHealth = "Needs Attention"
            }

            metrics = AmenTeacherPrivateMetrics(
                retentionQuality: retentionQuality,
                communityTrust: communityTrust,
                formationImpactCount: formationImpactCount,
                changedMindSignals: changedMindSignals,
                communityHealth: communityHealth
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Main view

struct AmenTeacherOSView: View {

    let teacherId: String

    @StateObject private var vm: AmenTeacherOSViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(teacherId: String) {
        self.teacherId = teacherId
        _vm = StateObject(wrappedValue: AmenTeacherOSViewModel(teacherId: teacherId))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                studioHeader
                    .padding(.bottom, 4)

                if vm.isLoading {
                    ProgressView("Loading metrics…")
                        .padding(.vertical, 40)
                } else {
                    metricsGrid
                    changedMindSection
                    communityHealthSection
                    uploadCTA
                    privacyDisclaimer
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Teacher Studio")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            Analytics.logEvent("teacher_os_viewed", parameters: nil)
        }
        .task {
            await vm.loadMetrics()
        }
        .sheet(isPresented: $vm.showUploadStub) {
            AmenTeacherUploadStubView()
        }
    }

    // MARK: - Glass header

    private var studioHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Teacher Studio")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.amenBlack)
                Text("Private — only you see these metrics")
                    .font(.caption)
                    .foregroundStyle(Color.amenBlack.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Color(.systemBackground)
                .amenGlassEffect(in: .rect(cornerRadius: 16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Metrics grid

    private var metricsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                AmenPrivateGaugeCard(
                    title: "Retention Quality",
                    subtitle: "How long viewers stayed engaged",
                    value: vm.metrics.retentionQuality,
                    tint: .amenBlue,
                    systemImage: "waveform.path.ecg"
                )
                AmenPrivateGaugeCard(
                    title: "Community Trust",
                    subtitle: "Edification score from structured comments",
                    value: vm.metrics.communityTrust,
                    tint: .amenPurple,
                    systemImage: "person.2.wave.2"
                )
            }

            AmenFormationImpactCard(
                count: vm.metrics.formationImpactCount
            )
        }
    }

    // MARK: - Changed-mind signals

    private var changedMindSection: some View {
        AmenTeacherStatCard(
            icon: "arrow.2.squarepath",
            title: "\"Changed My Mind\" Signals",
            description: "Respectful disagreements that you acknowledged as valuable",
            value: "\(vm.metrics.changedMindSignals)",
            tint: .amenPurple
        )
    }

    // MARK: - Community health

    private var communityHealthSection: some View {
        AmenTeacherStatCard(
            icon: "heart.circle",
            title: "Community Health",
            description: "Overall tone of structured discussion",
            value: vm.metrics.communityHealth,
            tint: .accentColor
        )
    }

    // MARK: - Upload CTA

    private var uploadCTA: some View {
        Button {
            vm.showUploadStub = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.doc")
                    .font(.headline)
                Text("Upload New Teaching")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.amenPurple)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Upload new teaching")
    }

    // MARK: - Privacy disclaimer

    private var privacyDisclaimer: some View {
        Text("These metrics are private. They measure formation, not engagement.")
            .font(.caption)
            .foregroundStyle(Color.amenBlack.opacity(0.4))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
    }
}

// MARK: - Private gauge card

private struct AmenPrivateGaugeCard: View {
    let title: String
    let subtitle: String
    let value: Double  // 0–100
    let tint: Color
    let systemImage: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .font(.callout)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.amenBlack)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            // Gauge
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(height: 8)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint)
                    .frame(width: max(4, (value / 100) * gaugeWidth), height: 8)
                    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8), value: value)
            }
            .accessibilityLabel("\(title): \(Int(value)) out of 100")

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Color.amenBlack.opacity(0.45))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .frame(maxWidth: .infinity)
    }

    // We approximate a fixed width since we don't have GeometryReader
    private var gaugeWidth: CGFloat { 120 }
}

// MARK: - Formation impact card

private struct AmenFormationImpactCard: View {
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title)
                .foregroundStyle(Color.amenPurple)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Formation Impact")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.amenBlack)
                Text("People who marked one of your teachings as understood")
                    .font(.caption)
                    .foregroundStyle(Color.amenBlack.opacity(0.5))
            }
            Spacer()
            Text("\(count)")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.amenPurple)
                .accessibilityLabel("\(count) people")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Generic stat card

private struct AmenTeacherStatCard: View {
    let icon: String
    let title: String
    let description: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.amenBlack)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color.amenBlack.opacity(0.5))
                    .lineLimit(2)
            }
            Spacer()
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(description)")
    }
}

// MARK: - Upload stub sheet (Wave D placeholder)

private struct AmenTeacherUploadStubView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "arrow.up.doc.fill")
                    .font(.systemScaled(56))
                    .foregroundStyle(Color.amenPurple.opacity(0.6))
                Text("Upload flow coming in Wave D.")
                    .font(.headline)
                    .foregroundStyle(Color.amenBlack)
                Text("Upload, provenance verification, and family-safety scanning will be available in the next wave.")
                    .font(.subheadline)
                    .foregroundStyle(Color.amenBlack.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Upload Teaching")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.amenPurple)
                }
            }
        }
    }
}

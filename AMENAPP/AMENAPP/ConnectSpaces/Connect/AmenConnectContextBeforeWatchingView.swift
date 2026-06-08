// AmenConnectContextBeforeWatchingView.swift
// AMEN Connect
//
// Context-before-watching card shown before or during playback.
// Aegis rules enforced:
//   - syntheticMediaLabelsNonRemovable: AI disclosure section is permanent, no dismiss path
//   - noScriptureWithoutProvenance: scripture ref count only shown (never raw unverified refs)

import SwiftUI
import FirebaseAnalytics
import FirebaseFirestore

// MARK: - ViewModel

@MainActor
final class AmenConnectContextViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var additionalContext: [String: Any] = [:]
    @Published var showClaims = false

    private let proxy = AmenConnectSpacesCallableProxy.shared

    func loadContext(videoId: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let ctx = try await proxy.fetchConnectVideoContext(videoId: videoId)
            additionalContext = ctx
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - View

struct AmenConnectContextBeforeWatchingView: View {
    let video: AmenConnectSpacesConnectVideo
    var onDismiss: (() -> Void)?

    @StateObject private var viewModel = AmenConnectContextViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Provenance summary string (non-removable disclosure)
    private var aiDisclosureText: String {
        let p = video.provenance
        if p.aiGenerated { return "AI-generated content" }
        if p.synthFace   { return "Synthetic face detected — deepfake risk" }
        if p.synthVoice  { return "Synthetic voice used" }
        if p.humanRecorded && p.aiEdited { return "Human-recorded, AI-edited" }
        if p.humanRecorded { return "Human-recorded original" }
        return "Provenance unknown"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Glass card — amenPurple tint
                VStack(alignment: .leading, spacing: 20) {

                    // MARK: Teacher identity
                    sectionBlock(label: "TEACHER") {
                        Text("@\(video.teacherId)")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.90))
                    }

                    // MARK: Sponsored badge (only shown when true)
                    if video.sponsored {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.systemScaled(10))
                            Text("Sponsored")
                                .font(.systemScaled(11, weight: .bold))
                        }
                        .foregroundStyle(Color(hex: "D9A441"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(Color(hex: "D9A441").opacity(0.18))
                                .overlay { Capsule().strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 1) }
                        }
                        .accessibilityLabel("Sponsored content")
                    }

                    // MARK: AI Disclosure — NON-REMOVABLE (syntheticMediaLabelsNonRemovable)
                    sectionBlock(label: "AI DISCLOSURE") {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform.badge.magnifyingglass")
                                .font(.systemScaled(13))
                                .foregroundStyle(Color(hex: "6E4BB5"))
                            Text(aiDisclosureText)
                                .font(.systemScaled(13, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "070607").opacity(0.60))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("AI Disclosure: \(aiDisclosureText)")

                    // MARK: Summary stub
                    sectionBlock(label: "SUMMARY") {
                        Text("This message explores the foundational themes of the passage and their relevance to everyday faith. The teaching draws from careful exegesis of the original text.")
                            .font(.systemScaled(13))
                            .foregroundStyle(Color.white.opacity(0.80))
                            .lineSpacing(4)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "070607").opacity(0.60))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    // MARK: Key claims
                    sectionBlock(label: "KEY CLAIMS") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.80)) {
                                    viewModel.showClaims.toggle()
                                }
                            } label: {
                                HStack {
                                    Text("\(video.claims.count) claim\(video.claims.count == 1 ? "" : "s")")
                                        .font(.systemScaled(13, weight: .semibold))
                                        .foregroundStyle(Color.white.opacity(0.85))
                                    Spacer()
                                    Image(systemName: viewModel.showClaims ? "chevron.up" : "chevron.down")
                                        .font(.systemScaled(11, weight: .semibold))
                                        .foregroundStyle(Color.white.opacity(0.50))
                                    Text("Review claims")
                                        .font(.systemScaled(11, weight: .medium))
                                        .foregroundStyle(Color(hex: "245B8F"))
                                }
                            }
                            .accessibilityLabel("\(video.claims.count) teaching claims. Tap to \(viewModel.showClaims ? "collapse" : "expand").")

                            if viewModel.showClaims {
                                ForEach(video.claims) { claim in
                                    claimRow(claim)
                                }
                            }
                        }
                    }

                    // MARK: Scripture references (noScriptureWithoutProvenance — count only, never raw unverified)
                    sectionBlock(label: "VERIFIED SCRIPTURE REFERENCES") {
                        HStack(spacing: 6) {
                            Image(systemName: "book.closed.fill")
                                .font(.systemScaled(12))
                                .foregroundStyle(Color(hex: "D9A441"))
                            Text("\(video.scriptureRefs.count) verified reference\(video.scriptureRefs.count == 1 ? "" : "s")")
                                .font(.systemScaled(13, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.80))
                        }
                    }
                    .accessibilityLabel("\(video.scriptureRefs.count) verified scripture references")

                    // MARK: Estimated time (always shown)
                    sectionBlock(label: "ESTIMATED TIME") {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.systemScaled(12))
                                .foregroundStyle(Color.white.opacity(0.50))
                            Text("42 min")
                                .font(.systemScaled(13, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.80))
                        }
                    }

                    // MARK: Loading indicator for additional context
                    if viewModel.isLoading {
                        HStack {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color(hex: "6E4BB5"))
                            Text("Loading additional context…")
                                .font(.systemScaled(12))
                                .foregroundStyle(Color.white.opacity(0.50))
                        }
                    }

                    if let err = viewModel.errorMessage {
                        Text("Could not load context: \(err)")
                            .font(.systemScaled(11))
                            .foregroundStyle(Color.red.opacity(0.80))
                    }
                }
                .padding(20)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(hex: "6E4BB5").opacity(0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color(hex: "6E4BB5").opacity(0.35), lineWidth: 1)
                        }
                }

                // MARK: CTA
                Button {
                    onDismiss?()
                } label: {
                    Text("Watch with intention")
                        .font(.systemScaled(15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(hex: "6E4BB5"))
                        }
                }
                .padding(.top, 16)
                .accessibilityLabel("Watch with intention")
            }
            .padding(20)
        }
        .background(Color(hex: "070607"))
        .task {
            await viewModel.loadContext(videoId: video.id)
        }
        .onAppear {
            Analytics.logEvent("connect_context_before_watching_viewed", parameters: nil)
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func sectionBlock<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.systemScaled(10, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(Color.white.opacity(0.35))
            content()
        }
    }

    @ViewBuilder
    private func claimRow(_ claim: AmenConnectSpacesTeachingClaim) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(claim.text)
                .font(.systemScaled(12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))

            if !claim.opposingFaithfulViews.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Opposing faithful views")
                        .font(.systemScaled(10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.40))
                    ForEach(claim.opposingFaithfulViews, id: \.self) { view in
                        HStack(alignment: .top, spacing: 5) {
                            Text("•")
                                .foregroundStyle(Color(hex: "D9A441"))
                            Text(view)
                                .font(.systemScaled(11))
                                .foregroundStyle(Color.white.opacity(0.65))
                        }
                    }
                }
                .padding(8)
                .background(Color(hex: "070607").opacity(0.50))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Hex color helper (private, file-scoped)

// MARK: - Preview

#if DEBUG
#Preview {
    AmenConnectContextBeforeWatchingView(
        video: AmenConnectSpacesConnectVideo(
            id: "preview-video-1",
            provenance: AmenConnectSpacesVideoProvenance(
                humanRecorded: true, aiEdited: true, aiGenerated: false,
                synthVoice: false, synthFace: false, deepfakeRisk: 0.2, verifiedOriginal: false),
            teacherId: "pastor_james",
            transcriptRef: "transcripts/preview-video-1",
            claims: [
                AmenConnectSpacesTeachingClaim(
                    id: "c1",
                    text: "Faith without works is dead.",
                    timestampSeconds: 120,
                    sourceTranscriptRange: "00:02:00–00:03:15",
                    opposingFaithfulViews: ["Salvation is by grace alone, not by works (Ephesians 2:8-9)"]),
                AmenConnectSpacesTeachingClaim(
                    id: "c2",
                    text: "Prayer changes circumstances.",
                    timestampSeconds: 600,
                    sourceTranscriptRange: "00:10:00–00:11:00",
                    opposingFaithfulViews: [])
            ],
            scriptureRefs: [
                AmenConnectSpacesScriptureRefProvenance(
                    id: "s1", reference: "James 2:17", translation: "ESV",
                    sourceLayer: .canonicalReference, verifiedAt: Date(), confidence: 0.97)
            ],
            sponsored: true,
            createdAt: Date(),
            updatedAt: Date()),
        onDismiss: {}
    )
}
#endif

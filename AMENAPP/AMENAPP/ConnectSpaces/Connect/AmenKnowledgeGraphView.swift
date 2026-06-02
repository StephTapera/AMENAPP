// AmenKnowledgeGraphView.swift
// AMEN Connect — Discipleship Learning & Knowledge Graph (Agent 7)
//
// Per-user formation journey view. Matte content throughout.
// Glass header only. No view counts, no algorithmic recommendations.
//
// Frozen contracts: ConnectSpacesPhase0Contracts.swift — do not edit.
// Callable proxy: AmenConnectSpacesPhase0BindingService.swift

import SwiftUI
import FirebaseAuth

// MARK: - ViewModel

@MainActor
final class AmenKnowledgeGraphViewModel: ObservableObject {
    @Published var graph: AmenConnectSpacesKnowledgeGraph
    @Published var markingUnderstoodId: String?
    @Published var errorMessage: String?

    init(graph: AmenConnectSpacesKnowledgeGraph) {
        self.graph = graph
    }

    func markUnderstood(videoId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "You must be signed in."
            return
        }
        markingUnderstoodId = videoId
        do {
            _ = try await AmenConnectSpacesCallableProxy.shared.recordKnowledgeGraphEvent(
                userId: userId,
                event: "markedUnderstood",
                itemRef: videoId
            )
            // Optimistically update local graph
            if !graph.understood.contains(videoId) {
                graph.understood.append(videoId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        markingUnderstoodId = nil
    }
}

// MARK: - Section model

private struct AmenKnowledgeGraphSection: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let videoIds: [String]
    let showMarkUnderstood: Bool
}

// MARK: - Main view

struct AmenKnowledgeGraphView: View {

    let graph: AmenConnectSpacesKnowledgeGraph

    @StateObject private var vm: AmenKnowledgeGraphViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(graph: AmenConnectSpacesKnowledgeGraph) {
        self.graph = graph
        _vm = StateObject(wrappedValue: AmenKnowledgeGraphViewModel(graph: graph))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                graphHeader
                    .padding(.bottom, 16)

                if let error = vm.errorMessage {
                    errorBanner(error)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                ForEach(sections) { section in
                    AmenKnowledgeGraphSectionView(
                        section: section,
                        markingUnderstoodId: vm.markingUnderstoodId,
                        onMarkUnderstood: { videoId in
                            Task { await vm.markUnderstood(videoId: videoId) }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }

                formationOnlyFooter
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Formation Journey")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Glass header

    private var graphHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(Color.amenPurple)
            VStack(alignment: .leading, spacing: 2) {
                Text("My Formation Journey")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.amenBlack)
                Text("Private — visible only to you")
                    .font(.caption)
                    .foregroundStyle(Color.amenBlack.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Color(.systemBackground)
                .glassEffect(in: .rect(cornerRadius: 0))
        )
        .overlay(
            Rectangle()
                .fill(Color.amenPurple.opacity(0.12))
                .frame(height: 2),
            alignment: .bottom
        )
    }

    // MARK: - Sections

    private var sections: [AmenKnowledgeGraphSection] {
        [
            AmenKnowledgeGraphSection(
                id: "studied",
                title: "I've Studied",
                systemImage: "book.closed",
                tint: .amenBlue,
                videoIds: vm.graph.studied,
                showMarkUnderstood: true
            ),
            AmenKnowledgeGraphSection(
                id: "understood",
                title: "I Understand",
                systemImage: "checkmark.seal",
                tint: .amenPurple,
                videoIds: vm.graph.understood,
                showMarkUnderstood: false
            ),
            AmenKnowledgeGraphSection(
                id: "wrestling",
                title: "I'm Wrestling With",
                systemImage: "figure.wrestling",
                tint: .amenGold,
                videoIds: vm.graph.wrestlingWith,
                showMarkUnderstood: false
            ),
            AmenKnowledgeGraphSection(
                id: "saved",
                title: "Saved for Later",
                systemImage: "bookmark.fill",
                tint: .amenBlue,
                videoIds: vm.graph.saved,
                showMarkUnderstood: false
            ),
            AmenKnowledgeGraphSection(
                id: "nextUp",
                title: "Up Next for Me",
                systemImage: "arrow.right.circle.fill",
                tint: .amenPurple,
                videoIds: vm.graph.nextUp,
                showMarkUnderstood: false
            )
        ]
    }

    // MARK: - Footer

    private var formationOnlyFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Formation-intent only", systemImage: "lock.shield")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.amenBlue.opacity(0.7))
            Text("This journey is built from what you've studied, not from engagement patterns or algorithmic recommendations.")
                .font(.caption)
                .foregroundStyle(Color.amenBlack.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.amenBlue.opacity(0.06))
        )
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.amenBlack)
            Spacer()
            Button {
                vm.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Color.amenBlack.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
    }
}

// MARK: - Section view

private struct AmenKnowledgeGraphSectionView: View {

    let section: AmenKnowledgeGraphSection
    let markingUnderstoodId: String?
    let onMarkUnderstood: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader
            if section.videoIds.isEmpty {
                emptyState
            } else {
                ForEach(section.videoIds, id: \.self) { videoId in
                    videoRow(videoId)
                }
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: section.systemImage)
                .foregroundStyle(section.tint)
                .frame(width: 20)
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.amenBlack)
            Spacer()
            Text("\(section.videoIds.count)")
                .font(.caption)
                .foregroundStyle(Color.amenBlack.opacity(0.4))
        }
    }

    private func videoRow(_ videoId: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(section.tint.opacity(0.18))
                .frame(width: 6)
                .frame(minHeight: 36)

            VStack(alignment: .leading, spacing: 2) {
                // Production: resolve videoId → title via a lookup service
                Text(videoId)
                    .font(.subheadline)
                    .foregroundStyle(Color.amenBlack)
                    .lineLimit(2)
                Text("ID: \(videoId)")
                    .font(.caption2)
                    .foregroundStyle(Color.amenBlack.opacity(0.35))
            }

            Spacer()

            if section.showMarkUnderstood {
                markUnderstoodButton(videoId)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func markUnderstoodButton(_ videoId: String) -> some View {
        let isMarking = markingUnderstoodId == videoId
        return Button {
            onMarkUnderstood(videoId)
        } label: {
            HStack(spacing: 4) {
                if isMarking {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                }
                Text(isMarking ? "Saving…" : "Understood")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(Color.amenPurple)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .strokeBorder(Color.amenPurple.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isMarking)
        .accessibilityLabel("Mark \(videoId) as understood")
    }

    private var emptyState: some View {
        Text("Nothing here yet — this section fills as you study.")
            .font(.caption)
            .foregroundStyle(Color.amenBlack.opacity(0.4))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
    }
}

// MARK: - Color extension (same tokens, scoped to this file)

private extension Color {
    static let amenGold   = Color(hex: "#D9A441")
    static let amenPurple = Color(hex: "#6E4BB5")
    static let amenBlue   = Color(hex: "#245B8F")
    static let amenBlack  = Color(hex: "#070607")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// AmenContextBeforeReplyPanel.swift
// AMEN Spaces — Agent 4: Spaces Intelligence
//
// Glass drawer surfaced before the user composes a reply.
// Glass card with accent top border.
// Reduce-motion: no spring animations when reduced.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Design Tokens

// MARK: - Context ViewModel

@MainActor
final class AmenContextBeforeReplyViewModel: ObservableObject {
    @Published var threadItems: [AmenConnectSpacesDerivedItem] = []
    @Published var openDecisionCount: Int = 0
    @Published var relatedOwner: String?
    @Published var riskItems: [AmenConnectSpacesDerivedItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()

    func load(spaceId: String, sourceMsgId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let snapshot = try await db
                .collection(AmenConnectSpacesFirestoreBinding.spacesCollection)
                .document(spaceId)
                .collection(AmenConnectSpacesFirestoreBinding.itemsSubcollection)
                .getDocuments()

            let allItems = snapshot.documents.compactMap { doc -> AmenConnectSpacesDerivedItem? in
                try? AmenConnectSpacesFirestoreBinding.bindDerivedItem(doc)
            }

            // Last 3 items in this thread
            threadItems = allItems
                .filter { $0.sourceMsgId == sourceMsgId }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(3)
                .map { $0 }

            // Open decisions in the space
            openDecisionCount = allItems.filter {
                $0.kind == .decision && $0.status == .open
            }.count

            // Related owner from thread items
            relatedOwner = threadItems.compactMap { $0.owner }.first

            // Risk items
            riskItems = allItems.filter { $0.kind == .risk }

        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Section Row

private struct ContextSectionRow: View {
    let label: String
    let content: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .kerning(1.1)
                .foregroundStyle(Color.white.opacity(0.38))

            Text(content)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Matte surface for context rows
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "#161318"))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(tint.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

// MARK: - Derived Item Row

private struct DerivedItemRow: View {
    let item: AmenConnectSpacesDerivedItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kindIcon(item.kind))
                .font(.system(size: 11))
                .foregroundStyle(kindColor(item.kind))
                .frame(width: 20)

            Text(item.title)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.80))
                .lineLimit(2)

            Spacer()

            StatusBadge(status: item.status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func kindIcon(_ kind: AmenConnectSpacesDerivedItemKind) -> String {
        switch kind {
        case .decision:    return "arrow.triangle.branch"
        case .task:        return "checkmark.square"
        case .risk:        return "exclamationmark.triangle"
        case .prayer:      return "hands.sparkles"
        case .careFollowUp: return "heart.circle"
        case .serveSlot:   return "person.badge.clock"
        }
    }

    private func kindColor(_ kind: AmenConnectSpacesDerivedItemKind) -> Color {
        switch kind {
        case .decision:    return .amenBlue
        case .task:        return .amenBlue
        case .risk:        return .accentColor
        case .prayer:      return .accentColor
        case .careFollowUp: return Color(hex: "#5DD178")
        case .serveSlot:   return .amenPurple
        }
    }
}

private struct StatusBadge: View {
    let status: AmenConnectSpacesItemStatus

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(tint.opacity(0.14))
                    .overlay(Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 1))
            )
            .foregroundStyle(tint)
    }

    private var label: String {
        switch status {
        case .open:       return "Open"
        case .inProgress: return "In Progress"
        case .waiting:    return "Waiting"
        case .done:       return "Done"
        case .archived:   return "Archived"
        }
    }

    private var tint: Color {
        switch status {
        case .open:       return .accentColor
        case .inProgress: return .amenBlue
        case .waiting:    return .amenPurple
        case .done:       return Color(hex: "#5DD178")
        case .archived:   return Color.white.opacity(0.30)
        }
    }
}

// MARK: - AmenContextBeforeReplyPanel

struct AmenContextBeforeReplyPanel: View {
    let spaceId: String
    let message: AmenConnectSpacesMessage

    var onStartReply: () -> Void = {}
    var onDismiss: () -> Void = {}

    @StateObject private var viewModel = AmenContextBeforeReplyViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.white.opacity(0.20))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .accessibilityHidden(true)

            // Glass card with accent top border
            VStack(spacing: 0) {
                // Accent top border line
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)

                VStack(spacing: 16) {
                    // Header
                    HStack {
                        Text("Before You Reply")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.94))
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.50))
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                        }
                        .accessibilityLabel("Dismiss context panel")
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .tint(Color.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        sectionContent
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor.opacity(0.80))
                            .padding(.horizontal, 4)
                    }

                    // CTA
                    Button(action: onStartReply) {
                        Text("Start Reply")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.amenPurple)
                            )
                    }
                    .accessibilityLabel("Start composing your reply")
                }
                .padding(16)
            }
            .background(
                // Glass card — chrome surface
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .task {
            await viewModel.load(spaceId: spaceId, sourceMsgId: message.id)
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 80 { onDismiss() }
                }
        )
        .animation(reduceMotion ? .none : .spring(response: 0.38, dampingFraction: 0.78), value: viewModel.isLoading)
    }

    @ViewBuilder
    private var sectionContent: some View {
        VStack(spacing: 12) {
            // Section 1: Thread items
            sectionHeader("What's happened in this thread")
            if viewModel.threadItems.isEmpty {
                emptyState("No prior thread items")
            } else {
                ForEach(viewModel.threadItems) { item in
                    DerivedItemRow(item: item)
                }
            }

            Divider().opacity(0.10)

            // Section 2: Decision state
            ContextSectionRow(
                label: "Decision state",
                content: viewModel.openDecisionCount == 0
                    ? "No open decisions"
                    : "\(viewModel.openDecisionCount) open decision\(viewModel.openDecisionCount == 1 ? "" : "s")",
                tint: Color.amenBlue
            )

            // Section 3: Related owner
            ContextSectionRow(
                label: "Related owner",
                content: viewModel.relatedOwner ?? "Unassigned",
                tint: Color.accentColor
            )

            // Section 4: Prior pastoral guidance (stub)
            ContextSectionRow(
                label: "Prior pastoral guidance",
                content: "No prior notes",
                tint: Color.amenPurple
            )

            // Section 5: Risk items
            sectionHeader("Risk")
            if viewModel.riskItems.isEmpty {
                emptyState("No risks flagged")
            } else {
                ForEach(viewModel.riskItems) { item in
                    DerivedItemRow(item: item)
                }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .kerning(0.8)
            .foregroundStyle(Color.white.opacity(0.38))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textCase(.uppercase)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ZStack(alignment: .bottom) {
        Color(hex: "#070607").ignoresSafeArea()

        AmenContextBeforeReplyPanel(
            spaceId: "demo-space",
            message: AmenConnectSpacesMessage(
                id: "msg-preview",
                body: "I've been struggling with this decision for weeks.",
                authorId: "user-1",
                detectedIntents: [.struggling, .decision],
                convictionCheck: AmenConnectSpacesConvictionCheck(
                    enabled: true,
                    suggestedPause: false,
                    warningKinds: [],
                    checkedAt: nil
                ),
                careRouted: false,
                createdAt: Date(),
                updatedAt: Date()
            ),
            onStartReply: {},
            onDismiss: {}
        )
    }
}
#endif

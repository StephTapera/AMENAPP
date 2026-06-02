// AmenCareFollowUpCard.swift
// AMEN Connect + Spaces — Presence & Care Routing (Agent 5)
// Built 2026-06-01
//
// Aegis caps enforced: C-22 (care content never shown behind glass — matte card),
// C-27 (no AI-generated content on care cards),
// C-34 (owner info scoped; unassigned state explicit).

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Design tokens

private extension Color {
    static let amenGold   = Color(red: 0.851, green: 0.643, blue: 0.255)
    static let amenPurple = Color(red: 0.431, green: 0.294, blue: 0.710)
    static let amenBlue   = Color(red: 0.141, green: 0.357, blue: 0.561)
}

// MARK: - Card ViewModel

@MainActor
final class AmenCareFollowUpCardViewModel: ObservableObject {
    @Published var item: AmenConnectSpacesDerivedItem
    @Published var isUpdating: Bool = false
    @Published var errorMessage: String?

    private let spaceId: String

    init(item: AmenConnectSpacesDerivedItem, spaceId: String) {
        self.item = item
        self.spaceId = spaceId
    }

    func markFollowedUp() async {
        guard item.status != .done else { return }
        isUpdating = true
        errorMessage = nil
        let db = Firestore.firestore()
        do {
            // Direct Firestore write for status update — acceptable per spec (no CF required)
            try await db
                .collection(AmenConnectSpacesFirestoreBinding.spacesCollection)
                .document(spaceId)
                .collection(AmenConnectSpacesFirestoreBinding.itemsSubcollection)
                .document(item.id)
                .updateData([
                    "status": AmenConnectSpacesItemStatus.done.rawValue,
                    "updatedAt": Timestamp(date: Date())
                ])
            item.status = .done
        } catch {
            errorMessage = error.localizedDescription
        }
        isUpdating = false
    }
}

// MARK: - Card View

struct AmenCareFollowUpCard: View {
    let item: AmenConnectSpacesDerivedItem
    let spaceId: String

    @StateObject private var vm: AmenCareFollowUpCardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(item: AmenConnectSpacesDerivedItem, spaceId: String) {
        self.item = item
        self.spaceId = spaceId
        _vm = StateObject(wrappedValue: AmenCareFollowUpCardViewModel(item: item, spaceId: spaceId))
    }

    var body: some View {
        // Matte card — care content is never behind glass (C-22, C-34)
        HStack(spacing: 0) {
            // amenGold left border (3pt)
            Rectangle()
                .fill(Color.amenGold)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                // Top row: kind badge + unrouted indicator
                HStack(spacing: 8) {
                    kindBadge
                    if vm.item.status != .done {
                        // Note: careRouted is on the source message, not the derived item.
                        // Items are shown by the queue so we surface the "Needs routing" amber
                        // indicator only for open/waiting items without an owner assigned.
                        if vm.item.owner == nil && vm.item.status != .inProgress {
                            needsRoutingPill
                        }
                    }
                    Spacer()
                    statusPill(vm.item.status)
                }

                // Title (no AI-generated content — C-27)
                Text(vm.item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // Owner row
                ownerRow

                // Due date row
                dueDateRow

                // Error feedback
                if let err = vm.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Follow-up button — only for non-done items
                if vm.item.status != .done {
                    Button {
                        Task { await vm.markFollowedUp() }
                    } label: {
                        Label(
                            vm.isUpdating ? "Saving…" : "Mark as followed up",
                            systemImage: vm.isUpdating ? "hourglass" : "checkmark.circle"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.amenGold)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.amenGold.opacity(0.6), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isUpdating)
                    .opacity(vm.isUpdating ? 0.6 : 1)
                    .accessibilityLabel("Mark care item as followed up")
                }
            }
            .padding(14)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(cardAccessibilityLabel)
    }

    // MARK: - Kind badge (glass pill on chrome — not on care body)

    private var kindBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: vm.item.kind == .prayer ? "hands.sparkles" : "heart.text.clipboard")
                .font(.caption.weight(.semibold))
            Text(vm.item.kind == .prayer ? "Prayer" : "Care Follow-Up")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(vm.item.kind == .prayer ? Color.amenPurple : Color.amenGold)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(
                            vm.item.kind == .prayer
                            ? Color.amenPurple.opacity(0.12)
                            : Color.amenGold.opacity(0.12)
                        )
                }
        }
        .accessibilityLabel(vm.item.kind == .prayer ? "Prayer" : "Care Follow-Up")
    }

    // MARK: - Needs routing amber pill

    private var needsRoutingPill: some View {
        Text("Needs routing")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color(red: 0.85, green: 0.55, blue: 0.10))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color(red: 0.85, green: 0.55, blue: 0.10).opacity(0.15))
            .clipShape(Capsule(style: .continuous))
            .accessibilityLabel("Needs routing — no shepherd assigned")
    }

    // MARK: - Status pill

    private func statusPill(_ status: AmenConnectSpacesItemStatus) -> some View {
        let (label, fg, bg) = statusTokens(status)
        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule(style: .continuous))
            .accessibilityLabel("Status: \(label)")
    }

    private func statusTokens(_ status: AmenConnectSpacesItemStatus) -> (String, Color, Color) {
        switch status {
        case .open:
            return ("Open", Color.amenGold, Color.amenGold.opacity(0.15))
        case .inProgress:
            return ("In Progress", Color.amenBlue, Color.amenBlue.opacity(0.15))
        case .done:
            return ("Done", Color(red: 0.18, green: 0.65, blue: 0.36), Color(red: 0.18, green: 0.65, blue: 0.36).opacity(0.15))
        case .waiting:
            return ("Waiting", Color(.secondaryLabel), Color(.tertiarySystemBackground))
        case .archived:
            return ("Archived", Color(.secondaryLabel), Color(.tertiarySystemBackground))
        }
    }

    // MARK: - Owner row

    private var ownerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: vm.item.owner != nil ? "person.circle" : "person.crop.circle.badge.questionmark")
                .font(.caption)
                .foregroundStyle(vm.item.owner != nil ? Color.amenGold : Color(.secondaryLabel))
                .accessibilityHidden(true)
            Text(vm.item.owner ?? "Unassigned — needs a shepherd")
                .font(.subheadline)
                .foregroundStyle(vm.item.owner != nil ? .primary : Color(.secondaryLabel))
                .italic(vm.item.owner == nil)
        }
        .accessibilityLabel(vm.item.owner != nil ? "Owner: \(vm.item.owner!)" : "Unassigned — needs a shepherd")
    }

    // MARK: - Due date row

    private var dueDateRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
                .accessibilityHidden(true)
            if let due = vm.item.due {
                Text(due, format: .dateTime.month().day().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Due \(due.formatted(.dateTime.month().day().year()))")
            } else {
                Text("No due date")
                    .font(.subheadline)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .italic()
                    .accessibilityLabel("No due date set")
            }
        }
    }

    // MARK: - Accessibility

    private var cardAccessibilityLabel: String {
        var parts = [vm.item.title]
        parts.append(vm.item.kind == .prayer ? "Prayer" : "Care Follow-Up")
        parts.append("Status: \(vm.item.status.rawValue)")
        if let owner = vm.item.owner {
            parts.append("Owner: \(owner)")
        } else {
            parts.append("Unassigned — needs a shepherd")
        }
        return parts.joined(separator: ". ")
    }
}

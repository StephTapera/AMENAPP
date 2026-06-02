// AMENAPP/AMENAPP/ConnectSpaces/Spaces/AmenMinistryRoomTasksTab.swift
// AMEN Connect + Spaces — Ministry Room Task Board
// Built 2026-06-02

import SwiftUI
import FirebaseAuth

// MARK: - ViewModel

@MainActor
final class AmenMinistryRoomTasksViewModel: ObservableObject {
    @Published var items: [AmenConnectSpacesDerivedItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let spaceId: String

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    func load() async {
        guard !spaceId.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        // Stub: callable returns empty — real implementation would call
        // AmenConnectSpacesCallableProxy.shared to fetch derived items
        // filtered by kind == .task or .serveSlot from Firestore.
        let fetched: [AmenConnectSpacesDerivedItem] = []
        items = fetched
        isLoading = false
    }

    func toggleDone(item: AmenConnectSpacesDerivedItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items[idx]
        updated.status = (updated.status == .done) ? .open : .done
        items[idx] = updated
    }

    var openItems: [AmenConnectSpacesDerivedItem] {
        items.filter { $0.status != .done && $0.status != .archived }
    }

    var doneItems: [AmenConnectSpacesDerivedItem] {
        items.filter { $0.status == .done }
    }
}

// MARK: - Status Chip

private struct AmenTaskStatusChip: View {
    let status: AmenConnectSpacesItemStatus

    private var label: String {
        switch status {
        case .open:       return "Open"
        case .inProgress: return "In Progress"
        case .waiting:    return "Waiting"
        case .done:       return "Done"
        case .archived:   return "Archived"
        }
    }

    private var chipColor: Color {
        switch status {
        case .open:       return Color(hex: "245B8F")
        case .inProgress: return Color(hex: "6E4BB5")
        case .waiting:    return Color(hex: "D9A441")
        case .done:       return Color.white.opacity(0.40)
        case .archived:   return Color.white.opacity(0.25)
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(chipColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(chipColor.opacity(0.14))
                    .overlay(
                        Capsule()
                            .strokeBorder(chipColor.opacity(0.32), lineWidth: 1)
                    )
            )
            .accessibilityLabel("Status: \(label)")
    }
}

// MARK: - Task Row

private struct AmenTaskRow: View {
    let item: AmenConnectSpacesDerivedItem
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Toggle checkbox
            Button {
                let anim: Animation = reduceMotion
                    ? .easeInOut(duration: 0.01)
                    : .spring(response: 0.3, dampingFraction: 0.7)
                withAnimation(anim) {
                    onToggle()
                }
            } label: {
                Image(systemName: item.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.status == .done ? Color(hex: "D9A441") : Color.white.opacity(0.40))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.status == .done ? "Mark \(item.title) as open" : "Mark \(item.title) as done")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(item.status == .done ? Color.white.opacity(0.40) : Color.white)
                    .strikethrough(item.status == .done, color: Color.white.opacity(0.40))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if let owner = item.owner {
                        Text(owner)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.50))
                    }

                    if let due = item.due {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                                .accessibilityHidden(true)
                            Text(Self.dueDateFormatter.string(from: due))
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(Color(hex: "D9A441").opacity(0.80))
                        .accessibilityLabel("Due \(Self.dueDateFormatter.string(from: due))")
                    }
                }
            }

            Spacer(minLength: 0)

            AmenTaskStatusChip(status: item.status)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.owner.map { "Assigned to \($0)." } ?? "") \(item.due.map { "Due \(Self.dueDateFormatter.string(from: $0))." } ?? "") Status: \(item.status.rawValue).")
    }
}

// MARK: - Section Header

private struct AmenTaskSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.55))
                .textCase(.uppercase)
                .tracking(0.8)
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "D9A441"))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color(hex: "D9A441").opacity(0.14))
                )
                .accessibilityLabel("\(count) items")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) section, \(count) items")
    }
}

// MARK: - Empty State

private struct AmenTasksEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color(hex: "D9A441").opacity(0.7))
                .accessibilityHidden(true)
            Text("No tasks yet.\nTasks created in Chat appear here.")
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No tasks yet. Tasks created in Chat appear here.")
    }
}

// MARK: - Main View

struct AmenMinistryRoomTasksTab: View {
    let spaceId: String

    @StateObject private var vm: AmenMinistryRoomTasksViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(spaceId: String) {
        self.spaceId = spaceId
        _vm = StateObject(wrappedValue: AmenMinistryRoomTasksViewModel(spaceId: spaceId))
    }

    var body: some View {
        VStack(spacing: 0) {
            if vm.isLoading {
                loadingView
            } else if vm.items.isEmpty {
                AmenTasksEmptyState()
                    .background(Color(hex: "070607"))
            } else {
                taskList
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .accessibilityLabel("Error: \(error)")
            }
        }
        .background(Color(hex: "070607"))
        .task { await vm.load() }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color(hex: "D9A441"))
            Text("Loading tasks…")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "070607"))
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                // Open section
                if !vm.openItems.isEmpty {
                    Section {
                        ForEach(vm.openItems) { item in
                            AmenTaskRow(item: item) {
                                vm.toggleDone(item: item)
                            }
                        }
                    } header: {
                        AmenTaskSectionHeader(title: "Open", count: vm.openItems.count)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "070607"))
                    }
                }

                // Done section
                if !vm.doneItems.isEmpty {
                    Section {
                        ForEach(vm.doneItems) { item in
                            AmenTaskRow(item: item) {
                                vm.toggleDone(item: item)
                            }
                        }
                    } header: {
                        AmenTaskSectionHeader(title: "Done", count: vm.doneItems.count)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "070607"))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(hex: "070607"))
    }
}

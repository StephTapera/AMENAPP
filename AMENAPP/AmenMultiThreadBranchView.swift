// AmenMultiThreadBranchView.swift
// AMEN App — Multi-Thread Branch Intelligence
//
// Shows suggested and active sub-threads for a space thread.
// Server suggests branches; users create/join them.
// Resolved branches are collapsed but accessible.

import SwiftUI
import FirebaseFirestore

// MARK: - ViewModel

@MainActor
final class AmenMultiThreadBranchViewModel: ObservableObject {
    @Published private(set) var branches: [AmenThreadBranch] = []
    @Published private(set) var state: LoadState = .idle

    enum LoadState: Equatable {
        case idle, loading, loaded, empty, error(String)
    }

    private let spaceId: String
    private let parentThreadId: String
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    init(spaceId: String, parentThreadId: String) {
        self.spaceId = spaceId
        self.parentThreadId = parentThreadId
    }

    func startListening() {
        guard AMENFeatureFlags.shared.multiThreadBranchingEnabled else {
            state = .empty
            return
        }
        state = .loading
        listener = db.collection("spaces").document(spaceId)
            .collection("branches")
            .whereField("parentThreadId", isEqualTo: parentThreadId)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snap, error in
                guard let self else { return }
                if let error {
                    self.state = .error(error.localizedDescription)
                    return
                }
                let decoded = (snap?.documents ?? []).compactMap { doc -> AmenThreadBranch? in
                    try? doc.data(as: AmenThreadBranch.self)
                }
                self.branches = decoded
                self.state = decoded.isEmpty ? .empty : .loaded
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}

// MARK: - Branch List View

struct AmenMultiThreadBranchView: View {
    let spaceId: String
    let parentThreadId: String
    var onOpenBranch: ((AmenThreadBranch) -> Void)? = nil

    @StateObject private var vm: AmenMultiThreadBranchViewModel

    init(spaceId: String,
         parentThreadId: String,
         onOpenBranch: ((AmenThreadBranch) -> Void)? = nil) {
        self.spaceId = spaceId
        self.parentThreadId = parentThreadId
        self.onOpenBranch = onOpenBranch
        _vm = StateObject(wrappedValue: AmenMultiThreadBranchViewModel(
            spaceId: spaceId, parentThreadId: parentThreadId
        ))
    }

    var body: some View {
        Group {
            switch vm.state {
            case .idle, .loading:
                loadingView
            case .empty:
                EmptyView()
            case .error:
                EmptyView()
            case .loaded:
                loadedView
            }
        }
        .onAppear { vm.startListening() }
        .onDisappear { vm.stopListening() }
    }

    // MARK: - Loaded

    private var loadedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            branchHeader
            Divider()
                .overlay(Color.black.opacity(0.06))
            branchList
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5)
                )
        )
    }

    private var branchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.45))
            Text("Sub-threads")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.78))
            Spacer(minLength: 0)
            Text("\(vm.branches.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.38))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var branchList: some View {
        VStack(spacing: 0) {
            let active = vm.branches.filter { !$0.isResolved }
            let resolved = vm.branches.filter { $0.isResolved }

            ForEach(active) { branch in
                branchRow(branch)
                if branch.id != active.last?.id || !resolved.isEmpty {
                    Divider()
                        .padding(.leading, 42)
                        .overlay(Color.black.opacity(0.05))
                }
            }

            if !resolved.isEmpty {
                resolvedSection(resolved)
            }
        }
    }

    private func branchRow(_ branch: AmenThreadBranch) -> some View {
        Button {
            onOpenBranch?(branch)
        } label: {
            HStack(spacing: 10) {
                branchIcon(branch.branchType)
                VStack(alignment: .leading, spacing: 2) {
                    Text(branch.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.80))
                        .lineLimit(1)
                    if let summary = branch.summary {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.black.opacity(0.42))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                branchMeta(branch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(branch.title) sub-thread, \(branch.messageCount) messages")
    }

    private func branchIcon(_ type: AmenBranchType) -> some View {
        ZStack {
            Circle()
                .fill(branchColor(type).opacity(0.10))
                .frame(width: 28, height: 28)
            Image(systemName: type.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(branchColor(type))
        }
    }

    private func branchMeta(_ branch: AmenThreadBranch) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.black.opacity(0.28))
            Text("\(branch.messageCount)")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.black.opacity(0.38))
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.22))
        }
    }

    @ViewBuilder
    private func resolvedSection(_ branches: [AmenThreadBranch]) -> some View {
        DisclosureGroup {
            ForEach(branches) { branch in
                branchRow(branch)
                    .opacity(0.65)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.black.opacity(0.32))
                Text("\(branches.count) resolved")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.38))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .disclosureGroupStyle(InlineDisclosureGroupStyle())
    }

    private func branchColor(_ type: AmenBranchType) -> Color {
        switch type {
        case .theology:           return Color(red: 0.36, green: 0.27, blue: 0.80)
        case .counseling:         return Color(red: 0.22, green: 0.56, blue: 0.47)
        case .prayer:             return Color(red: 0.47, green: 0.33, blue: 0.71)
        case .operations:         return Color(red: 0.22, green: 0.42, blue: 0.70)
        case .youthDiscussion:    return Color(red: 0.78, green: 0.42, blue: 0.20)
        case .leadershipFollowUp: return Color(red: 0.60, green: 0.30, blue: 0.20)
        case .studyDeepDive:      return Color(red: 0.18, green: 0.45, blue: 0.62)
        case .general:            return Color(red: 0.35, green: 0.35, blue: 0.35)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.75)
            Text("Loading threads…")
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.38))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Branch Card (compact, for embedding in thread list)

struct AmenBranchChip: View {
    let branch: AmenThreadBranch
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            HStack(spacing: 5) {
                Image(systemName: branch.branchType.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.45))
                Text(branch.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.68))
                    .lineLimit(1)
                Text("·")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.28))
                Text("\(branch.messageCount)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.black.opacity(0.38))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.05))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(branch.title) branch, \(branch.messageCount) messages")
    }
}

// MARK: - Disclosure Group Style

private struct InlineDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack {
                    configuration.label
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.25))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        AmenMultiThreadBranchView(
            spaceId: "preview_space",
            parentThreadId: "preview_thread",
            onOpenBranch: { _ in }
        )

        AmenBranchChip(branch: AmenThreadBranch(
            id: "1",
            parentThreadId: "t1",
            spaceId: "s1",
            title: "Theology of Suffering",
            branchType: .theology,
            createdBy: "uid",
            createdAt: Date(),
            messageCount: 12,
            participantCount: 4,
            summary: "Discussion on Romans 8 and trials",
            isResolved: false
        ))
    }
    .padding()
    .background(Color(UIColor.systemGroupedBackground))
}

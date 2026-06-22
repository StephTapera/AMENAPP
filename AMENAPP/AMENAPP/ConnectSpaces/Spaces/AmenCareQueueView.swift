// AmenCareQueueView.swift
// AMEN Connect + Spaces — Presence & Care Routing (Agent 5)
// Built 2026-06-01
//
// Aegis caps enforced: C-22 (care signals route to humans — hard rule footer),
// C-34 (care content never behind glass), C-41 (reduce-motion adaptive).

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - ViewModel

@MainActor
final class AmenCareQueueViewModel: ObservableObject {
    @Published var items: [AmenConnectSpacesDerivedItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let spaceId: String
    private var listener: ListenerRegistration?

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    deinit {
        listener?.remove()
    }

    func startListening() {
        guard !spaceId.isEmpty else { return }
        isLoading = true
        let db = Firestore.firestore()
        listener = db
            .collection(AmenConnectSpacesFirestoreBinding.spacesCollection)
            .document(spaceId)
            .collection(AmenConnectSpacesFirestoreBinding.itemsSubcollection)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let snapshot else { return }
                let loaded = snapshot.documents.compactMap { doc -> AmenConnectSpacesDerivedItem? in
                    try? AmenConnectSpacesFirestoreBinding.bindDerivedItem(doc)
                }
                // Filter: only care-relevant kinds
                self.items = loaded.filter {
                    $0.kind == .careFollowUp || $0.kind == .prayer
                }
                .sorted { $0.createdAt > $1.createdAt }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}

// MARK: - Main View

struct AmenCareQueueView: View {
    let spaceId: String

    @StateObject private var vm: AmenCareQueueViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(spaceId: String) {
        self.spaceId = spaceId
        _vm = StateObject(wrappedValue: AmenCareQueueViewModel(spaceId: spaceId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Glass header (chrome surface only)
            glassHeader

            if vm.isLoading {
                loadingView
            } else if vm.items.isEmpty {
                emptyStateView
            } else {
                itemList
            }

            // C-22 hard rule: matte footer — always visible
            humanRoutingFooter
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { vm.startListening() }
        .onDisappear { vm.stopListening() }
    }

    // MARK: - Glass header (chrome)

    private var glassHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .foregroundStyle(Color.accentColor)
                .font(.title3.weight(.semibold))
                .accessibilityHidden(true)
            Text("Care Queue")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if !vm.items.isEmpty {
                Text("\(vm.items.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(.label))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule(style: .continuous))
                    .accessibilityLabel("\(vm.items.count) care items")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Divider().opacity(0.25) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Care Queue header")
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading care queue…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Empty state (matte)

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Text("✦")
                .font(.largeTitle)
                .foregroundStyle(Color(.label))
                .accessibilityHidden(true)
            Text("No care requests right now. The flock is at peace. ✦")
                .font(.body)
                .foregroundStyle(Color(.label))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No care requests right now. The flock is at peace.")
    }

    // MARK: - Item list (matte scrollable)

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(vm.items) { item in
                    AmenCareFollowUpCard(item: item, spaceId: spaceId)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - C-22 hard rule footer (matte, always shown)

    private var humanRoutingFooter: some View {
        Text("Care needs are always routed to human pastoral staff — never handled by AI alone.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .overlay(alignment: .top) { Divider().opacity(0.25) }
            .accessibilityLabel("Care needs are always routed to human pastoral staff — never handled by AI alone.")
    }
}

// AMENAPP/AMENAPP/ConnectSpaces/Spaces/AmenMinistryRoomHistoryTab.swift
// AMEN Connect + Spaces — Ministry Room Message History / Digest Tab
// Built 2026-06-02

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Presence Loader ViewModel

/// Loads the current user's spiritual presence from Firestore so the
/// rhythm-aware digest can respect Sabbath and fasting states.
@MainActor
final class AmenMinistryRoomPresenceLoader: ObservableObject {
    @Published var presence: AmenConnectSpacesPresence?
    @Published var isLoading: Bool = false

    private var listener: ListenerRegistration?

    func start(userId: String) {
        guard !userId.isEmpty else { return }
        isLoading = true
        let db = Firestore.firestore()
        listener = db
            .collection(AmenConnectSpacesFirestoreBinding.presenceCollection)
            .document(userId)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                self.isLoading = false
                guard let snapshot else { return }
                self.presence = try? AmenConnectSpacesFirestoreBinding.bindPresence(snapshot)
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }
}

// MARK: - Main View

struct AmenMinistryRoomHistoryTab: View {
    let spaceId: String

    @StateObject private var presenceLoader = AmenMinistryRoomPresenceLoader()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    /// Fallback presence used when Firestore has no document yet for the user.
    private var fallbackPresence: AmenConnectSpacesPresence {
        AmenConnectSpacesPresence(
            userId: currentUserId,
            spiritualState: .inTheWord,
            urgentReachable: false,
            sabbathUntil: nil,
            updatedAt: Date()
        )
    }

    private var resolvedPresence: AmenConnectSpacesPresence {
        presenceLoader.presence ?? fallbackPresence
    }

    var body: some View {
        VStack(spacing: 0) {
            // Glass chrome header
            historyHeader

            // Matte content area
            if presenceLoader.isLoading {
                loadingView
            } else {
                ScrollView {
                    AmenRhythmAwareDigestView(
                        presence: resolvedPresence,
                        spaceId: spaceId
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(Color(hex: "070607"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(hex: "070607"))
        .onAppear {
            presenceLoader.start(userId: currentUserId)
        }
        .onDisappear {
            presenceLoader.stop()
        }
    }

    // MARK: - Glass Chrome Header

    private var historyHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: "D9A441"))
                .accessibilityHidden(true)

            Text("Message History")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.25)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Message History section")
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color(hex: "D9A441"))
            Text("Loading history…")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "070607"))
    }
}

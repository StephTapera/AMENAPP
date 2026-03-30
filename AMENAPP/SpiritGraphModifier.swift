//
//  SpiritGraphModifier.swift
//  AMENAPP
//
//  Spirit Graph — AI explanation for why a post appeared in the user's feed.
//  Apply `.spiritGraph(postId:currentUserId:isFollowing:)` to any feed post view.
//  Shows a subtle "Why this reached you" chip for posts from unfollowed users.
//

import SwiftUI
import FirebaseFunctions

// MARK: - Spirit Graph Modifier

struct SpiritGraphModifier: ViewModifier {
    let postId: String
    let currentUserId: String?
    let isFollowing: Bool

    @State private var reason: String = ""
    @State private var showPrompt: Bool = false
    @State private var showAlert: Bool = false
    @State private var isLoading: Bool = false
    @State private var hasFetched: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) {
                if showPrompt {
                    spiritGraphChip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .alert("Why this reached you", isPresented: $showAlert) {
                Button("Got it") { }
            } message: {
                Text(reason)
            }
            .onAppear {
                // Only show for posts from users the current user does not follow
                guard !isFollowing, !hasFetched else { return }
                hasFetched = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                        showPrompt = true
                    }
                }
            }
    }

    private var spiritGraphChip: some View {
        Button {
            if reason.isEmpty {
                fetchSpiritGraph()
            } else {
                showAlert = true
            }
        } label: {
            HStack(spacing: 5) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.indigo)
                }
                Text(reason.isEmpty ? "Why this reached you" : "Why this reached you ·")
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.indigo.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func fetchSpiritGraph() {
        guard let uid = currentUserId, !postId.isEmpty else { return }
        isLoading = true
        Task {
            do {
                let functions = Functions.functions()
                let result = try await functions.httpsCallable("spiritGraph").call([
                    "postId": postId,
                    "currentUserId": uid,
                ])
                if let data = result.data as? [String: Any],
                   let r = data["reason"] as? String,
                   !r.isEmpty {
                    await MainActor.run {
                        reason = r
                        isLoading = false
                        showAlert = true
                    }
                } else {
                    await MainActor.run { isLoading = false }
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds a subtle Spirit Graph chip to a feed post for unfollowed authors.
    func spiritGraph(postId: String, currentUserId: String?, isFollowing: Bool) -> some View {
        modifier(SpiritGraphModifier(postId: postId, currentUserId: currentUserId, isFollowing: isFollowing))
    }
}

//
//  RepliesView.swift
//  AMENAPP
//
//  Scrollable feed view for displaying user's reply threads
//  Shows all posts the user has commented on with their replies
//

import SwiftUI

struct RepliesView: View {
    let userId: String
    
    @StateObject private var viewModel = RepliesViewModel()
    @State private var isRefreshing = false
    
    var body: some View {
        ZStack {
            // Liquid Glass background - consistent with app design
            Color(.systemBackground)
                .ignoresSafeArea()
            
            if viewModel.replyThreads.isEmpty && !viewModel.isLoading {
                // Empty state
                emptyState
            } else {
                // Reply threads list
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.replyThreads) { thread in
                            ReplyThreadRowView(thread: thread)
                                .onAppear {
                                    // Load more when reaching the last item
                                    if thread.id == viewModel.replyThreads.last?.id {
                                        Task {
                                            await viewModel.fetchReplies(for: userId)
                                        }
                                    }
                                }
                        }
                        
                        // Loading indicator at bottom
                        if viewModel.isLoading && !viewModel.replyThreads.isEmpty {
                            ProgressView()
                                .tint(.primary)
                                .padding(.vertical, 20)
                        }
                        
                        // Bottom padding
                        Spacer()
                            .frame(height: 32)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .refreshable {
                    await viewModel.refreshReplies(for: userId)
                }
            }
            
            // Initial loading state
            if viewModel.isLoading && viewModel.replyThreads.isEmpty {
                AMENLoadingIndicator()
            }
            
            // Error state
            if let error = viewModel.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.systemScaled(48))
                        .foregroundStyle(.red.opacity(0.8))
                    
                    Text(error)
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button {
                        Task {
                            await viewModel.refreshReplies(for: userId)
                        }
                    } label: {
                        Text("Try Again")
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            // Initial load
            if viewModel.replyThreads.isEmpty {
                await viewModel.fetchReplies(for: userId, isInitialLoad: true)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.systemScaled(56, weight: .light))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No Replies Yet")
                .font(AMENFont.bold(22))
                .foregroundStyle(.primary)
            
            Text("When you reply to posts, they'll appear here")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Preview

#Preview {
    RepliesView(userId: "preview-user-id")
        .preferredColorScheme(.dark)
}

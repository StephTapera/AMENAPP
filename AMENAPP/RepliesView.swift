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
            // Dark glassmorphic background
            Color.black
                .ignoresSafeArea()
            
            if viewModel.replyThreads.isEmpty && !viewModel.isLoading {
                // Empty state
                emptyState
            } else {
                // Reply threads list
                ScrollView {
                    LazyVStack(spacing: 0) {
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
                                .tint(.white)
                                .padding(.vertical, 20)
                        }
                    }
                    .padding(.top, 16)
                }
                .refreshable {
                    await viewModel.refreshReplies(for: userId)
                }
            }
            
            // Initial loading state
            if viewModel.isLoading && viewModel.replyThreads.isEmpty {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
            
            // Error state
            if let error = viewModel.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red.opacity(0.8))
                    
                    Text(error)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button {
                        Task {
                            await viewModel.refreshReplies(for: userId)
                        }
                    } label: {
                        Text("Try Again")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                            )
                    }
                }
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
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No Replies Yet")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundColor(.white)
            
            Text("When you reply to posts, they'll appear here")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    RepliesView(userId: "preview-user-id")
        .preferredColorScheme(.dark)
}

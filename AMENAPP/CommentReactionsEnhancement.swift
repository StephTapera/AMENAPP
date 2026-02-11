//
//  CommentReactionsEnhancement.swift
//  AMENAPP
//
//  Enhancement 1: Smart Comment Reactions
//

import SwiftUI
import FirebaseFirestore

// MARK: - Reaction Types

enum CommentReaction: String, CaseIterable, Codable {
    case amen = "🙏"      // Prayer/agreement
    case heart = "❤️"     // Love/support
    case fire = "🔥"      // Powerful/impactful
    case hundred = "💯"   // Truth/agreement
    case thinking = "🤔"  // Thoughtful
    case praise = "🙌"    // Celebration
    
    var displayName: String {
        switch self {
        case .amen: return "Amen"
        case .heart: return "Love"
        case .fire: return "Fire"
        case .hundred: return "Truth"
        case .thinking: return "Thinking"
        case .praise: return "Praise"
        }
    }
    
    var color: Color {
        switch self {
        case .amen: return .purple
        case .heart: return .red
        case .fire: return .orange
        case .hundred: return .blue
        case .thinking: return .gray
        case .praise: return .yellow
        }
    }
}

// MARK: - Comment Reaction Model

struct CommentReactionData: Codable {
    var userId: String
    var username: String
    var reaction: CommentReaction
    var timestamp: Date
}

// MARK: - Enhanced Comment Row with Reactions

struct EnhancedCommentRow: View {
    let comment: Comment
    var isReply: Bool = false
    let onReply: () -> Void
    let onDelete: () -> Void
    let onReact: (CommentReaction) -> Void
    
    @State private var showReactionPicker = false
    @State private var showReactionDetails = false
    @State private var reactions: [CommentReaction: Int] = [:]
    @State private var userReaction: CommentReaction?
    @State private var showOptions = false
    @State private var reactionScale: CGFloat = 1.0
    
    private var isOwnComment: Bool {
        comment.authorId == FirebaseManager.shared.currentUser?.uid
    }
    
    // Group reactions by type
    private var groupedReactions: [(reaction: CommentReaction, count: Int)] {
        reactions.sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
            .prefix(3)
            .map { $0 }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            CommentAvatar(comment: comment, isReply: isReply)
            
            VStack(alignment: .leading, spacing: 8) {
                // Author info
                CommentHeader(comment: comment, isReply: isReply)
                
                // Content
                Text(comment.content)
                    .font(.custom("OpenSans-Regular", size: isReply ? 13 : 14))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Reactions Display (if any reactions exist)
                if !reactions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(groupedReactions, id: \.reaction) { item in
                            ReactionBubble(
                                reaction: item.reaction,
                                count: item.count,
                                isUserReaction: userReaction == item.reaction
                            )
                            .onTapGesture {
                                showReactionDetails = true
                            }
                        }
                        
                        if reactions.count > 3 {
                            Text("+\(reactions.count - 3)")
                                .font(.custom("OpenSans-Regular", size: 11))
                                .foregroundStyle(.black.opacity(0.5))
                        }
                    }
                    .padding(.vertical, 6)
                }
                
                // Actions
                HStack(spacing: 16) {
                    // Reaction Picker Button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            showReactionPicker.toggle()
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: userReaction != nil ? "heart.fill" : "heart")
                                .font(.system(size: 13, weight: .medium))
                            
                            Text(userReaction?.rawValue ?? "React")
                                .font(.custom("OpenSans-Medium", size: 12))
                        }
                        .foregroundStyle(userReaction != nil ? userReaction!.color : .black.opacity(0.6))
                        .scaleEffect(reactionScale)
                    }
                    
                    // Reply button
                    if !isReply {
                        Button {
                            onReply()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 12))
                                
                                if comment.replyCount > 0 {
                                    Text("\(comment.replyCount)")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                }
                            }
                            .foregroundStyle(.black.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    // Options
                    if isOwnComment {
                        Button {
                            showOptions = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12))
                                .foregroundStyle(.black.opacity(0.6))
                        }
                        .confirmationDialog("Comment Options", isPresented: $showOptions) {
                            Button("Delete Comment", role: .destructive) {
                                onDelete()
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, isReply ? 12 : 16)
        .overlay(alignment: .bottomLeading) {
            // Reaction Picker Overlay
            if showReactionPicker {
                ReactionPicker(onSelect: { reaction in
                    selectReaction(reaction)
                }, onDismiss: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showReactionPicker = false
                    }
                })
                .offset(x: 48, y: -10)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showReactionDetails) {
            ReactionDetailsSheet(commentId: comment.id ?? "", reactions: reactions)
        }
        .task {
            await loadReactions()
        }
    }
    
    // MARK: - Actions
    
    private func selectReaction(_ reaction: CommentReaction) {
        // Animate reaction selection
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            reactionScale = 1.3
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                reactionScale = 1.0
            }
        }
        
        // Update local state immediately
        if userReaction == reaction {
            // Remove reaction
            userReaction = nil
            reactions[reaction, default: 0] -= 1
            if reactions[reaction] == 0 {
                reactions.removeValue(forKey: reaction)
            }
        } else {
            // Add new reaction (remove old one if exists)
            if let oldReaction = userReaction {
                reactions[oldReaction, default: 0] -= 1
                if reactions[oldReaction] == 0 {
                    reactions.removeValue(forKey: oldReaction)
                }
            }
            userReaction = reaction
            reactions[reaction, default: 0] += 1
        }
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Close picker
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showReactionPicker = false
        }
        
        // Save to Firebase
        onReact(reaction)
    }
    
    private func loadReactions() async {
        // Load reactions from Firestore
        // This would be implemented in your CommentService
    }
}

// MARK: - Reaction Picker

struct ReactionPicker: View {
    let onSelect: (CommentReaction) -> Void
    let onDismiss: () -> Void
    
    @State private var appearedReactions: Set<CommentReaction> = []
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(CommentReaction.allCases, id: \.self) { reaction in
                Button {
                    onSelect(reaction)
                } label: {
                    VStack(spacing: 4) {
                        Text(reaction.rawValue)
                            .font(.system(size: 28))
                            .scaleEffect(appearedReactions.contains(reaction) ? 1.0 : 0.5)
                            .opacity(appearedReactions.contains(reaction) ? 1.0 : 0.0)
                        
                        Text(reaction.displayName)
                            .font(.custom("OpenSans-Medium", size: 10))
                            .foregroundStyle(.black.opacity(0.6))
                    }
                    .frame(width: 50)
                }
                .buttonStyle(ReactionButtonStyle(color: reaction.color))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        )
        .onAppear {
            // Stagger animation
            for (index, reaction) in CommentReaction.allCases.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        appearedReactions.insert(reaction)
                    }
                }
            }
        }
    }
}

// MARK: - Reaction Button Style

struct ReactionButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.2 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

// MARK: - Reaction Bubble

struct ReactionBubble: View {
    let reaction: CommentReaction
    let count: Int
    let isUserReaction: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Text(reaction.rawValue)
                .font(.system(size: 14))
            
            if count > 1 {
                Text("\(count)")
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(isUserReaction ? reaction.color : .black.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isUserReaction ? reaction.color.opacity(0.15) : Color.black.opacity(0.05))
                .overlay(
                    Capsule()
                        .stroke(isUserReaction ? reaction.color.opacity(0.3) : Color.clear, lineWidth: 1.5)
                )
        )
    }
}

// MARK: - Reaction Details Sheet

struct ReactionDetailsSheet: View {
    let commentId: String
    let reactions: [CommentReaction: Int]
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(reactions.sorted { $0.value > $1.value }, id: \.key) { reaction, count in
                    Section {
                        // In real implementation, fetch users who reacted with this type
                        Text("\(count) people reacted with \(reaction.rawValue)")
                            .font(.custom("OpenSans-Regular", size: 14))
                    } header: {
                        HStack {
                            Text(reaction.rawValue)
                            Text(reaction.displayName)
                                .font(.custom("OpenSans-SemiBold", size: 13))
                        }
                    }
                }
            }
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Helper Views

private struct CommentAvatar: View {
    let comment: Comment
    let isReply: Bool
    
    var body: some View {
        if let imageURL = comment.authorProfileImageURL,
           let url = URL(string: imageURL) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(.black.opacity(0.1))
                    .overlay(
                        Text(comment.authorInitials)
                            .font(.custom("OpenSans-SemiBold", size: isReply ? 10 : 12))
                            .foregroundStyle(.black.opacity(0.6))
                    )
            }
            .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(.black.opacity(0.1))
                .frame(width: isReply ? 28 : 36, height: isReply ? 28 : 36)
                .overlay(
                    Text(comment.authorInitials)
                        .font(.custom("OpenSans-SemiBold", size: isReply ? 10 : 12))
                        .foregroundStyle(.black.opacity(0.6))
                )
        }
    }
}

private struct CommentHeader: View {
    let comment: Comment
    let isReply: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Text(comment.authorName)
                .font(.custom("OpenSans-SemiBold", size: isReply ? 13 : 14))
                .foregroundStyle(.black)
            
            Text(comment.authorUsername.hasPrefix("@") ? comment.authorUsername : "@\(comment.authorUsername)")
                .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                .foregroundStyle(.black.opacity(0.5))
            
            Text("•")
                .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                .foregroundStyle(.black.opacity(0.3))
            
            Text(comment.timeAgo)
                .font(.custom("OpenSans-Regular", size: isReply ? 11 : 12))
                .foregroundStyle(.black.opacity(0.5))
        }
    }
}

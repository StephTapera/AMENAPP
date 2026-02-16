//
//  SubtleCollaborationSuggestionsView.swift
//  AMENAPP
//
//  Created by Claude on 2/15/26.
//
//  Non-intrusive, subtle UI for suggesting potential collaborators to users
//

import SwiftUI
import FirebaseAuth

/// Subtle card that suggests potential collaborators based on smart matching
struct SubtleCollaborationSuggestionsView: View {
    @StateObject private var matchingService = CollaborationMatchingService.shared
    @State private var currentMatchIndex = 0
    @State private var showFullProfile = false
    @State private var isExpanded = false
    
    var body: some View {
        if !matchingService.suggestedCollaborators.isEmpty {
            VStack(spacing: 0) {
                // Collapsible header
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.badge.gearshape.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.blue.opacity(0.8))
                        
                        Text("People You Might Connect With")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                }
                
                // Expandable content
                if isExpanded {
                    collaboratorCard
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .padding(.horizontal)
            .padding(.vertical, 8)
            .task {
                // Load suggestions when view appears
                await matchingService.findPotentialCollaborators(limit: 5)
            }
        }
    }
    
    private var collaboratorCard: some View {
        let match = matchingService.suggestedCollaborators[currentMatchIndex]
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Profile image
                AsyncImage(url: URL(string: match.profileImageURL ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundStyle(.blue.opacity(0.5))
                        )
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(match.userName)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                    
                    Text(matchingService.getSubtleSuggestionMessage(for: match))
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            
            // Match reasons (subtle badges)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(match.matchReasons.prefix(3), id: \.self) { reason in
                        HStack(spacing: 4) {
                            Image(systemName: reason.icon)
                                .font(.system(size: 9, weight: .medium))
                            
                            Text(reason.rawValue)
                                .font(.custom("OpenSans-Regular", size: 10))
                        }
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                }
            }
            
            // Action buttons (subtle)
            HStack(spacing: 12) {
                Button {
                    // View profile action
                    showFullProfile = true
                } label: {
                    Text("View Profile")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.1))
                        )
                }
                
                Button {
                    // Next match
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        currentMatchIndex = (currentMatchIndex + 1) % matchingService.suggestedCollaborators.count
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemBackground))
                    )
                }
            }
            
            // Match score indicator (very subtle)
            HStack(spacing: 4) {
                Text("\(Int(match.matchScore))% match")
                    .font(.custom("OpenSans-Regular", size: 10))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(currentMatchIndex + 1) of \(matchingService.suggestedCollaborators.count)")
                    .font(.custom("OpenSans-Regular", size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showFullProfile) {
            UserProfileView(userId: match.userId)
        }
    }
}

/// Inline suggestion badge that can be placed in Top Ideas
struct InlineCollaboratorSuggestion: View {
    let match: CollaborationMatchingService.UserMatch
    @State private var showProfile = false
    
    var body: some View {
        Button {
            showProfile = true
        } label: {
            HStack(spacing: 8) {
                AsyncImage(url: URL(string: match.profileImageURL ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("💡 Collaborate with \(match.userName)")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.primary)
                    
                    if let reason = match.matchReasons.first {
                        Text(reason.rawValue)
                            .font(.custom("OpenSans-Regular", size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
            )
        }
        .sheet(isPresented: $showProfile) {
            UserProfileView(userId: match.userId)
        }
    }
}

#Preview {
    SubtleCollaborationSuggestionsView()
}

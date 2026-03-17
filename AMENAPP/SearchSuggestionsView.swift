//
//  SearchSuggestionsView.swift
//  AMENAPP
//
//  Autocomplete suggestions dropdown for search
//

import SwiftUI

// MARK: - Search Suggestions View

struct SearchSuggestionsView: View {
    let suggestions: [AlgoliaUserSuggestion]
    let onSelect: (AlgoliaUserSuggestion) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button(action: {
                    onSelect(suggestion)
                }) {
                    HStack(spacing: 12) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 40, height: 40)
                            
                            if let profileImageURL = suggestion.profileImageURL,
                               let url = URL(string: profileImageURL) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 40, height: 40)
                                            .clipShape(Circle())
                                    case .failure(_), .empty:
                                        Text(String(suggestion.displayName.prefix(1)))
                                            .font(.custom("OpenSans-Bold", size: 16))
                                            .foregroundStyle(.white)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                Text(String(suggestion.displayName.prefix(1)))
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(.white)
                            }
                        }
                        
                        // User info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.displayName)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.black)
                                .lineLimit(1)
                            
                            Text("@\(suggestion.username)")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        // Followers count (social proof)
                        if suggestion.followersCount > 0 {
                            Text("\(formatFollowerCount(suggestion.followersCount))")
                                .font(.custom("OpenSans-Regular", size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        
                        Image(systemName: "arrow.up.backward")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(90))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white)
                }
                .buttonStyle(PlainButtonStyle())
                
                if suggestion.id != suggestions.last?.id {
                    Divider()
                        .padding(.leading, 68)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
    }
    
    private func formatFollowerCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        } else {
            return "\(count)"
        }
    }
}

#Preview {
    SearchSuggestionsView(
        suggestions: [
            AlgoliaUserSuggestion(json: [
                "objectID": "1",
                "username": "johndoe",
                "displayName": "John Doe",
                "profileImageURL": "",
                "followersCount": 1234
            ])!,
            AlgoliaUserSuggestion(json: [
                "objectID": "2",
                "username": "janedoe",
                "displayName": "Jane Doe",
                "profileImageURL": "",
                "followersCount": 567
            ])!
        ],
        onSelect: { _ in }
    )
    .padding()
    .background(Color(white: 0.98))
}

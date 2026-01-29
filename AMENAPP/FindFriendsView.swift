//
//  FindFriendsView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI

struct FindFriendsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedInterest: FriendInterest = .all
    
    enum FriendInterest: String, CaseIterable {
        case all = "All"
        case bibleStudy = "Bible Study"
        case prayer = "Prayer"
        case sports = "Sports"
        case music = "Music"
        case ministry = "Ministry"
        case youngAdults = "Young Adults"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search community", text: $searchText)
                        .font(.custom("OpenSans-Regular", size: 16))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                )
                .padding(.horizontal)
                .padding(.top)
                
                // Interest filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FriendInterest.allCases, id: \.self) { interest in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedInterest = interest
                                }
                            } label: {
                                Text(interest.rawValue)
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(selectedInterest == interest ? .white : .black)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(selectedInterest == interest ? Color.black : Color.gray.opacity(0.1))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Suggested Friends
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Suggested Friends")
                                    .font(.custom("OpenSans-Bold", size: 20))
                                
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.blue)
                            }
                            .padding(.horizontal)
                            
                            ForEach(suggestedFriends) { friend in
                                FriendCard(friend: friend)
                            }
                        }
                        
                        // Nearby Believers
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Nearby Believers")
                                    .font(.custom("OpenSans-Bold", size: 20))
                                
                                Image(systemName: "location.fill")
                                    .foregroundStyle(.blue)
                            }
                            .padding(.horizontal)
                            
                            ForEach(nearbyFriends) { friend in
                                FriendCard(friend: friend)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Find community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}

struct FriendCard: View {
    let friend: Friend
    @State private var isSent = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile image
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: friend.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                
                Text(friend.initials)
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(friend.name)
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 4) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    Text(friend.church)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(friend.interests, id: \.self) { interest in
                            Text(interest)
                                .font(.custom("OpenSans-SemiBold", size: 11))
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
            }
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isSent = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isSent ? "checkmark" : "person.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                    
                    if !isSent {
                        Text("Add")
                            .font(.custom("OpenSans-Bold", size: 14))
                    }
                }
                .foregroundStyle(isSent ? .green : .white)
                .padding(.horizontal, isSent ? 12 : 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSent ? Color.green.opacity(0.1) : Color.black)
                )
            }
            .disabled(isSent)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
    }
}

struct Friend: Identifiable {
    let id = UUID()
    let name: String
    let initials: String
    let church: String
    let interests: [String]
    let gradientColors: [Color]
}

let suggestedFriends = [
    Friend(
        name: "David Johnson",
        initials: "DJ",
        church: "Grace Community Church",
        interests: ["Prayer", "Worship", "Sports"],
        gradientColors: [.blue, .purple]
    ),
    Friend(
        name: "Emily Chen",
        initials: "EC",
        church: "New Life Fellowship",
        interests: ["Bible Study", "Ministry", "Music"],
        gradientColors: [.pink, .orange]
    ),
    Friend(
        name: "Marcus Williams",
        initials: "MW",
        church: "Faith Baptist Church",
        interests: ["Young Adults", "Sports", "Prayer"],
        gradientColors: [.green, .cyan]
    )
]

let nearbyFriends = [
    Friend(
        name: "Lisa Martinez",
        initials: "LM",
        church: "Hope Community Church",
        interests: ["Worship", "Ministry", "Bible Study"],
        gradientColors: [.purple, .pink]
    ),
    Friend(
        name: "James Brown",
        initials: "JB",
        church: "Cornerstone Church",
        interests: ["Prayer", "Young Adults", "Music"],
        gradientColors: [.orange, .yellow]
    )
]

#Preview {
    FindFriendsView()
}

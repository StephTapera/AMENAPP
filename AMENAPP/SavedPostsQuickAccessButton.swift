//
//  SavedPostsQuickAccessButton.swift
//  AMENAPP
//
//  Created by Steph on 1/29/26.
//
//  Quick access button for saved posts with badge count
//

import SwiftUI

struct SavedPostsQuickAccessButton: View {
    @StateObject private var savedPostsService = RealtimeSavedPostsService.shared
    @State private var savedCount = 0
    @State private var showBadgePulse = false
    
    var body: some View {
        NavigationLink {
            SavedPostsView()
        } label: {
            ZStack(alignment: .topTrailing) {
                // Main button
                VStack(spacing: 8) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                    
                    Text("Saved")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                
                // Badge count
                if savedCount > 0 {
                    Text("\(savedCount)")
                        .font(.custom("OpenSans-Bold", size: 11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, savedCount > 99 ? 6 : 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.red)
                        )
                        .offset(x: 8, y: -8)
                        .scaleEffect(showBadgePulse ? 1.1 : 1.0)
                }
            }
        }
        .buttonStyle(.plain)
        .task {
            await loadCount()
            setupListener()
        }
    }
    
    private func loadCount() async {
        do {
            savedCount = try await savedPostsService.getSavedPostsCount()
        } catch {
            print("❌ Error loading saved count: \(error)")
        }
    }
    
    private func setupListener() {
        savedPostsService.observeSavedPosts { postIds in
            let newCount = postIds.count
            
            if newCount != savedCount {
                // Animate badge when count changes
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    savedCount = newCount
                    showBadgePulse = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        showBadgePulse = false
                    }
                }
            }
        }
    }
}

#Preview {
    SavedPostsQuickAccessButton()
        .padding()
}

// MARK: - Compact Row Version (for lists)

struct SavedPostsRow: View {
    @StateObject private var savedPostsService = RealtimeSavedPostsService.shared
    @State private var savedCount = 0
    
    var body: some View {
        NavigationLink {
            SavedPostsView()
        } label: {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)
                    .frame(width: 40, height: 40)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved Posts")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                    
                    if savedCount > 0 {
                        Text("\(savedCount) saved")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Bookmark posts to read later")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Badge
                if savedCount > 0 {
                    Text("\(savedCount)")
                        .font(.custom("OpenSans-Bold", size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.blue))
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
        }
        .task {
            await loadCount()
        }
    }
    
    private func loadCount() async {
        do {
            savedCount = try await savedPostsService.getSavedPostsCount()
        } catch {
            print("❌ Error loading saved count: \(error)")
        }
    }
}

#Preview("Row") {
    List {
        SavedPostsRow()
    }
}

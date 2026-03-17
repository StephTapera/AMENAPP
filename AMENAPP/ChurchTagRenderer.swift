//
//  ChurchTagRenderer.swift
//  AMENAPP
//
//  Renders clickable church pills in post/note content
//  Detects @church mentions and replaces with interactive pills
//

import SwiftUI
import CoreLocation

// MARK: - Church Tag Renderer

struct ChurchTaggedText: View {
    let text: String
    let churchTags: [ChurchTag]
    let userLocation: CLLocation?
    
    @State private var churches: [String: ChurchEntity] = [:]  // churchId -> Church
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main text
            Text(text)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Church pills
            if !churchTags.isEmpty && !isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(churchTags, id: \.id) { tag in
                            if let church = churches[tag.churchId] {
                                ChurchPill(
                                    church: church,
                                    userLocation: userLocation,
                                    onTap: {
                                        openChurchProfile(churchId: church.id)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadChurches()
        }
    }
    
    private func loadChurches() async {
        guard !churchTags.isEmpty else {
            isLoading = false
            return
        }
        
        // Load all tagged churches
        for tag in churchTags {
            if let church = try? await ChurchDataService.shared.getChurch(id: tag.churchId) {
                await MainActor.run {
                    churches[tag.churchId] = church
                }
            }
        }
        
        isLoading = false
    }
    
    private func openChurchProfile(churchId: String) {
        ChurchDeepLinkHandler.shared.openChurch(id: churchId)
    }
}

// MARK: - Post Extension

extension Post {
    /// Get church tags for this post
    func loadChurchTags() async -> [ChurchTag] {
        let postId = firebaseId ?? id.uuidString
        
        do {
            return try await ChurchDataService.shared.getTags(
                context: .post,
                contextId: postId
            )
        } catch {
            dlog("⚠️ Failed to load church tags: \(error)")
            return []
        }
    }
}

// MARK: - Helper View for PostCard Integration

struct PostContentWithChurchTags: View {
    let post: Post
    let userLocation: CLLocation?
    
    @State private var churchTags: [ChurchTag] = []
    
    var body: some View {
        ChurchTaggedText(
            text: post.content,
            churchTags: churchTags,
            userLocation: userLocation
        )
        .task {
            churchTags = await post.loadChurchTags()
        }
    }
}

// MARK: - Church Tag Input Helper

/// Helper to save church tags when creating a post
@MainActor
class ChurchTagSaver {
    static let shared = ChurchTagSaver()
    private init() {}
    
    /// Save church tags for a post
    func saveTags(
        churches: [ChurchEntity],
        postId: String,
        context: ChurchTag.TagContext,
        userLocation: CLLocation?
    ) async throws {
        
        for church in churches {
            let distance = userLocation?.distance(from: church.coordinate.clLocation)
            let distanceInMiles = distance != nil ? distance! / 1609.34 : nil
            
            _ = try await ChurchDataService.shared.createTag(
                churchId: church.id,
                context: context,
                contextId: postId,
                distance: distanceInMiles
            )
        }
        
        #if DEBUG
        dlog("✅ Saved \(churches.count) church tags for \(context.rawValue): \(postId)")
        #endif
    }
}

// MARK: - Preview

#Preview {
    ChurchTaggedText(
        text: "Visiting a new church this Sunday! Excited to check it out.",
        churchTags: [
            ChurchTag(
                id: "tag1",
                churchId: "church1",
                churchName: "Redeemer Presbyterian",
                city: "New York",
                distance: 2.5,
                taggedAt: Date(),
                taggedBy: "user1",
                context: .post,
                contextId: "post1"
            )
        ],
        userLocation: CLLocation(latitude: 40.7128, longitude: -74.0060)
    )
    .padding()
}

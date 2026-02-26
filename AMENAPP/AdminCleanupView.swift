//
//  AdminCleanupView.swift
//  AMENAPP
//
//  Admin tool to clean up fake/sample data from Firebase
//

import SwiftUI
import FirebaseFirestore

struct AdminCleanupView: View {
    @StateObject private var postService = FirebasePostService.shared
    @State private var isDeleting = false
    @State private var showConfirmation = false
    @State private var deletionComplete = false
    @State private var deletedCount = 0
    
    @State private var isCleaningConversations = false
    @State private var showConversationConfirmation = false
    @State private var conversationCleanupComplete = false
    @State private var duplicateConversationsRemoved = 0
    
    // AI Content Detection
    @State private var isScanningAI = false
    @State private var aiScanComplete = false
    @State private var aiScannedCount = 0
    @State private var aiFlaggedCount = 0
    @State private var aiDeletedCount = 0
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("⚠️ Warning: This will permanently delete fake sample data from your Firebase database.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.red)
                } header: {
                    Text("Admin Tools")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                Section {
                    Button {
                        showConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                                .foregroundStyle(.red)
                            
                            Text("Delete All Fake Posts")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.red)
                            
                            Spacer()
                            
                            if isDeleting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isDeleting)
                    
                    if deletionComplete {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Deleted \(deletedCount) fake posts")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("Posts Cleanup")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                Section {
                    Button {
                        showConversationConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "message.badge.filled.fill")
                                .foregroundStyle(.orange)
                            
                            Text("Clean Up Duplicate Conversations")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.orange)
                            
                            Spacer()
                            
                            if isCleaningConversations {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isCleaningConversations)
                    
                    if conversationCleanupComplete {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Removed \(duplicateConversationsRemoved) duplicate conversations")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("Conversations Cleanup")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                // 🤖 AI Content Detection Section
                Section {
                    Button {
                        scanForAIContent()
                    } label: {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(.purple)
                            
                            Text("Scan for AI-Generated Posts")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.purple)
                            
                            Spacer()
                            
                            if isScanningAI {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isScanningAI)
                    
                    if aiScanComplete {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("AI Scan Complete")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.green)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Scanned: \(aiScannedCount) posts")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                Text("• Flagged: \(aiFlaggedCount) posts")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.orange)
                                Text("• Deleted: \(aiDeletedCount) posts")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.red)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("Automatically detects and removes AI-generated content (ChatGPT, Claude, etc.) to keep the community authentic.")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("AI Content Detection")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                Section {
                    Text("This will delete posts by these fake authors:")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(fakeAuthorNames, id: \.self) { name in
                            Text("• \(name)")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Fake Authors to Remove")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
            }
            .navigationTitle("Admin Cleanup")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog(
                "Delete All Fake Posts?",
                isPresented: $showConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Fake Posts", role: .destructive) {
                    deleteFakePosts()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all sample data posts from Firebase. This action cannot be undone.")
            }
            .confirmationDialog(
                "Clean Up Duplicate Conversations?",
                isPresented: $showConversationConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clean Up Duplicates", role: .destructive) {
                    cleanUpDuplicateConversations()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will keep only the most recent conversation with each user and delete older duplicates. This action cannot be undone.")
            }
        }
    }
    
    private var fakeAuthorNames: [String] {
        [
            "Sarah Chen",
            "Sarah Johnson",
            "David Chen",
            "Mike Chen",
            "Michael Chen",
            "Michael Thompson",
            "Emily Rodriguez",
            "James Parker",
            "Grace Thompson",
            "Daniel Park",
            "Rebecca Santos",
            "Sarah Mitchell",
            "Marcus Lee",
            "Jennifer Adams",
            "Emily Foster",
            "David & Rachel",
            "Patricia Moore",
            "George Thompson",
            "Angela Rivera",
            "Olivia Chen",
            "Nathan Parker",
            "Maria Santos",
            "Hannah Davis",
            "Jacob Williams",
            "Linda Martinez",
            "Rachel Kim",
            "David Martinez",
            "Anonymous"
        ]
    }
    
    private func deleteFakePosts() {
        isDeleting = true
        deletionComplete = false
        
        Task {
            do {
                // Get count before deletion
                let snapshot = try await Firestore.firestore()
                    .collection("posts")
                    .getDocuments()
                
                let beforeCount = snapshot.documents.count
                
                // Delete fake posts
                try await postService.deleteFakePosts()
                
                // Get count after deletion
                let afterSnapshot = try await Firestore.firestore()
                    .collection("posts")
                    .getDocuments()
                
                let afterCount = afterSnapshot.documents.count
                
                await MainActor.run {
                    deletedCount = beforeCount - afterCount
                    isDeleting = false
                    deletionComplete = true
                    
                    // Haptic feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
                
                print("✅ Cleanup complete! Deleted \(deletedCount) fake posts")
                
            } catch {
                print("❌ Error deleting fake posts: \(error)")
                await MainActor.run {
                    isDeleting = false
                }
            }
        }
    }
    
    private func scanForAIContent() {
        isScanningAI = true
        aiScanComplete = false
        aiScannedCount = 0
        aiFlaggedCount = 0
        aiDeletedCount = 0
        
        Task {
            do {
                print("🤖 Starting AI content scan...")
                
                // Scan posts in batches
                let result = try await AIContentDetectionService.shared.scanExistingPosts(batchSize: 50)
                
                await MainActor.run {
                    aiScannedCount = result.totalScanned
                    aiFlaggedCount = result.flaggedCount
                    aiDeletedCount = result.deletedCount
                    aiScanComplete = true
                    isScanningAI = false
                }
                
                print("✅ AI scan complete:")
                print("   - Scanned: \(result.totalScanned)")
                print("   - Flagged: \(result.flaggedCount)")
                print("   - Deleted: \(result.deletedCount)")
                
            } catch {
                print("❌ Error scanning for AI content: \(error)")
                await MainActor.run {
                    isScanningAI = false
                }
            }
        }
    }
    
    private func cleanUpDuplicateConversations() {
        isCleaningConversations = true
        conversationCleanupComplete = false
        
        Task {
            do {
                let db = Firestore.firestore()
                let currentUserId = FirebaseMessagingService.shared.currentUserId
                
                guard FirebaseMessagingService.shared.isAuthenticated else {
                    print("❌ User not authenticated")
                    await MainActor.run { isCleaningConversations = false }
                    return
                }
                
                // Get all conversations for current user
                let snapshot = try await db.collection("conversations")
                    .whereField("participantIds", arrayContains: currentUserId)
                    .whereField("isGroup", isEqualTo: false)
                    .getDocuments()
                
                print("📊 Found \(snapshot.documents.count) total 1-on-1 conversations")
                
                // Group conversations by the other participant
                var conversationsByUser: [String: [(id: String, updatedAt: Date)]] = [:]
                
                for doc in snapshot.documents {
                    let data = doc.data()
                    guard let participantIds = data["participantIds"] as? [String],
                          participantIds.count == 2 else {
                        continue
                    }
                    
                    // Get the other user's ID
                    let otherUserId = participantIds.first { $0 != currentUserId } ?? ""
                    guard !otherUserId.isEmpty else { continue }
                    
                    // Get updatedAt timestamp
                    let updatedAt: Date
                    if let timestamp = data["updatedAt"] as? Timestamp {
                        updatedAt = timestamp.dateValue()
                    } else if let dateString = data["updatedAt"] as? String,
                              let date = ISO8601DateFormatter().date(from: dateString) {
                        updatedAt = date
                    } else {
                        updatedAt = Date(timeIntervalSince1970: 0)
                    }
                    
                    if conversationsByUser[otherUserId] == nil {
                        conversationsByUser[otherUserId] = []
                    }
                    conversationsByUser[otherUserId]?.append((id: doc.documentID, updatedAt: updatedAt))
                }
                
                // Find and delete duplicates (keep the most recent)
                var duplicatesToDelete: [String] = []
                
                for (userId, conversations) in conversationsByUser {
                    if conversations.count > 1 {
                        // Sort by updatedAt descending (most recent first)
                        let sorted = conversations.sorted { $0.updatedAt > $1.updatedAt }
                        
                        print("🔍 Found \(conversations.count) conversations with user \(userId)")
                        print("   Keeping: \(sorted[0].id) (most recent)")
                        
                        // Mark all except the first (most recent) for deletion
                        for conv in sorted.dropFirst() {
                            print("   Deleting: \(conv.id)")
                            duplicatesToDelete.append(conv.id)
                        }
                    }
                }
                
                // Delete the duplicates
                for convId in duplicatesToDelete {
                    try await db.collection("conversations").document(convId).delete()
                }
                
                await MainActor.run {
                    duplicateConversationsRemoved = duplicatesToDelete.count
                    isCleaningConversations = false
                    conversationCleanupComplete = true
                    
                    // Haptic feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
                
                print("✅ Cleanup complete! Removed \(duplicatesToDelete.count) duplicate conversations")
                
            } catch {
                print("❌ Error cleaning up conversations: \(error)")
                await MainActor.run {
                    isCleaningConversations = false
                }
            }
        }
    }
}

#Preview {
    AdminCleanupView()
}

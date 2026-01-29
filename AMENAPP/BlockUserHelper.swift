//
//  BlockUserHelper.swift
//  AMENAPP
//
//  Created by Steph on 1/21/26.
//
//  Helper views and functions for blocking users from various screens
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Block User Button

/// Add this to user profile menus, post cards, etc.
struct BlockUserButton: View {
    let userId: String
    let username: String
    @State private var showBlockConfirmation = false
    @State private var showReportOptions = false
    
    var body: some View {
        Button(role: .destructive) {
            showBlockConfirmation = true
        } label: {
            Label("Block @\(username)", systemImage: "hand.raised.fill")
        }
        .confirmationDialog(
            "Block @\(username)?",
            isPresented: $showBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                blockUser()
            }
            
            Button("Block and Report") {
                showReportOptions = true
            }
            
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to follow you or see your posts. You can unblock them anytime from Settings.")
        }
        .sheet(isPresented: $showReportOptions) {
            ReportAndBlockSheet(userId: userId, username: username)
        }
    }
    
    private func blockUser() {
        Task {
            do {
                try await BlockService.shared.blockUser(userId: userId)
                print("✅ Blocked @\(username)")
                
                // Show toast notification (optional)
                // ToastService.shared.show("Blocked @\(username)")
            } catch {
                print("❌ Failed to block user: \(error)")
            }
        }
    }
}

// MARK: - Unblock User Button

/// For viewing blocked user profiles or in blocked users list
struct UnblockUserButton: View {
    let userId: String
    let username: String
    @State private var showUnblockConfirmation = false
    
    var body: some View {
        Button {
            showUnblockConfirmation = true
        } label: {
            Label("Unblock @\(username)", systemImage: "hand.raised.slash")
        }
        .confirmationDialog(
            "Unblock @\(username)?",
            isPresented: $showUnblockConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unblock") {
                unblockUser()
            }
            
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will be able to follow you and view your posts again.")
        }
    }
    
    private func unblockUser() {
        Task {
            do {
                try await BlockService.shared.unblockUser(userId: userId)
                print("✅ Unblocked @\(username)")
            } catch {
                print("❌ Failed to unblock user: \(error)")
            }
        }
    }
}

// MARK: - Report and Block Sheet

struct ReportAndBlockSheet: View {
    @Environment(\.dismiss) var dismiss
    let userId: String
    let username: String
    
    @State private var selectedReason: ReportReason = .spam
    @State private var additionalDetails = ""
    @State private var isSubmitting = false
    
    enum ReportReason: String, CaseIterable {
        case spam = "Spam"
        case harassment = "Harassment or Bullying"
        case inappropriate = "Inappropriate Content"
        case impersonation = "Impersonation"
        case other = "Other"
        
        var icon: String {
            switch self {
            case .spam: return "envelope.badge.fill"
            case .harassment: return "exclamationmark.triangle.fill"
            case .inappropriate: return "eye.slash.fill"
            case .impersonation: return "person.fill.questionmark"
            case .other: return "ellipsis.circle.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("You're about to report and block @\(username)")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("REPORT USER")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                Section {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(ReportReason.allCases, id: \.self) { reason in
                            Label {
                                Text(reason.rawValue)
                                    .font(.custom("OpenSans-Regular", size: 15))
                            } icon: {
                                Image(systemName: reason.icon)
                            }
                            .tag(reason)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("REASON")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                Section {
                    TextEditor(text: $additionalDetails)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .frame(height: 100)
                } header: {
                    Text("ADDITIONAL DETAILS (OPTIONAL)")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                Section {
                    Button {
                        submitReport()
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text("Submit Report & Block")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSubmitting)
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Report User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
        }
    }
    
    private func submitReport() {
        isSubmitting = true
        
        Task {
            do {
                // 1. Submit report to Firestore
                try await submitReportToFirestore()
                
                // 2. Block the user
                try await BlockService.shared.blockUser(userId: userId)
                
                print("✅ Reported and blocked @\(username)")
                
                // Dismiss
                await MainActor.run {
                    dismiss()
                }
                
                // Show success message (optional)
                // ToastService.shared.show("User reported and blocked")
                
            } catch {
                print("❌ Failed to report/block user: \(error)")
            }
            
            isSubmitting = false
        }
    }
    
    private func submitReportToFirestore() async throws {
        let db = Firestore.firestore()
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReportError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let report: [String: Any] = [
            "reporterId": currentUserId,
            "reportedUserId": userId,
            "reportedUsername": username,
            "reason": selectedReason.rawValue,
            "details": additionalDetails,
            "createdAt": Date(),
            "status": "pending"
        ]
        
        try await db.collection("reports").addDocument(data: report)
        
        print("✅ Report submitted successfully")
    }
}

// MARK: - Usage Examples

/*
 
 // 1. In User Profile Menu (e.g., when viewing another user's profile)
 
 Menu {
     Button {
         // Follow/Unfollow
     } label: {
         Label("Follow", systemImage: "person.badge.plus")
     }
     
     Button {
         // Send Message
     } label: {
         Label("Send Message", systemImage: "envelope")
     }
     
     Divider()
     
     // Add block button
     BlockUserButton(userId: user.id, username: user.username)
     
 } label: {
     Image(systemName: "ellipsis")
 }
 
 
 // 2. In Post Card Menu (e.g., TestimonyPostCard, PostCard)
 
 Menu {
     if isOwnPost {
         Button { editPost() } label: {
             Label("Edit", systemImage: "pencil")
         }
         Button(role: .destructive) { deletePost() } label: {
             Label("Delete", systemImage: "trash")
         }
     } else {
         Button { reportPost() } label: {
             Label("Report Post", systemImage: "exclamationmark.triangle")
         }
         
         Divider()
         
         // Block post author
         BlockUserButton(userId: post.authorId, username: post.authorName)
     }
 } label: {
     Image(systemName: "ellipsis")
 }
 
 
 // 3. In Comment Menu
 
 Menu {
     if isOwnComment {
         Button { editComment() } label: {
             Label("Edit", systemImage: "pencil")
         }
         Button(role: .destructive) { deleteComment() } label: {
             Label("Delete", systemImage: "trash")
         }
     } else {
         Button { reportComment() } label: {
             Label("Report", systemImage: "flag")
         }
         
         // Block comment author
         BlockUserButton(userId: comment.authorId, username: comment.authorName)
     }
 } label: {
     Image(systemName: "ellipsis")
 }
 
 
 // 4. In Direct Message Conversation
 
 .toolbar {
     ToolbarItem(placement: .navigationBarTrailing) {
         Menu {
             Button { muteConversation() } label: {
                 Label("Mute", systemImage: "bell.slash")
             }
             
             Button { deleteConversation() } label: {
                 Label("Delete Conversation", systemImage: "trash")
             }
             
             Divider()
             
             BlockUserButton(userId: otherUser.id, username: otherUser.username)
             
         } label: {
             Image(systemName: "ellipsis.circle")
         }
     }
 }
 
 */

// MARK: - Helper to check block status before showing content

extension View {
    /// Hide content if user is blocked or has blocked you
    func hideIfBlocked(userId: String) -> some View {
        modifier(BlockCheckModifier(userId: userId))
    }
}

struct BlockCheckModifier: ViewModifier {
    let userId: String
    @State private var hasBlockRelationship = false
    @State private var isChecking = true
    
    func body(content: Content) -> some View {
        Group {
            if isChecking {
                ProgressView()
                    .onAppear {
                        checkBlockStatus()
                    }
            } else if hasBlockRelationship {
                // Show blocked state
                VStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("User Unavailable")
                        .font(.custom("OpenSans-Bold", size: 16))
                    Text("This content is not available")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                content
            }
        }
    }
    
    private func checkBlockStatus() {
        Task {
            let blocked = await BlockService.shared.hasBlockRelationship(userId: userId)
            
            await MainActor.run {
                hasBlockRelationship = blocked
                isChecking = false
            }
        }
    }
}

// MARK: - Preview

#Preview("Block Button") {
    BlockUserButton(userId: "user123", username: "johndoe")
}

#Preview("Unblock Button") {
    UnblockUserButton(userId: "user123", username: "johndoe")
}

#Preview("Report Sheet") {
    ReportAndBlockSheet(userId: "user123", username: "johndoe")
}

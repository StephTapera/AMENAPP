//
//  ProfileImageDebugView.swift
//  AMENAPP
//
//  Debug helper to check profile image status
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileImageDebugView: View {
    @State private var debugInfo: String = "Loading..."
    @State private var cachedURL: String?
    @State private var firestoreURL: String?
    @State private var postsWithImages: Int = 0
    @State private var postsWithoutImages: Int = 0
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Profile Image Debug")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                GroupBox("UserDefaults Cache") {
                    if let cachedURL = cachedURL {
                        Text("✅ Cached: \(cachedURL)")
                            .font(.custom("OpenSans-Regular", size: 12))
                    } else {
                        Text("❌ No cached profile image URL")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.red)
                    }
                }
                
                GroupBox("Firestore User Document") {
                    if let firestoreURL = firestoreURL {
                        Text("✅ Firestore: \(firestoreURL)")
                            .font(.custom("OpenSans-Regular", size: 12))
                    } else {
                        Text("❌ No profileImageURL in Firestore")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.red)
                    }
                }
                
                GroupBox("Post Analysis") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Posts with profile images: \(postsWithImages)")
                        Text("Posts without profile images: \(postsWithoutImages)")
                    }
                    .font(.custom("OpenSans-Regular", size: 12))
                }
                
                Button("Refresh Debug Info") {
                    Task {
                        await loadDebugInfo()
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Cache Profile Image Now") {
                    Task {
                        await UserProfileImageCache.shared.cacheCurrentUserProfile()
                        await loadDebugInfo()
                    }
                }
                .buttonStyle(.bordered)
                
                Text(debugInfo)
                    .font(.custom("OpenSans-Regular", size: 10))
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding()
        }
        .task {
            await loadDebugInfo()
        }
    }
    
    private func loadDebugInfo() async {
        var info = "=== DEBUG INFO ===\n\n"
        
        // Check UserDefaults
        cachedURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
        info += "UserDefaults Cache:\n"
        info += "- currentUserProfileImageURL: \(cachedURL ?? "nil")\n\n"
        
        // Check Firestore
        guard let userId = Auth.auth().currentUser?.uid else {
            debugInfo = "Not authenticated"
            return
        }
        
        do {
            let db = Firestore.firestore()
            let userDoc = try await db.collection("users").document(userId).getDocument()
            
            if let userData = userDoc.data() {
                info += "Firestore User Document:\n"
                info += "- displayName: \(userData["displayName"] as? String ?? "nil")\n"
                info += "- username: \(userData["username"] as? String ?? "nil")\n"
                info += "- initials: \(userData["initials"] as? String ?? "nil")\n"
                firestoreURL = userData["profileImageURL"] as? String
                info += "- profileImageURL: \(firestoreURL ?? "nil")\n\n"
            } else {
                info += "Firestore: User document not found\n\n"
            }
            
            // Check recent posts
            let postsSnapshot = try await db.collection("posts")
                .whereField("authorId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 10)
                .getDocuments()
            
            postsWithImages = 0
            postsWithoutImages = 0
            
            info += "Recent Posts Analysis:\n"
            for (index, doc) in postsSnapshot.documents.enumerated() {
                let data = doc.data()
                if let imageURL = data["authorProfileImageURL"] as? String, !imageURL.isEmpty {
                    postsWithImages += 1
                    info += "  \(index + 1). ✅ Has profile image\n"
                } else {
                    postsWithoutImages += 1
                    info += "  \(index + 1). ❌ No profile image\n"
                }
            }
            
        } catch {
            info += "Error: \(error.localizedDescription)\n"
        }
        
        debugInfo = info
    }
}

#Preview {
    ProfileImageDebugView()
}

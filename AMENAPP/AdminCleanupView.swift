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
                    Text("Actions")
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
}

#Preview {
    AdminCleanupView()
}

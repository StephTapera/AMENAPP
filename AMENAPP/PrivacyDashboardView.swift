//
//  PrivacyDashboardView.swift
//  AMENAPP
//
//  Privacy-first user data dashboard
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct PrivacyDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var userData: UserDataSummary?
    @State private var isLoading = true
    @State private var isExporting = false
    @State private var showExportSuccess = false
    
    struct UserDataSummary {
        var postsCount: Int
        var commentsCount: Int
        var interactionsCount: Int
        var accountCreated: Date
        var dataCollected: [String]
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        
                        Text("Privacy Dashboard")
                            .font(.custom("OpenSans-Bold", size: 26))
                        
                        Text("Your data, your control")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let data = userData {
                        // Data Summary
                        VStack(alignment: .leading, spacing: 16) {
                            Text("What We Have")
                                .font(.custom("OpenSans-Bold", size: 20))
                            
                            dataRow("Posts", value: "\(data.postsCount)")
                            dataRow("Comments", value: "\(data.commentsCount)")
                            dataRow("Interactions", value: "\(data.interactionsCount)")
                            dataRow("Member Since", value: data.accountCreated.formatted(date: .abbreviated, time: .omitted))
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 10)
                        )
                        
                        // Data Categories
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Data Categories")
                                .font(.custom("OpenSans-Bold", size: 20))
                            
                            ForEach(data.dataCollected, id: \.self) { category in
                                HStack {
                                    Image(systemName: "doc.text")
                                        .foregroundColor(.blue)
                                    Text(category)
                                        .font(.custom("OpenSans-Regular", size: 15))
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 10)
                        )
                        
                        // Actions
                        VStack(spacing: 12) {
                            Button {
                                exportData()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.down.doc")
                                    Text(isExporting ? "Exporting..." : "Export My Data")
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue)
                                .cornerRadius(12)
                            }
                            .disabled(isExporting)
                            
                            Text("We'll email you a complete copy of your data")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadUserData()
        }
        .alert("Export Requested", isPresented: $showExportSuccess) {
            Button("OK") { }
        } message: {
            Text("We'll email you a copy of your data within 48 hours.")
        }
    }
    
    private func dataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundColor(.primary)
        }
    }
    
    private func loadUserData() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let db = Firestore.firestore()
            
            // Get user doc
            let userDoc = try await db.collection("users").document(userId).getDocument()
            let created = (userDoc.data()?["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            
            // Count posts
            let postsSnapshot = try await db.collection("posts").whereField("userId", isEqualTo: userId).getDocuments()
            
            // Count comments  
            let commentsSnapshot = try await db.collection("comments").whereField("userId", isEqualTo: userId).getDocuments()
            
            await MainActor.run {
                userData = UserDataSummary(
                    postsCount: postsSnapshot.documents.count,
                    commentsCount: commentsSnapshot.documents.count,
                    interactionsCount: 0,
                    accountCreated: created,
                    dataCollected: [
                        "Profile Information",
                        "Posts & Comments",
                        "Likes & Interactions",
                        "Follow Relationships",
                        "Usage Analytics"
                    ]
                )
                isLoading = false
            }
        } catch {
            print("❌ Failed to load user data: \(error)")
            isLoading = false
        }
    }
    
    private func exportData() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isExporting = true
        
        Task {
            try? await Firestore.firestore().collection("dataExportRequests").document().setData([
                "userId": userId,
                "requestedAt": FieldValue.serverTimestamp(),
                "status": "pending"
            ])
            
            await MainActor.run {
                isExporting = false
                showExportSuccess = true
            }
        }
    }
}

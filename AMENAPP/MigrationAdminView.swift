//
//  MigrationAdminView.swift
//  AMENAPP
//
//  Admin view for running database migrations
//

import SwiftUI

struct MigrationAdminView: View {
    @State private var isChecking = false
    @State private var isMigrating = false
    @State private var statusMessage = ""
    @State private var totalPosts = 0
    @State private var postsNeedingMigration = 0
    @State private var showCompletionAlert = false
    @State private var migrationComplete = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        
                        Text("Profile Image Migration")
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        Text("Add profile images to existing posts")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)
                    
                    // Status Card
                    if totalPosts > 0 {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "chart.bar.doc.horizontal")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.blue)
                                
                                Text("Migration Status")
                                    .font(.custom("OpenSans-Bold", size: 18))
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("Total Posts:")
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(totalPosts)")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            
                            HStack {
                                Text("Need Migration:")
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(postsNeedingMigration)")
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(postsNeedingMigration > 0 ? .orange : .green)
                            }
                            
                            if postsNeedingMigration == 0 && totalPosts > 0 {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("All posts have profile images!")
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                        .foregroundStyle(.green)
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    // Status Messages
                    if !statusMessage.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.blue)
                                Text("Status")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            
                            Text(statusMessage)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        // Check Status Button
                        Button {
                            Task {
                                await checkMigrationStatus()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isChecking {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "magnifyingglass")
                                }
                                Text("Check Migration Status")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue)
                            )
                        }
                        .disabled(isChecking || isMigrating)
                        
                        // Migrate Button
                        if postsNeedingMigration > 0 {
                            Button {
                                Task {
                                    await runMigration()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if isMigrating {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text("Migrate \(postsNeedingMigration) Posts")
                                        .font(.custom("OpenSans-Bold", size: 16))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.orange)
                                )
                            }
                            .disabled(isChecking || isMigrating)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    Spacer(minLength: 40)
                    
                    // Warning
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Important")
                                .font(.custom("OpenSans-Bold", size: 14))
                        }
                        
                        Text("This migration will update all existing posts to include the author's current profile image URL. This is a one-time operation and is safe to run multiple times.")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Database Migration")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Migration Complete", isPresented: $showCompletionAlert) {
                Button("OK") {
                    // Refresh status after migration
                    Task {
                        await checkMigrationStatus()
                    }
                }
            } message: {
                Text("All posts have been successfully updated with profile images!")
            }
        }
    }
    
    // MARK: - Actions
    
    private func checkMigrationStatus() async {
        isChecking = true
        statusMessage = "Checking database..."
        
        do {
            let status = try await PostProfileImageMigration.shared.checkStatus()
            
            await MainActor.run {
                totalPosts = status.totalPosts
                postsNeedingMigration = status.needsMigration
                
                if postsNeedingMigration == 0 {
                    statusMessage = "✅ All \(totalPosts) posts already have profile images!"
                } else {
                    statusMessage = "⚠️ Found \(postsNeedingMigration) posts that need migration"
                }
                
                isChecking = false
            }
        } catch {
            await MainActor.run {
                statusMessage = "❌ Error checking status: \(error.localizedDescription)"
                isChecking = false
            }
        }
    }
    
    private func runMigration() async {
        isMigrating = true
        statusMessage = "Migrating posts... This may take a moment."
        
        do {
            try await PostProfileImageMigration.shared.migrateAllPosts()
            
            await MainActor.run {
                migrationComplete = true
                statusMessage = "✅ Migration completed successfully!"
                showCompletionAlert = true
                isMigrating = false
            }
        } catch {
            await MainActor.run {
                statusMessage = "❌ Migration error: \(error.localizedDescription)"
                isMigrating = false
            }
        }
    }
}

#Preview {
    MigrationAdminView()
}

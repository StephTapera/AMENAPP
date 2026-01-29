//
//  DeveloperToolsView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//
//  Developer tools for debugging and maintenance
//

import SwiftUI

struct DeveloperToolsView: View {
    @State private var isMigratingUsers = false
    @State private var migrationResult: String?
    @State private var showMigrationAlert = false
    @State private var testSearchQuery = ""
    @State private var searchResults: [String] = []
    
    var body: some View {
        NavigationStack {
            List {
                Section("User Search") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fix User Search Issues")
                            .font(.custom("OpenSans-Bold", size: 16))
                        
                        Text("This will update all user profiles to be searchable by adding lowercase username and display name fields.")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                        
                        Button {
                            runUserMigration()
                        } label: {
                            HStack {
                                if isMigratingUsers {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "person.2.fill")
                                }
                                Text(isMigratingUsers ? "Migrating..." : "Migrate Users for Search")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isMigratingUsers ? Color.gray : Color.blue)
                            )
                        }
                        .disabled(isMigratingUsers)
                        
                        if let result = migrationResult {
                            Text(result)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(result.contains("✅") ? .green : .red)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Firestore Indexes") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Required Indexes")
                            .font(.custom("OpenSans-Bold", size: 16))
                        
                        Text("You need to create these indexes in Firebase Console for search to work:")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            IndexInfoRow(
                                title: "Username Search",
                                collection: "users",
                                fields: ["usernameLowercase (Ascending)", "Document ID (Ascending)"]
                            )
                            
                            IndexInfoRow(
                                title: "Display Name Search",
                                collection: "users",
                                fields: ["displayNameLowercase (Ascending)", "Document ID (Ascending)"]
                            )
                        }
                        
                        Button {
                            if let url = URL(string: "https://console.firebase.google.com/project/_/firestore/indexes") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "link")
                                Text("Open Firebase Console")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.orange)
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Test Search") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Test User Search")
                            .font(.custom("OpenSans-Bold", size: 16))
                        
                        HStack {
                            TextField("Search users...", text: $testSearchQuery)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .textFieldStyle(.roundedBorder)
                            
                            Button {
                                testSearch()
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(Circle().fill(Color.blue))
                            }
                        }
                        
                        if !searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Results:")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                
                                ForEach(searchResults, id: \.self) { result in
                                    Text("• \(result)")
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Instructions") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to Fix Search")
                            .font(.custom("OpenSans-Bold", size: 16))
                        
                        InstructionStep(number: 1, text: "Tap 'Migrate Users for Search' above")
                        InstructionStep(number: 2, text: "Open Firebase Console using the button above")
                        InstructionStep(number: 3, text: "Go to Firestore Database → Indexes")
                        InstructionStep(number: 4, text: "Create the two indexes listed above")
                        InstructionStep(number: 5, text: "Wait 2-3 minutes for indexes to build")
                        InstructionStep(number: 6, text: "Test search using the 'Test Search' section")
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Developer Tools")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Migration Complete", isPresented: $showMigrationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(migrationResult ?? "Migration completed")
            }
        }
    }
    
    // MARK: - Actions
    
    private func runUserMigration() {
        isMigratingUsers = true
        migrationResult = nil
        
        Task {
            do {
                try await FirebaseManager.shared.migrateUsersForSearch()
                
                await MainActor.run {
                    migrationResult = "✅ Migration successful! Users are now searchable."
                    isMigratingUsers = false
                    showMigrationAlert = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    migrationResult = "❌ Migration failed: \(error.localizedDescription)"
                    isMigratingUsers = false
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func testSearch() {
        guard !testSearchQuery.isEmpty else { return }
        
        Task {
            do {
                let results = try await SearchService.shared.searchPeople(query: testSearchQuery)
                
                await MainActor.run {
                    searchResults = results.map { "\($0.title) (\($0.subtitle))" }
                    
                    if searchResults.isEmpty {
                        searchResults = ["No results found. Make sure indexes are created!"]
                    }
                }
            } catch {
                await MainActor.run {
                    searchResults = ["Error: \(error.localizedDescription)"]
                }
            }
        }
    }
}

// MARK: - Index Info Row

struct IndexInfoRow: View {
    let title: String
    let collection: String
    let fields: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.primary)
            
            Text("Collection: \(collection)")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                ForEach(fields, id: \.self) { field in
                    Text("• \(field)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.1))
        )
    }
}

// MARK: - Instruction Step

struct InstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 28, height: 28)
                
                Text("\(number)")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.white)
            }
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    DeveloperToolsView()
}

//
//  DeveloperMenuView.swift
//  AMENAPP
//
//  Temporary developer menu for running migrations and admin tasks
//  ⚠️ Remove this from production builds
//

import SwiftUI

struct DeveloperMenuView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        MigrationAdminView()
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Profile Image Migration")
                                    .font(.custom("OpenSans-SemiBold", size: 16))
                                Text("Add profile images to existing posts")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("Database Migrations")
                }
                
                Section {
                    Button {
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.gray)
                            Text("Close Developer Menu")
                                .font(.custom("OpenSans-Regular", size: 16))
                        }
                    }
                }
            }
            .navigationTitle("Developer Menu")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    DeveloperMenuView()
}

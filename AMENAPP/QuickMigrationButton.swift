#if DEBUG
//
//  QuickMigrationButton.swift
//  AMENAPP
//
//  Quick access button for running profile image migration
//  Debug only — not included in Release builds
//

import SwiftUI

struct QuickMigrationButton: View {
    @State private var showMigrationView = false

    var body: some View {
        Button {
            showMigrationView = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 14))
                Text("Migrate")
                    .font(.custom("OpenSans-Bold", size: 13))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.orange)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            )
        }
        .padding(20)
        .sheet(isPresented: $showMigrationView) {
            MigrationAdminView()
        }
    }
}

extension View {
    func withMigrationButton() -> some View {
        self.overlay(alignment: .bottomTrailing) {
            QuickMigrationButton()
        }
    }
}
#endif

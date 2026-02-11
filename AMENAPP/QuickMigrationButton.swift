//
//  QuickMigrationButton.swift
//  AMENAPP
//
//  Quick access button for running profile image migration
//  Add this to any view for easy testing, then remove when done
//

import SwiftUI

/// Quick access button for migration - drop this into any view for testing
/// Usage:
/// ```swift
/// .overlay(alignment: .bottomTrailing) {
///     QuickMigrationButton()
/// }
/// ```
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

// MARK: - Usage Examples

/// Example 1: Add to ContentView as floating button
extension View {
    func withMigrationButton() -> some View {
        self.overlay(alignment: .bottomTrailing) {
            QuickMigrationButton()
        }
    }
}

/// Example 2: Inline in any view
/*
 struct OpenTableView: View {
     var body: some View {
         VStack {
             // Your content here
         }
         .overlay(alignment: .bottomTrailing) {
             QuickMigrationButton()
         }
     }
 }
 */

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
        
        VStack {
            Text("Your App Content")
                .font(.title)
            Spacer()
        }
        .overlay(alignment: .bottomTrailing) {
            QuickMigrationButton()
        }
    }
}

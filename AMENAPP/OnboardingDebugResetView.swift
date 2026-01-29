//
//  DebugResetView.swift
//  AMENAPP
//
//  Created by Steph on 1/18/26.
//
//  Debug helper to reset onboarding/auth state for testing
//  Remove this file in production or wrap in #if DEBUG
//

import SwiftUI

#if DEBUG
struct DebugResetView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Current State") {
                    HStack {
                        Text("Completed Onboarding")
                        Spacer()
                        Text(hasCompletedOnboarding ? "Yes" : "No")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Logged In")
                        Spacer()
                        Text(isLoggedIn ? "Yes" : "No")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Quick Actions") {
                    Button {
                        hasCompletedOnboarding = false
                        isLoggedIn = false
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to First Launch")
                        }
                    }
                    
                    Button {
                        hasCompletedOnboarding = true
                        isLoggedIn = false
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "person.fill.questionmark")
                            Text("Skip to Auth Screen")
                        }
                    }
                    
                    Button {
                        hasCompletedOnboarding = true
                        isLoggedIn = true
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Skip to Main App")
                        }
                    }
                }
                
                Section("Manual Toggles") {
                    Toggle("Completed Onboarding", isOn: $hasCompletedOnboarding)
                    Toggle("Logged In", isOn: $isLoggedIn)
                }
            }
            .navigationTitle("Debug Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    DebugResetView()
}
#endif

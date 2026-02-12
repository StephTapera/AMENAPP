//
//  QuickProfileImageFixView.swift
//  AMENAPP
//
//  Quick fix view to update profile image cache and migrate posts
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct QuickProfileImageFixView: View {
    @State private var isProcessing = false
    @State private var statusMessage = "Ready to fix profile images"
    @State private var showSuccess = false
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
                .padding(.top, 40)
            
            Text("Fix Profile Images")
                .font(.custom("OpenSans-Bold", size: 24))
            
            Text("This will refresh your profile image cache and ensure it appears on new posts")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("What this does:")
                    .font(.custom("OpenSans-Bold", size: 16))
                
                Label("Refreshes your profile image from Firestore", systemImage: "arrow.clockwise")
                Label("Updates the app cache", systemImage: "square.and.arrow.down")
                Label("Makes images appear on new posts", systemImage: "checkmark.circle")
            }
            .font(.custom("OpenSans-Regular", size: 14))
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
            
            if isProcessing {
                ProgressView()
                    .scaleEffect(1.2)
                    .padding()
            }
            
            Text(statusMessage)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(showSuccess ? .green : .secondary)
                .padding(.horizontal)
                .multilineTextAlignment(.center)
            
            Button {
                fixProfileImages()
            } label: {
                Text(isProcessing ? "Processing..." : "Fix Profile Images Now")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isProcessing ? Color.gray : Color.blue)
                    .cornerRadius(12)
            }
            .disabled(isProcessing)
            .padding(.horizontal)
            
            Spacer()
        }
        .navigationTitle("Fix Profile Images")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func fixProfileImages() {
        isProcessing = true
        showSuccess = false
        statusMessage = "Refreshing profile data..."
        
        Task {
            do {
                // Step 1: Refresh cache from Firestore
                await UserProfileImageCache.shared.cacheCurrentUserProfile()
                
                await MainActor.run {
                    statusMessage = "Cache updated! Checking profile image..."
                }
                
                // Step 2: Verify the cache has an image URL
                let cachedURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
                
                await MainActor.run {
                    if let url = cachedURL, !url.isEmpty {
                        statusMessage = "✅ Success! Profile image cache updated.\n\nYour new posts will now include your profile picture.\n\nProfile URL: \(url.prefix(50))..."
                        showSuccess = true
                    } else {
                        statusMessage = "⚠️ No profile image found in Firestore.\n\nPlease upload a profile picture first:\n1. Go to your Profile\n2. Tap on your avatar\n3. Upload a photo"
                        showSuccess = false
                    }
                    isProcessing = false
                }
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(cachedURL != nil ? .success : .warning)
                
            } catch {
                await MainActor.run {
                    statusMessage = "❌ Error: \(error.localizedDescription)"
                    isProcessing = false
                    showSuccess = false
                }
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
}

#Preview {
    NavigationStack {
        QuickProfileImageFixView()
    }
}

//
//  MusicKitTest.swift
//  AMENAPP
//
//  Minimal test to verify MusicKit works
//  Copy this entire file into your project
//

import SwiftUI
import MusicKit

struct MusicKitTestView: View {
    @State private var authStatus = "Not checked"
    @State private var canPlay = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("MusicKit Test")
                .font(.largeTitle)
                .bold()
            
            Text("Status: \(authStatus)")
                .foregroundStyle(.secondary)
            
            Button("Check Authorization") {
                Task {
                    let status = MusicAuthorization.currentStatus
                    authStatus = "\(status)"
                    canPlay = status == .authorized
                }
            }
            .buttonStyle(.borderedProminent)
            
            Button("Request Permission") {
                Task {
                    let status = await MusicAuthorization.request()
                    authStatus = "\(status)"
                    canPlay = status == .authorized
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            
            if canPlay {
                Text("✅ MusicKit is working!")
                    .font(.headline)
                    .foregroundStyle(.green)
            }
        }
        .padding()
    }
}

// To use this test:
// 1. Just add this file to your project
// 2. In your app's main file, replace the current view with:
//    MusicKitTestView()
// 3. Run the app
// 4. Tap "Request Permission"
// 5. If you see the permission dialog, MusicKit is working!

#Preview {
    MusicKitTestView()
}

//
//  ChurchDeepLinkHandler.swift
//  AMENAPP
//
//  Handle church deep links throughout the app
//  amen://church/{churchId}
//

import SwiftUI
import Combine

@MainActor
class ChurchDeepLinkHandler: ObservableObject {
    static let shared = ChurchDeepLinkHandler()
    
    @Published var churchIdToOpen: String?
    @Published var showChurchProfile = false
    
    private init() {}
    
    /// Handle incoming URL
    func handleURL(_ url: URL) -> Bool {
        // Parse church deep link
        if let churchId = ChurchDeepLink.parse(url) {
            openChurch(id: churchId)
            return true
        }
        
        return false
    }
    
    /// Open church profile by ID
    func openChurch(id: String) {
        churchIdToOpen = id
        showChurchProfile = true
        
        #if DEBUG
        dlog("🔗 [DEEP LINK] Opening church: \(id)")
        #endif
    }
    
    /// Close church profile
    func closeChurch() {
        showChurchProfile = false
        churchIdToOpen = nil
    }
}

// MARK: - Deep Link View Modifier

extension View {
    func handleChurchDeepLinks() -> some View {
        modifier(ChurchDeepLinkModifier())
    }
}

struct ChurchDeepLinkModifier: ViewModifier {
    @StateObject private var handler = ChurchDeepLinkHandler.shared
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $handler.showChurchProfile) {
                if let churchId = handler.churchIdToOpen {
                    ChurchProfileView(churchId: churchId)
                }
            }
            .onOpenURL { url in
                _ = handler.handleURL(url)
            }
    }
}

// MARK: - App Integration

/// Add this to AMENAPPApp.swift:
/*
 @main
 struct AMENAPPApp: App {
     var body: some Scene {
         WindowGroup {
             ContentView()
                 .handleChurchDeepLinks()  // <-- Add this
         }
     }
 }
 */

// MARK: - Universal Link Support

/// For Info.plist - Add URL Types:
/*
 <key>CFBundleURLTypes</key>
 <array>
     <dict>
         <key>CFBundleURLSchemes</key>
         <array>
             <string>amen</string>
         </array>
         <key>CFBundleURLName</key>
         <string>com.amen.app</string>
     </dict>
 </array>
 */

/// For Associated Domains (Universal Links):
/// Add to Info.plist:
///   <key>com.apple.developer.associated-domains</key>
///   <array>
///     <string>applinks:amen.app</string>
///   </array>
///
/// Then add apple-app-site-association file to your domain root

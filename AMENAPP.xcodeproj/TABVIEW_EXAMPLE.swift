//
//  EXAMPLE: How to add WorshipMusicView to your TabView
//  Add this to your main ContentView or wherever you have tabs
//

import SwiftUI

struct ContentView_Example: View {
    var body: some View {
        TabView {
            // Your existing tabs...
            
            // Find Church tab (you already have this)
            FindChurchView()
                .tabItem {
                    Label("Churches", systemImage: "building.2")
                }
            
            // ADD THIS NEW TAB - Worship Music
            WorshipMusicView()
                .tabItem {
                    Label("Worship", systemImage: "music.note.list")
                }
            
            // Messages tab (you already have this)
            MessagesView()
                .tabItem {
                    Label("Messages", systemImage: "message")
                }
            
            // Other tabs...
        }
    }
}

// ALTERNATIVE: If you want to test it standalone first, use this:
struct WorshipMusicTestApp: App {
    var body: some Scene {
        WindowGroup {
            WorshipMusicView()
        }
    }
}

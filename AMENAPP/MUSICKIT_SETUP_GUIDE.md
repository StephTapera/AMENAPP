# MusicKit Integration Guide for AMENAPP

## Setup Steps

### 1. Enable MusicKit in Xcode

1. Open your Xcode project
2. Select your app target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **"MusicKit"**

### 2. Add MusicKit Identifier

1. Go to [Apple Developer Portal](https://developer.apple.com/account/)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Select your App ID
4. Enable **MusicKit** capability
5. Save changes

### 3. Update Info.plist

Add the following to your `Info.plist`:

```xml
<key>NSAppleMusicUsageDescription</key>
<string>AMENAPP uses Apple Music to provide worship songs and hymns for your spiritual journey.</string>
```

### 4. Add to Your Main TabView or Navigation

In your main app file (likely `ContentView.swift`), add the worship music tab:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            // Your existing tabs...
            FindChurchView()
                .tabItem {
                    Label("Find Church", systemImage: "building.2")
                }
            
            // Add this new tab
            WorshipMusicView()
                .tabItem {
                    Label("Worship", systemImage: "music.note.list")
                }
            
            // Other tabs...
        }
    }
}
```

## Features Implemented

### ✅ Core Features
- **Search worship music** by keyword
- **Category browsing** (Worship, Hymns, Gospel, etc.)
- **Play songs** with full Apple Music integration
- **30-second previews** for non-subscribers
- **Now Playing mini player** with playback controls
- **Beautiful UI** matching your app's design

### ✅ User Experience
- Authorization banner when MusicKit isn't connected
- Loading states while fetching songs
- Empty states with helpful messaging
- Haptic feedback on interactions
- Smooth animations and transitions

## Usage Examples

### Play a Worship Song
```swift
let musicManager = MusicKitManager.shared

// Request authorization first
await musicManager.requestAuthorization()

// Search for songs
let songs = try await musicManager.searchWorshipMusic(query: "Amazing Grace")

// Play a song
if let firstSong = songs.first {
    try await musicManager.playSong(firstSong)
}
```

### Get Church Service Playlist
```swift
// Get curated playlist for a church service
let playlist = try await musicManager.getServicePlaylistSuggestions()

// Play the entire playlist
try await musicManager.playCollection(playlist)
```

### Search for Hymns
```swift
let hymns = try await musicManager.searchHymns(query: "Amazing Grace")
```

## Integration Ideas

### 1. **Church Profile Integration**
Add a "This Sunday's Music" section to each church:

```swift
struct ChurchDetailView: View {
    let church: Church
    @State private var serviceSongs: [Song] = []
    
    var body: some View {
        VStack {
            // Church details...
            
            Section("This Sunday's Worship Set") {
                ForEach(serviceSongs) { song in
                    SongCard(song: song) {
                        // Play song
                    }
                }
            }
        }
    }
}
```

### 2. **Prayer Time Music**
Add background music during prayer:

```swift
struct PrayerView: View {
    @State private var isPlayingMusic = false
    
    var body: some View {
        VStack {
            // Prayer content...
            
            Button("Play Prayer Music") {
                Task {
                    let songs = try await MusicKitManager.shared
                        .searchWorshipMusic(query: "instrumental worship")
                    try await MusicKitManager.shared.playCollection(songs)
                }
            }
        }
    }
}
```

### 3. **Daily Devotional Soundtrack**
```swift
// In your devotional view
let songs = try await MusicKitManager.shared
    .searchWorshipMusic(query: "peaceful worship")
```

## Important Notes

### Cost & Requirements
- ✅ **Free** to integrate MusicKit
- ✅ 30-second previews work for everyone
- ⚠️ Full playback requires **Apple Music subscription**
- ⚠️ Requires **iOS 15.0+**

### Best Practices
1. Always request authorization before accessing MusicKit
2. Handle cases where users don't have Apple Music
3. Provide preview playback as a fallback
4. Cache search results to reduce API calls
5. Respect user privacy and music preferences

### Limitations
- Can only access Apple Music catalog
- Cannot download songs for offline use (handled by Apple Music app)
- Preview length is limited to 30 seconds
- Requires active internet connection

## Testing

### Simulator
- MusicKit works in simulator
- You'll need to sign in with an Apple ID
- Previews work without subscription

### Physical Device
- Works best on physical devices
- Test with and without Apple Music subscription
- Verify authorization flow

## Troubleshooting

### "Not Authorized" Error
- Ensure MusicKit capability is added
- Check Info.plist has usage description
- Verify user granted permission

### No Search Results
- Check internet connection
- Verify search query isn't too specific
- Try broader search terms

### Playback Issues
- Ensure user has Apple Music subscription (for full songs)
- Check if song has preview available
- Verify playback permissions

## Next Steps

1. ✅ Add MusicKit capability in Xcode
2. ✅ Update Info.plist
3. ✅ Add WorshipMusicView to your app
4. ✅ Test authorization flow
5. ✅ Customize categories for your audience
6. ✅ Add integration points with church features

## Support

For more information:
- [MusicKit Documentation](https://developer.apple.com/musickit/)
- [MusicKit WWDC Sessions](https://developer.apple.com/videos/musickit)
- [Apple Music API Reference](https://developer.apple.com/documentation/musickit)

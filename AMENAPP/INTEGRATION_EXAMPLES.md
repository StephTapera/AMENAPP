# Quick Integration Examples

## Adding Music to Existing Views

### 1. Add to FindChurchView (Church Details)

You can enhance your church cards with music:

```swift
// In your EnhancedChurchCard, add a section for service music
VStack(alignment: .leading, spacing: 16) {
    // ... existing church info ...
    
    if isExpanded {
        Divider()
        
        // Add this section
        VStack(alignment: .leading, spacing: 12) {
            Text("This Sunday's Music")
                .font(.custom("OpenSans-Bold", size: 16))
            
            CompactMusicPlayer(
                title: "Worship Set",
                searchQuery: "contemporary worship \(church.denomination)"
            )
        }
        
        // ... rest of expanded details ...
    }
}
```

### 2. Create a Prayer Tab/View

```swift
struct PrayerView: View {
    @State private var prayerText = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                Text("Prayer Room")
                    .font(.custom("OpenSans-Bold", size: 28))
                
                // Prayer music
                CompactMusicPlayer.prayerMusic
                    .padding(.horizontal)
                
                // Prayer input
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Prayer")
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    TextEditor(text: $prayerText)
                        .frame(height: 200)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                }
                .padding(.horizontal)
                
                // Submit button
                Button("Submit Prayer Request") {
                    // Handle prayer submission
                }
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                )
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
}
```

### 3. Add to Main TabView

Update your main `ContentView.swift`:

```swift
struct ContentView: View {
    var body: some View {
        TabView {
            // Home or Dashboard
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            // Find Church (existing)
            FindChurchView()
                .tabItem {
                    Label("Churches", systemImage: "building.2.fill")
                }
            
            // NEW: Worship Music
            WorshipMusicView()
                .tabItem {
                    Label("Worship", systemImage: "music.note.list")
                }
            
            // NEW: Prayer Room
            PrayerView()
                .tabItem {
                    Label("Prayer", systemImage: "hands.sparkles")
                }
            
            // Profile or Settings
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
    }
}
```

### 4. Add to Church Profile Sheet

When user taps on a church for details:

```swift
struct ChurchDetailSheet: View {
    let church: Church
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Church header with image
                    ZStack {
                        LinearGradient(
                            colors: church.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 200)
                        
                        VStack {
                            Spacer()
                            Text(church.name)
                                .font(.custom("OpenSans-Bold", size: 24))
                                .foregroundStyle(.white)
                                .padding()
                        }
                    }
                    
                    // Church details...
                    VStack(alignment: .leading, spacing: 20) {
                        // Address, phone, etc...
                        
                        // NEW: Worship music section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(.pink)
                                Text("Worship Music")
                                    .font(.custom("OpenSans-Bold", size: 20))
                            }
                            
                            Text("Prepare for this Sunday's service")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                            
                            CompactMusicPlayer(
                                title: "\(church.denomination) Worship",
                                searchQuery: "\(church.denomination) contemporary worship"
                            )
                        }
                        .padding()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```

### 5. Daily Devotional Integration

```swift
struct DevotionalView: View {
    let devotional: Devotional // Your devotional model
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Devotional title
                Text(devotional.title)
                    .font(.custom("OpenSans-Bold", size: 28))
                    .padding(.horizontal)
                
                // Devotional content
                Text(devotional.content)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .lineSpacing(8)
                    .padding(.horizontal)
                
                // Music for reflection
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "headphones")
                            .foregroundStyle(.purple)
                        Text("Reflect with Music")
                            .font(.custom("OpenSans-Bold", size: 18))
                    }
                    
                    CompactMusicPlayer.reflectionMusic
                }
                .padding(.horizontal)
                
                // Scripture reference, etc...
            }
            .padding(.vertical)
        }
    }
}
```

### 6. Live Service Experience

Create an immersive service view:

```swift
struct LiveServiceView: View {
    let church: Church
    @State private var isLive = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Live indicator
            if isLive {
                HStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("LIVE NOW")
                        .font(.custom("OpenSans-Bold", size: 12))
                        .foregroundStyle(.red)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
            }
            
            ScrollView {
                VStack(spacing: 24) {
                    // Service details
                    Text(church.name)
                        .font(.custom("OpenSans-Bold", size: 24))
                    
                    Text("Sunday Service • 10:00 AM")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.secondary)
                    
                    // Worship section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 24))
                                .foregroundStyle(.pink)
                            Text("Today's Worship Set")
                                .font(.custom("OpenSans-Bold", size: 20))
                        }
                        
                        CompactMusicPlayer(
                            title: "Service Music",
                            searchQuery: "contemporary worship uplifting"
                        )
                    }
                    .padding()
                    
                    // Sermon notes, etc...
                }
            }
        }
    }
}
```

### 7. Morning Devotional Notification Action

When user taps morning devotional notification:

```swift
struct MorningDevotionalView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Good Morning! 🌅")
                .font(.custom("OpenSans-Bold", size: 28))
            
            Text("Start your day with worship")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.secondary)
            
            // Preset morning worship playlist
            CompactMusicPlayer(
                title: "Morning Worship",
                searchQuery: "worship morning uplifting"
            )
            .padding()
            
            // Today's verse, prayer, etc...
        }
    }
}
```

## Quick Copy-Paste Examples

### Minimal Integration
```swift
// Just add this anywhere:
CompactMusicPlayer.prayerMusic
```

### With Custom Query
```swift
CompactMusicPlayer(
    title: "Your Title",
    searchQuery: "your search terms"
)
```

### All Presets Available
```swift
CompactMusicPlayer.prayerMusic        // Prayer & meditation
CompactMusicPlayer.worshipPrep        // Contemporary worship
CompactMusicPlayer.hymnPlayer         // Traditional hymns
CompactMusicPlayer.gospelMusic        // Gospel music
CompactMusicPlayer.reflectionMusic    // Quiet reflection
```

## Best Placement Ideas

1. ✅ **Church detail pages** - Show music for that denomination
2. ✅ **Prayer requests** - Background music while praying
3. ✅ **Daily devotionals** - Reflection soundtrack
4. ✅ **Service reminders** - Preview worship music
5. ✅ **Profile/Dashboard** - Quick access to worship
6. ✅ **Before check-in** - Prepare before attending service
7. ✅ **Quiet time tracking** - Music for Bible reading

## Remember

- Always check if user authorized MusicKit
- Provide fallback UI for non-authorized state
- Test with and without Apple Music subscription
- Use preview playback for non-subscribers
- Keep music queries relevant to context

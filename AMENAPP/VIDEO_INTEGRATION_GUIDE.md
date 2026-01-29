# Video Integration in SwiftUI - Guide

## ✅ More Books Added to Essential Books UI

**Enhanced from 8 to 30 books** including:

### New Additions by Category:

**Apologetics:**
- Evidence That Demands a Verdict - Josh McDowell
- The Reason for God - Timothy Keller

**Theology:**
- The Cost of Discipleship - Dietrich Bonhoeffer
- The Holiness of God - R.C. Sproul
- Systematic Theology - Wayne Grudem
- The Attributes of God - A.W. Pink & A.W. Tozer
- The Screwtape Letters - C.S. Lewis
- The Gospel According to Jesus - John MacArthur

**Devotional:**
- Crazy Love - Francis Chan
- The Pursuit of God - A.W. Tozer
- Celebration of Discipline - Richard Foster
- Humility - Andrew Murray
- Don't Waste Your Life - John Piper
- Absolute Surrender - Andrew Murray

**New Believer:**
- Radical - David Platt
- Boundaries - Henry Cloud
- Simply Christian - N.T. Wright
- Respectable Sins - Jerry Bridges

**Biography:**
- The Jesus I Never Knew - Philip Yancey
- Pilgrim's Progress - John Bunyan
- The Hiding Place - Corrie ten Boom

---

## 📹 About Adding Actual Videos

### Can SwiftUI Play Videos?

**Yes! SwiftUI can play videos using:**

1. **AVKit Framework** (Apple's native video player)
2. **VideoPlayer** (SwiftUI native component)
3. **AVPlayerViewController** (UIKit wrapped in SwiftUI)
4. **YouTube/Vimeo embeds** (via WebKit)

---

## 🎥 Implementation Options

### Option 1: Native VideoPlayer (Simplest)

```swift
import SwiftUI
import AVKit

struct BookVideoPreview: View {
    // Local video file
    let videoURL = Bundle.main.url(forResource: "book_trailer", withExtension: "mp4")!
    
    var body: some View {
        VideoPlayer(player: AVPlayer(url: videoURL))
            .frame(height: 200)
            .cornerRadius(12)
    }
}
```

**Pros:**
- ✅ Very simple
- ✅ Native controls
- ✅ Supports local and remote videos
- ✅ Picture-in-Picture support

**Cons:**
- ❌ Limited customization
- ❌ Takes up space when embedded

---

### Option 2: Custom AVPlayer with Controls

```swift
import SwiftUI
import AVKit

struct CustomVideoPlayer: View {
    @State private var player: AVPlayer
    @State private var isPlaying = false
    
    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }
    
    var body: some View {
        ZStack {
            VideoPlayer(player: player)
            
            // Custom overlay controls
            if !isPlaying {
                Button {
                    player.play()
                    isPlaying = true
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white)
                }
            }
        }
        .onDisappear {
            player.pause()
        }
    }
}
```

**Pros:**
- ✅ More control over UI
- ✅ Custom overlays
- ✅ Pause/play management

**Cons:**
- ❌ More code to manage
- ❌ Need to handle player lifecycle

---

### Option 3: YouTube/Vimeo Embed (Best for Online Content)

```swift
import SwiftUI
import WebKit

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    
    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let embedHTML = """
        <!DOCTYPE html>
        <html>
        <body style="margin:0;padding:0;">
        <iframe width="100%" height="100%" 
                src="https://www.youtube.com/embed/\(videoID)" 
                frameborder="0" 
                allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" 
                allowfullscreen>
        </iframe>
        </body>
        </html>
        """
        uiView.loadHTMLString(embedHTML, baseURL: nil)
    }
}

// Usage
YouTubePlayerView(videoID: "dQw4w9WgXcQ")
    .frame(height: 200)
```

**Pros:**
- ✅ No video hosting needed
- ✅ Works with YouTube/Vimeo
- ✅ Standard video controls
- ✅ Adaptive bitrate streaming

**Cons:**
- ❌ Requires internet
- ❌ Dependent on external service
- ❌ Ads may appear (YouTube)

---

## 🎬 Enhanced Book Card with Video

Here's how to add video previews to the Essential Books UI:

```swift
struct Book: Identifiable {
    let id = UUID()
    let title: String
    let author: String
    let description: String
    let category: String
    let rating: Int
    let coverColors: [Color]
    let videoURL: URL?  // ✨ New field
    let youtubeID: String?  // ✨ New field
}

struct EnhancedBookCard: View {
    let book: Book
    @State private var isSaved = false
    @State private var showVideoPreview = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Video Preview Section (tappable)
            if let videoURL = book.videoURL {
                Button {
                    showVideoPreview = true
                } label: {
                    ZStack {
                        // Thumbnail
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: book.coverColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 160)
                        
                        // Play button overlay
                        VStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.white)
                            
                            Text("Book Summary")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            
            // Rest of book card...
            HStack(spacing: 16) {
                // Book info
                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title)
                        .font(.custom("OpenSans-Bold", size: 16))
                    
                    Text("by \(book.author)")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .sheet(isPresented: $showVideoPreview) {
            if let videoURL = book.videoURL {
                VideoPlayerSheet(url: videoURL, title: book.title)
            }
        }
    }
}

struct VideoPlayerSheet: View {
    @Environment(\.dismiss) var dismiss
    let url: URL
    let title: String
    
    var body: some View {
        NavigationStack {
            VStack {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 300)
                
                Spacer()
            }
            .navigationTitle(title)
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
```

---

## 📦 Video Storage Options

### 1. **Bundle (Local Files)**
```swift
// Add .mp4 files to Xcode project
let url = Bundle.main.url(forResource: "book_preview", withExtension: "mp4")!
```

**Best for:**
- ✅ App demonstrations
- ✅ Offline functionality
- ✅ Small promotional videos

**Limitations:**
- ❌ Increases app size
- ❌ Not ideal for many videos
- ❌ Can't update without app update

### 2. **Remote URLs (Cloud Hosting)**
```swift
// Host on AWS S3, Firebase Storage, etc.
let url = URL(string: "https://yourserver.com/videos/book_summary.mp4")!
```

**Best for:**
- ✅ Many videos
- ✅ Large file sizes
- ✅ Updatable content
- ✅ Doesn't affect app size

**Requires:**
- ❌ Internet connection
- ❌ Hosting service
- ❌ Bandwidth costs

### 3. **YouTube/Vimeo**
```swift
YouTubePlayerView(videoID: "abc123xyz")
```

**Best for:**
- ✅ Free hosting
- ✅ Professional content
- ✅ Public videos
- ✅ CDN distribution

**Note:**
- ❌ Ads may appear (YouTube)
- ❌ Requires internet
- ❌ Platform dependency

---

## 🎯 Recommended Approach for Essential Books

### For Book Previews/Summaries:

```swift
// Add to Book model
struct Book: Identifiable {
    // ... existing fields ...
    let youtubeID: String?  // For book review videos
    let previewImageURL: String?  // For video thumbnail
}

// Example books with video reviews
Book(
    title: "Mere Christianity",
    author: "C.S. Lewis",
    description: "A classic defense of the Christian faith",
    category: "Apologetics",
    rating: 5,
    coverColors: [.blue, .indigo],
    youtubeID: "xyz123",  // Link to book review video
    previewImageURL: "https://img.youtube.com/vi/xyz123/maxresdefault.jpg"
)
```

---

## 💡 Smart Features to Add

### 1. **Video Thumbnail Preview**
Show a thumbnail instead of gradient - tappable to play

### 2. **Picture-in-Picture**
Allow videos to play while browsing other books

### 3. **Offline Download**
Save videos for offline viewing

### 4. **Auto-play Preview**
Muted video loops when scrolling into view

### 5. **Chapter Markers**
For longer book summaries, add chapters

---

## 🔧 Implementation Steps

### To Add Videos to Essential Books:

1. **Update Book Model**
```swift
struct Book: Identifiable {
    // ... existing ...
    let videoURL: URL?
    let videoDuration: String?  // "5:32"
    let hasVideo: Bool { videoURL != nil }
}
```

2. **Update UI**
- Add video preview section to BookCard
- Add play button overlay
- Add video duration badge

3. **Add Video Player Sheet**
- Full-screen video player
- Done button
- Playback controls

4. **Host Videos**
- Upload to YouTube (free)
- Or use Firebase Storage
- Or AWS S3
- Or bundle small previews

---

## 📝 Next Steps

**To implement videos:**

1. Choose hosting (YouTube recommended for books)
2. Create/find book review videos
3. Update Book model with video IDs
4. Add video preview UI to BookCard
5. Implement video player sheet
6. Test playback on device

**Estimated effort:** 2-4 hours for full implementation

---

## ⚠️ Important Considerations

### Performance:
- Don't autoplay multiple videos
- Use thumbnails, not live video previews
- Lazy load video players
- Pause videos when scrolling away

### App Store Guidelines:
- Videos must follow content guidelines
- Age-appropriate content only
- Proper copyright permissions
- No misleading previews

### User Experience:
- Always show video duration
- Provide pause/play controls
- Support landscape orientation
- Handle background audio properly

---

**Status:** ✅ Books expanded to 30 items  
**Video Support:** Ready to implement when needed  
**Recommended:** YouTube embeds for book reviews/summaries

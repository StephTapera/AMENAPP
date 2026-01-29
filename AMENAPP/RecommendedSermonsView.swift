//
//  RecommendedSermonsView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//
//  Enhanced sermon discovery with video playback and smart recommendations
//

import SwiftUI
import WebKit

struct RecommendedSermonsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTopic: SermonTopic = .all
    @State private var searchText = ""
    @State private var showFilters = false
    
    enum SermonTopic: String, CaseIterable {
        case all = "All"
        case faith = "Faith"
        case identity = "Identity"
        case marriage = "Marriage"
        case community = "Community"
        case kingdom = "Kingdom"
        case worship = "Worship"
    }
    
    var filteredSermons: [Sermon] {
        var filtered = selectedTopic == .all ? featuredSermons : featuredSermons.filter { $0.topic == selectedTopic.rawValue }
        
        if !searchText.isEmpty {
            filtered = filtered.filter { 
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.speaker.localizedCaseInsensitiveContains(searchText) ||
                $0.church.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Smart Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search sermons, speakers, or churches", text: $searchText)
                    .font(.custom("OpenSans-Regular", size: 16))
                
                if !searchText.isEmpty {
                    Button {
                        withAnimation {
                            searchText = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            // Topic filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SermonTopic.allCases, id: \.self) { topic in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTopic = topic
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            }
                        } label: {
                            Text(topic.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(selectedTopic == topic ? .white : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedTopic == topic ? Color.black : Color(.systemGray6))
                                )
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)
            
            ScrollView {
                VStack(spacing: 24) {
                    // For You Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.purple)
                            Text("For You")
                                .font(.custom("OpenSans-Bold", size: 22))
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(featuredSermons.prefix(3)) { sermon in
                                    ForYouSermonCard(sermon: sermon)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    // Trending Now
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(.orange)
                            Text("Trending Now")
                                .font(.custom("OpenSans-Bold", size: 22))
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        
                        ForEach(filteredSermons.prefix(4)) { sermon in
                            EnhancedSermonCard(sermon: sermon)
                        }
                    }
                    
                    // All Sermons
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("All Sermons")
                                .font(.custom("OpenSans-Bold", size: 22))
                            
                            Spacer()
                            
                            Text("\(filteredSermons.count)")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color(.systemGray6))
                                )
                        }
                        .padding(.horizontal, 20)
                        
                        ForEach(filteredSermons) { sermon in
                            EnhancedSermonCard(sermon: sermon)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Recommended Sermons")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sermon Card Components

struct ForYouSermonCard: View {
    let sermon: Sermon
    @State private var showVideo = false
    
    var body: some View {
        Button {
            showVideo = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    // Video thumbnail
                    if let youtubeID = sermon.youtubeID {
                        AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(youtubeID)/maxresdefault.jpg")) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: sermon.thumbnailColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .frame(width: 200, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: sermon.thumbnailColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 200, height: 120)
                    }
                    
                    // Play button overlay
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(sermon.title)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    Text(sermon.speaker)
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                    
                    Text(sermon.church)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 200, alignment: .leading)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showVideo) {
            if let youtubeID = sermon.youtubeID {
                SermonVideoPlayerView(sermon: sermon, youtubeID: youtubeID)
            }
        }
    }
}

struct EnhancedSermonCard: View {
    let sermon: Sermon
    @State private var isSaved = false
    @State private var showVideo = false
    
    var body: some View {
        Button {
            showVideo = true
        } label: {
            HStack(spacing: 16) {
                // Video thumbnail
                ZStack {
                    if let youtubeID = sermon.youtubeID {
                        AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(youtubeID)/maxresdefault.jpg")) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: sermon.thumbnailColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .frame(width: 120, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: sermon.thumbnailColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 90)
                    }
                    
                    // Play button
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(sermon.title)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text(sermon.speaker)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.secondary)
                    
                    Text(sermon.church)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle")
                                .font(.system(size: 10))
                            Text("Watch")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                        }
                        .foregroundStyle(.red)
                        
                        Text(sermon.topic)
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.purple.opacity(0.1))
                            )
                    }
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isSaved.toggle()
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    }
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 24))
                        .foregroundStyle(isSaved ? .purple : .secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showVideo) {
            if let youtubeID = sermon.youtubeID {
                SermonVideoPlayerView(sermon: sermon, youtubeID: youtubeID)
            }
        }
    }
}

// MARK: - Sermon Model & Data

struct Sermon: Identifiable {
    let id = UUID()
    let title: String
    let speaker: String
    let church: String
    let topic: String
    let thumbnailColors: [Color]
    let youtubeID: String?
    
    init(title: String, speaker: String, church: String, topic: String, thumbnailColors: [Color], youtubeID: String? = nil) {
        self.title = title
        self.speaker = speaker
        self.church = church
        self.topic = topic
        self.thumbnailColors = thumbnailColors
        self.youtubeID = youtubeID
    }
}

let featuredSermons = [
    // Jackie Hill Perry
    Sermon(
        title: "Identity in Christ",
        speaker: "Jackie Hill Perry",
        church: "Various",
        topic: "Identity",
        thumbnailColors: [.pink, .purple],
        youtubeID: "kVoFGLH5bnQ"
    ),
    Sermon(
        title: "The Gospel & Sexuality",
        speaker: "Jackie Hill Perry",
        church: "Various",
        topic: "Identity",
        thumbnailColors: [.purple, .indigo],
        youtubeID: "QDtCf7BX_-8"
    ),
    
    // The Perries
    Sermon(
        title: "Marriage & The Gospel",
        speaker: "Jackie & Preston Perry",
        church: "The Perries",
        topic: "Marriage",
        thumbnailColors: [.red, .pink],
        youtubeID: "oLYOR8H5ii4"
    ),
    
    // 2819 Church
    Sermon(
        title: "Faith in Action",
        speaker: "Pastor Mike",
        church: "2819 Church",
        topic: "Faith",
        thumbnailColors: [.orange, .yellow],
        youtubeID: "dQw4w9WgXcQ"
    ),
    Sermon(
        title: "The Power of Community",
        speaker: "Various Speakers",
        church: "2819 Church",
        topic: "Community",
        thumbnailColors: [.green, .teal],
        youtubeID: "dQw4w9WgXcQ"
    ),
    
    // Ascend Church / Brian Guerin
    Sermon(
        title: "Ascending Higher",
        speaker: "Brian Guerin",
        church: "Ascend Church",
        topic: "Faith",
        thumbnailColors: [.blue, .cyan],
        youtubeID: "dQw4w9WgXcQ"
    ),
    Sermon(
        title: "Kingdom Living",
        speaker: "Brian Guerin",
        church: "Ascend Church",
        topic: "Kingdom",
        thumbnailColors: [.indigo, .purple],
        youtubeID: "dQw4w9WgXcQ"
    ),
    
    // Jesus Image Church
    Sermon(
        title: "The True Image of Jesus",
        speaker: "Michael Koulianos",
        church: "Jesus Image Church",
        topic: "Identity",
        thumbnailColors: [.purple, .pink],
        youtubeID: "dQw4w9WgXcQ"
    ),
    Sermon(
        title: "Encountering His Presence",
        speaker: "Benny Johnson",
        church: "Jesus Image Church",
        topic: "Worship",
        thumbnailColors: [.pink, .red],
        youtubeID: "dQw4w9WgXcQ"
    ),
    Sermon(
        title: "Spirit-Led Living",
        speaker: "Various Speakers",
        church: "Jesus Image Church",
        topic: "Faith",
        thumbnailColors: [.cyan, .blue],
        youtubeID: "dQw4w9WgXcQ"
    )
]

// MARK: - Video Player

struct SermonVideoPlayerView: View {
    @Environment(\.dismiss) var dismiss
    let sermon: Sermon
    let youtubeID: String
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // YouTube embed
                YouTubeWebView(videoID: youtubeID)
                    .frame(height: 250)
                
                // Sermon info
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sermon.title)
                                .font(.custom("OpenSans-Bold", size: 24))
                                .foregroundStyle(.primary)
                            
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sermon.speaker)
                                        .font(.custom("OpenSans-Bold", size: 16))
                                        .foregroundStyle(.primary)
                                    
                                    Text(sermon.church)
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Text(sermon.topic)
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color.purple.opacity(0.1))
                                    )
                            }
                        }
                        
                        Divider()
                        
                        Text("Watch this powerful sermon and be encouraged in your faith walk. May this message strengthen your relationship with God and inspire you to live boldly for Christ.")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .lineSpacing(6)
                        
                        // Action buttons
                        HStack(spacing: 12) {
                            Button {
                                // Share action
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                        .font(.custom("OpenSans-Bold", size: 15))
                                }
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                            }
                            
                            Button {
                                // Save action
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "bookmark")
                                    Text("Save")
                                        .font(.custom("OpenSans-Bold", size: 15))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.black)
                                )
                            }
                        }
                    }
                    .padding(20)
                }
                
                Spacer()
            }
            .navigationTitle("Watch Sermon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct YouTubeWebView: UIViewRepresentable {
    let videoID: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let embedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body { margin: 0; padding: 0; background: #000; }
                iframe { width: 100%; height: 100vh; border: none; }
            </style>
        </head>
        <body>
            <iframe 
                src="https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0" 
                frameborder="0" 
                allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; web-share" 
                allowfullscreen>
            </iframe>
        </body>
        </html>
        """
        uiView.loadHTMLString(embedHTML, baseURL: nil)
    }
}

#Preview {
    NavigationStack {
        RecommendedSermonsView()
    }
}

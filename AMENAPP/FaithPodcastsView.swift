//
//  FaithPodcastsView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//
//  Enhanced podcast discovery with smart recommendations and rich features
//

import SwiftUI

struct FaithPodcastsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedGenre: PodcastGenre = .all
    @State private var searchText = ""
    @State private var showPlayer = false
    @State private var selectedPodcast: Podcast?
    @State private var playingEpisode: PodcastEpisode?
    @State private var isPlaying = false
    @State private var showFilters = false
    
    enum PodcastGenre: String, CaseIterable {
        case all = "All"
        case teaching = "Teaching"
        case devotional = "Devotional"
        case testimonies = "Testimonies"
        case youngAdults = "Young Adults"
        case family = "Family"
        case apologetics = "Apologetics"
    }
    
    var filteredPodcasts: [Podcast] {
        let filtered = selectedGenre == .all ? faithPodcasts : faithPodcasts.filter { $0.genre == selectedGenre.rawValue }
        
        if searchText.isEmpty {
            return filtered
        }
        return filtered.filter { 
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.host.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Custom Header
                VStack(spacing: 16) {
                    HStack {
                        // Liquid Glass X button
                        Button {
                            dismiss()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                LinearGradient(
                                                    colors: [
                                                        Color.white.opacity(0.3),
                                                        Color.white.opacity(0.1)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                                
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(LiquidGlassButtonStyle())
                        
                        Spacer()
                        
                        Text("Faith Podcasts")
                            .font(.custom("OpenSans-Bold", size: 18))
                        
                        Spacer()
                        
                        Button {
                            showFilters = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    // Smart Search bar with liquid glass
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        
                        TextField("Search podcasts or hosts", text: $searchText)
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
                }
                .background(Color(.systemBackground))
                
                // Genre filter with liquid glass pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PodcastGenre.allCases, id: \.self) { genre in
                            GenreChip(
                                title: genre.rawValue,
                                isSelected: selectedGenre == genre
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedGenre = genre
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 12)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // For You Section - Personalized
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
                                    ForEach(faithPodcasts.prefix(4)) { podcast in
                                        ForYouPodcastCard(podcast: podcast) {
                                            selectedPodcast = podcast
                                        }
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
                            
                            ForEach(filteredPodcasts.prefix(3)) { podcast in
                                EnhancedPodcastCard(podcast: podcast) {
                                    selectedPodcast = podcast
                                } onPlay: { episode in
                                    playingEpisode = episode
                                    isPlaying = true
                                    showPlayer = true
                                }
                            }
                        }
                        
                        // All Podcasts
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("All Podcasts")
                                    .font(.custom("OpenSans-Bold", size: 22))
                                
                                Spacer()
                                
                                Text("\(filteredPodcasts.count)")
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
                            
                            ForEach(filteredPodcasts) { podcast in
                                EnhancedPodcastCard(podcast: podcast) {
                                    selectedPodcast = podcast
                                } onPlay: { episode in
                                    playingEpisode = episode
                                    isPlaying = true
                                    showPlayer = true
                                }
                            }
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.bottom, showPlayer ? 80 : 0)
                }
            }
            
            // Mini Player
            if showPlayer, let episode = playingEpisode {
                MiniPlayer(
                    episode: episode,
                    isPlaying: $isPlaying,
                    onTap: {
                        // Show full player
                    },
                    onClose: {
                        withAnimation {
                            showPlayer = false
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $selectedPodcast) { podcast in
            PodcastDetailView(podcast: podcast)
        }
        .sheet(isPresented: $showFilters) {
            FiltersSheet()
        }
    }
}

struct TrendingPodcastCard: View {
    let podcast: Podcast
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: podcast.coverColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 180, height: 180)
                
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.title)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                Text(podcast.host)
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 4) {
                    Image(systemName: "headphones")
                        .font(.system(size: 10))
                    Text("\(podcast.episodes) episodes")
                        .font(.custom("OpenSans-Regular", size: 11))
                }
                .foregroundStyle(.secondary)
            }
            .frame(width: 180)
        }
    }
}

struct PodcastCard: View {
    let podcast: Podcast
    @State private var isSubscribed = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Podcast cover
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: podcast.coverColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "waveform")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(podcast.title)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                Text(podcast.host)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "headphones")
                            .font(.system(size: 10))
                        Text("\(podcast.episodes) episodes")
                            .font(.custom("OpenSans-Regular", size: 12))
                    }
                    .foregroundStyle(.secondary)
                    
                    Text(podcast.genre)
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
                    isSubscribed.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isSubscribed ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .bold))
                    
                    if !isSubscribed {
                        Text("Follow")
                            .font(.custom("OpenSans-Bold", size: 14))
                    }
                }
                .foregroundStyle(isSubscribed ? .green : .white)
                .padding(.horizontal, isSubscribed ? 12 : 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSubscribed ? Color.green.opacity(0.1) : Color.black)
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
    }
}

struct Podcast: Identifiable {
    let id = UUID()
    let title: String
    let host: String
    let genre: String
    let episodes: Int
    let coverColors: [Color]
}

let faithPodcasts = [
    Podcast(
        title: "The Bible Project",
        host: "Tim Mackie & Jon Collins",
        genre: "Teaching",
        episodes: 450,
        coverColors: [.blue, .cyan]
    ),
    Podcast(
        title: "Daily Hope",
        host: "Rick Warren",
        genre: "Devotional",
        episodes: 1200,
        coverColors: [.green, .teal]
    ),
    Podcast(
        title: "The Gospel Coalition",
        host: "Various Speakers",
        genre: "Teaching",
        episodes: 800,
        coverColors: [.orange, .red]
    ),
    Podcast(
        title: "Jesus Calling",
        host: "Sarah Young",
        genre: "Devotional",
        episodes: 365,
        coverColors: [.purple, .pink]
    ),
    Podcast(
        title: "Real Faith Stories",
        host: "Faith Community",
        genre: "Testimonies",
        episodes: 250,
        coverColors: [.indigo, .blue]
    ),
    Podcast(
        title: "Young & Seeking",
        host: "Youth Ministry Team",
        genre: "Young Adults",
        episodes: 180,
        coverColors: [.pink, .orange]
    ),
    Podcast(
        title: "Faith & Family",
        host: "Focus on the Family",
        genre: "Family",
        episodes: 500,
        coverColors: [.teal, .green]
    ),
    Podcast(
        title: "Reasonable Faith",
        host: "William Lane Craig",
        genre: "Apologetics",
        episodes: 320,
        coverColors: [.red, .purple]
    ),
    Podcast(
        title: "Every Day Prayers",
        host: "John Eldredge",
        genre: "Devotional",
        episodes: 90,
        coverColors: [.cyan, .blue]
    ),
    Podcast(
        title: "Truth Over Tradition",
        host: "Mike Winger",
        genre: "Teaching",
        episodes: 400,
        coverColors: [.orange, .yellow]
    )
]

// MARK: - Supporting Components

struct GenreChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.black : Color(.systemGray6))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ForYouPodcastCard: View {
    let podcast: Podcast
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: podcast.coverColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 160, height: 160)
                    
                    Image(systemName: "waveform")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.3))
                    
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                                .padding(12)
                        }
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(podcast.title)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    Text(podcast.host)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 160, alignment: .leading)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EnhancedPodcastCard: View {
    let podcast: Podcast
    let onTap: () -> Void
    let onPlay: (PodcastEpisode) -> Void
    
    @State private var isSubscribed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Podcast cover with gradient
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: podcast.coverColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 90, height: 90)
                    
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(podcast.title)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    Text(podcast.host)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "headphones")
                                .font(.system(size: 10))
                            Text("\(podcast.episodes) eps")
                                .font(.custom("OpenSans-Regular", size: 12))
                        }
                        .foregroundStyle(.secondary)
                        
                        Text(podcast.genre)
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.purple.opacity(0.1))
                            )
                    }
                    
                    // Latest episode preview
                    Button {
                        let episode = PodcastEpisode(
                            title: "Latest Episode",
                            podcastTitle: podcast.title,
                            duration: "45:00",
                            date: Date()
                        )
                        onPlay(episode)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 14))
                            Text("Play Latest")
                                .font(.custom("OpenSans-Bold", size: 13))
                        }
                        .foregroundStyle(.purple)
                    }
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isSubscribed.toggle()
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    }
                } label: {
                    Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(isSubscribed ? .green : .primary.opacity(0.5))
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
    }
}

struct PodcastEpisode: Identifiable {
    let id = UUID()
    let title: String
    let podcastTitle: String
    let duration: String
    let date: Date
}

struct MiniPlayer: View {
    let episode: PodcastEpisode
    @Binding var isPlaying: Bool
    let onTap: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Animated waveform
                HStack(spacing: 3) {
                    ForEach(0..<4) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.purple)
                            .frame(width: 3, height: isPlaying ? CGFloat.random(in: 12...24) : 12)
                            .animation(
                                isPlaying ? .easeInOut(duration: 0.5).repeatForever() : .default,
                                value: isPlaying
                            )
                    }
                }
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.1))
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(episode.podcastTitle)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPlaying.toggle()
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 12, y: -4)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PodcastDetailView: View {
    let podcast: Podcast
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
                VStack(spacing: 24) {
                    // Large podcast artwork
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: podcast.coverColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 240, height: 240)
                        
                        Image(systemName: "waveform")
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                    .padding(.top, 32)
                    
                    VStack(spacing: 12) {
                        Text(podcast.title)
                            .font(.custom("OpenSans-Bold", size: 28))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text(podcast.host)
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Image(systemName: "headphones")
                                    .font(.system(size: 12))
                                Text("\(podcast.episodes) episodes")
                                    .font(.custom("OpenSans-Regular", size: 14))
                            }
                            
                            Text(podcast.genre)
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.purple.opacity(0.1))
                                )
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 32)
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            // Subscribe action
                        } label: {
                            Text("Subscribe")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.black)
                                )
                        }
                        
                        Button {
                            // Share action
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                                .foregroundStyle(.primary)
                                .frame(width: 50, height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About")
                            .font(.custom("OpenSans-Bold", size: 18))
                        
                        Text("Discover engaging faith-based content with \(podcast.title). Join \(podcast.host) as they explore scripture, theology, and practical Christian living.")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    
                    // Recent episodes placeholder
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Episodes")
                            .font(.custom("OpenSans-Bold", size: 18))
                            .padding(.horizontal, 32)
                        
                        ForEach(0..<5) { index in
                            EpisodeRow(episodeNumber: index + 1)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .safeAreaInset(edge: .top) {
                // Custom header with dismiss button
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 36, height: 36)
                                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(LiquidGlassButtonStyle())
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                )
            }
        }
    }


struct EpisodeRow: View {
    let episodeNumber: Int
    
    var body: some View {
        HStack(spacing: 16) {
            // Episode artwork thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary.opacity(0.6))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Episode \(episodeNumber): Faith in Action")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                Text("45 min • 3 days ago")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                // Play episode
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.purple)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 8)
    }
}

struct FiltersSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var sortBy = "Most Popular"
    @State private var duration = "All"
    @State private var showExplicitContent = false
    
    let sortOptions = ["Most Popular", "Newest", "A-Z", "Most Episodes"]
    let durationOptions = ["All", "Under 30 min", "30-60 min", "Over 60 min"]
    
    var body: some View {
        Form {
                Section("Sort By") {
                    ForEach(sortOptions, id: \.self) { option in
                        Button {
                            sortBy = option
                        } label: {
                            HStack {
                                Text(option)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if sortBy == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.purple)
                                }
                            }
                        }
                    }
                }
                
                Section("Episode Duration") {
                    ForEach(durationOptions, id: \.self) { option in
                        Button {
                            duration = option
                        } label: {
                            HStack {
                                Text(option)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if duration == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.purple)
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Toggle("Show Explicit Content", isOn: $showExplicitContent)
                }
                
                Section {
                    Button {
                        // Reset filters
                        sortBy = "Most Popular"
                        duration = "All"
                        showExplicitContent = false
                    } label: {
                        Text("Reset All Filters")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                // Custom header
                HStack {
                    Text("Filters")
                        .font(.custom("OpenSans-Bold", size: 20))
                    
                    Spacer()
                    
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-Bold", size: 16))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    Rectangle()
                        .fill(Color(.systemBackground))
                        .ignoresSafeArea()
                )
            }
        }
    }


// MARK: - Button Style

private struct LiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    FaithPodcastsView()
}

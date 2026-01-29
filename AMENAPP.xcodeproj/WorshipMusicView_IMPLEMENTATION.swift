//
//  WorshipMusicView.swift
//  AMENAPP
//
//  Simple worship music view - Copy this entire file
//

import SwiftUI
import MusicKit

struct WorshipMusicView: View {
    @StateObject private var musicManager = MusicKitManager.shared
    @State private var searchText = ""
    @State private var searchResults: [Song] = []
    @State private var showAuthAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(white: 0.98)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Image(systemName: "music.note.list")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.pink)
                                    
                                    Text("Worship Music")
                                        .font(.custom("OpenSans-Bold", size: 28))
                                }
                                
                                Text("Discover worship songs and hymns")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        
                        // Search bar
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            
                            TextField("Search worship songs...", text: $searchText)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .onSubmit {
                                    performSearch()
                                }
                            
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                    searchResults = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.systemGray6))
                        )
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 8)
                    
                    // Authorization Banner
                    if !musicManager.isAuthorized {
                        AuthBanner {
                            requestAuth()
                        }
                    }
                    
                    // Now Playing
                    if let song = musicManager.currentSong {
                        NowPlayingBar(
                            song: song,
                            isPlaying: musicManager.isPlaying,
                            onPlayPause: togglePlay,
                            onStop: stopMusic
                        )
                    }
                    
                    // Content
                    if musicManager.isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !searchResults.isEmpty {
                        SongsList(songs: searchResults, onTap: playSong)
                    } else if !musicManager.worshipSongs.isEmpty {
                        SongsList(songs: musicManager.worshipSongs, onTap: playSong)
                    } else {
                        EmptyView(isAuthorized: musicManager.isAuthorized) {
                            loadInitial()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                if musicManager.isAuthorized && musicManager.worshipSongs.isEmpty {
                    loadInitial()
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func requestAuth() {
        Task {
            let granted = await musicManager.requestAuthorization()
            if granted {
                loadInitial()
            }
        }
    }
    
    private func loadInitial() {
        Task {
            do {
                _ = try await musicManager.fetchPopularWorshipSongs()
            } catch {
                print("❌ Failed: \(error)")
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        Task {
            do {
                searchResults = try await musicManager.searchWorshipMusic(query: searchText)
            } catch {
                print("❌ Search failed: \(error)")
            }
        }
    }
    
    private func playSong(_ song: Song) {
        Task {
            do {
                try await musicManager.playSong(song)
            } catch {
                print("❌ Play failed: \(error)")
            }
        }
    }
    
    private func togglePlay() {
        Task {
            do {
                if musicManager.isPlaying {
                    musicManager.pause()
                } else {
                    try await musicManager.resume()
                }
            } catch {
                print("❌ Toggle failed: \(error)")
            }
        }
    }
    
    private func stopMusic() {
        musicManager.stop()
    }
}

// MARK: - Auth Banner
struct AuthBanner: View {
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(.pink))
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Connect Apple Music")
                    .font(.custom("OpenSans-Bold", size: 16))
                
                Text("Access worship music and hymns")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                action()
            } label: {
                Text("Connect")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.pink))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Songs List
struct SongsList: View {
    let songs: [Song]
    let onTap: (Song) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(songs, id: \.id) { song in
                    SimpleSongCard(song: song) {
                        onTap(song)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Simple Song Card
struct SimpleSongCard: View {
    let song: Song
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Artwork
                if let artwork = song.artwork {
                    ArtworkImage(artwork, width: 60)
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.pink)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(.white)
                        )
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.title)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(song.artistName)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.pink)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Now Playing Bar
struct NowPlayingBar: View {
    let song: Song
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onStop: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if let artwork = song.artwork {
                ArtworkImage(artwork, width: 50)
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .lineLimit(1)
                
                Text(song.artistName)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.pink)
                }
                
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 12, y: -4)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

// MARK: - Empty View
struct EmptyView: View {
    let isAuthorized: Bool
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(.pink)
            
            Text(isAuthorized ? "Discover Worship Music" : "Connect Apple Music")
                .font(.custom("OpenSans-Bold", size: 22))
            
            Text(isAuthorized ? "Search for worship songs" : "Authorization required")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
            
            if isAuthorized {
                Button(action: action) {
                    Text("Get Started")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(.pink))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    WorshipMusicView()
}

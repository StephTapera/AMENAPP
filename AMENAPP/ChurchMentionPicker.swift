//
//  ChurchMentionPicker.swift
//  AMENAPP
//
//  @church mention picker for composer
//  Autocomplete search for nearby churches
//

import SwiftUI
import CoreLocation
import Combine

struct ChurchMentionPicker: View {
    @Binding var searchQuery: String
    @Binding var isPresented: Bool
    let userLocation: CLLocation?
    let onSelect: (ChurchEntity) -> Void
    
    @StateObject private var viewModel = ChurchMentionViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                
                TextField("Search churches...", text: $searchQuery)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            
            Divider()
            
            // Results
            ScrollView {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.top, 40)
                        Spacer()
                    }
                } else if viewModel.results.isEmpty && !searchQuery.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "building.columns")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        
                        Text("No churches found")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                        
                        Text("Try searching by church name")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.results) { result in
                            ChurchSearchResultRow(result: result) {
                                if let church = result.church {
                                    onSelect(church)
                                    isPresented = false
                                } else {
                                    // Create from Google Places result
                                    Task {
                                        if let newChurch = await viewModel.createChurchFromResult(result) {
                                            onSelect(newChurch)
                                            isPresented = false
                                        }
                                    }
                                }
                            }
                            
                            if result.id != viewModel.results.last?.id {
                                Divider()
                                    .padding(.leading, 68)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .onChange(of: searchQuery) { oldValue, newValue in
            Task {
                await viewModel.search(query: newValue, location: userLocation)
            }
        }
        .task {
            // Load nearby churches on appear
            if let location = userLocation {
                await viewModel.loadNearby(location: location)
            }
        }
    }
}

// MARK: - View Model

@MainActor
class ChurchMentionViewModel: ObservableObject {
    @Published var results: [ChurchSearchResult] = []
    @Published var isLoading = false
    
    private let service = ChurchDataService.shared
    private var searchTask: Task<Void, Never>?
    
    func search(query: String, location: CLLocation?) async {
        // Cancel previous search
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            // Show nearby if no query
            if let location = location {
                await loadNearby(location: location)
            }
            return
        }
        
        isLoading = true
        
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                guard !Task.isCancelled else { return }
                
                if let location = location {
                    let searchResults = try await service.searchChurches(
                        query: query,
                        near: location,
                        radius: 25.0
                    )
                    
                    guard !Task.isCancelled else { return }
                    results = searchResults
                }
            } catch {
                dlog("⚠️ Church search failed: \(error)")
            }
            
            isLoading = false
        }
    }
    
    func loadNearby(location: CLLocation) async {
        isLoading = true
        
        do {
            // Get top 10 nearest churches
            let searchResults = try await service.searchChurches(
                query: "",
                near: location,
                radius: 10.0
            )
            results = Array(searchResults.prefix(10))
        } catch {
            dlog("⚠️ Failed to load nearby churches: \(error)")
        }
        
        isLoading = false
    }
    
    func createChurchFromResult(_ result: ChurchSearchResult) async -> ChurchEntity? {
        // If church has placeId, try to fetch full details
        guard let placeId = result.placeId else { return nil }
        
        do {
            return try await service.getOrCreateChurch(placeId: placeId)
        } catch {
            dlog("⚠️ Failed to create church: \(error)")
            return nil
        }
    }
}

// MARK: - Text Field with Church Mentions

struct ChurchMentionTextField: View {
    @Binding var text: String
    @Binding var churchMentions: [ChurchMention]
    let placeholder: String
    let userLocation: CLLocation?
    
    @State private var showChurchPicker = false
    @State private var churchSearchQuery = ""
    @State private var currentMentionRange: NSRange?
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .font(.custom("OpenSans-Regular", size: 16))
                .frame(minHeight: 100)
                .focused($isFocused)
                .onChange(of: text) { oldValue, newValue in
                    detectChurchMention(in: newValue)
                }
            
            // Display mentioned churches as pills
            if !churchMentions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(churchMentions) { mention in
                            churchMentionChip(mention)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .sheet(isPresented: $showChurchPicker) {
            NavigationView {
                ChurchMentionPicker(
                    searchQuery: $churchSearchQuery,
                    isPresented: $showChurchPicker,
                    userLocation: userLocation,
                    onSelect: { church in
                        insertChurchMention(church)
                    }
                )
                .navigationTitle("Tag Church")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Cancel") {
                            showChurchPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
    
    private func churchMentionChip(_ mention: ChurchMention) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 10))
                .foregroundStyle(.blue)
            
            Text(mention.name)
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundStyle(.blue)
            
            Button {
                removeChurchMention(mention)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func detectChurchMention(in text: String) {
        // Look for @church pattern
        if text.hasSuffix("@church") || text.contains("@church ") {
            churchSearchQuery = ""
            showChurchPicker = true
        }
    }
    
    private func insertChurchMention(_ church: ChurchEntity) {
        // Replace @church with church name
        let mentionText = "@\(church.name)"
        
        if let range = text.range(of: "@church") {
            text.replaceSubrange(range, with: mentionText)
        } else {
            text += " \(mentionText)"
        }
        
        // Add to mentions array
        let mention = ChurchMention(
            id: UUID().uuidString,
            churchId: church.id,
            name: church.name,
            city: church.city,
            range: NSRange(location: 0, length: 0) // Will be calculated when saving
        )
        
        churchMentions.append(mention)
    }
    
    private func removeChurchMention(_ mention: ChurchMention) {
        // Remove from text
        text = text.replacingOccurrences(of: "@\(mention.name)", with: "")
        
        // Remove from array
        churchMentions.removeAll { $0.id == mention.id }
    }
}

// MARK: - Preview

#Preview {
    ChurchMentionPicker(
        searchQuery: .constant(""),
        isPresented: .constant(true),
        userLocation: CLLocation(latitude: 40.7128, longitude: -74.0060),
        onSelect: { _ in }
    )
}

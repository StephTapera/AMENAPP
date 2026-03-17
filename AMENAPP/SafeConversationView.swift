//
//  SafeConversationView.swift
//  AMENAPP
//
//  Safe Conversation Mode settings UI
//  Protects vulnerable users from harmful messages
//

import SwiftUI
import FirebaseAuth
import Combine

struct SafeConversationView: View {
    @StateObject private var viewModel = SafeConversationViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header explanation
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 32))
                                .foregroundStyle(.green)
                            
                            Text("Safe Conversation Mode")
                                .font(.custom("OpenSans-Bold", size: 24))
                        }
                        
                        Text("Protect yourself from harmful messages when you're vulnerable. Messages from non-trusted accounts won't interrupt you.")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    // Auto-enabled notice
                    if let autoUntil = viewModel.autoEnabledUntil, autoUntil > Date() {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Auto-Enabled")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                
                                Text("AMEN enabled Safe Mode to help protect you. It will automatically turn off on \(autoUntil.formatted(date: .abbreviated, time: .shortened)).")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                    }
                    
                    // Enable toggle
                    Toggle(isOn: $viewModel.isEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Safe Mode")
                                .font(.custom("OpenSans-SemiBold", size: 17))
                            
                            Text("Filter or redirect messages from non-trusted users")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    
                    if viewModel.isEnabled {
                        // Protection Level
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Protection Level")
                                .font(.custom("OpenSans-SemiBold", size: 17))
                                .padding(.horizontal, 20)
                            
                            ForEach([
                                SafeConversationSettings.SafeMode.requestsOnly,
                                SafeConversationSettings.SafeMode.filtered,
                                SafeConversationSettings.SafeMode.lockdown
                            ], id: \.self) { mode in
                                SafeModeCard(
                                    mode: mode,
                                    isSelected: viewModel.mode == mode,
                                    onSelect: {
                                        viewModel.mode = mode
                                    }
                                )
                            }
                        }
                        
                        Divider()
                            .padding(.horizontal, 20)
                        
                        // Additional Options
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Additional Options")
                                .font(.custom("OpenSans-SemiBold", size: 17))
                                .padding(.horizontal, 20)
                            
                            Toggle(isOn: $viewModel.enableKindnessFilter) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Kindness Filter")
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                    
                                    Text("Hide potentially harmful messages locally")
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.green)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                            
                            Toggle(isOn: $viewModel.showSupportiveReplies) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Supportive Reply Suggestions")
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                    
                                    Text("Show quick replies for friends checking in")
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.green)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                        }
                        
                        Divider()
                            .padding(.horizontal, 20)
                        
                        // Trusted Users
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Trusted Users")
                                    .font(.custom("OpenSans-SemiBold", size: 17))
                                
                                Spacer()
                                
                                Text("\(viewModel.trustedUserIds.count)")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 20)
                            
                            Text("Messages from these users will always come through, even in Safe Mode.")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)
                            
                            Button {
                                // TODO: Show user picker
                                viewModel.showAddTrusted = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                    
                                    Text("Add Trusted User")
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                }
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(12)
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Safe Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        Task {
                            await viewModel.save()
                        }
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $viewModel.showAddTrusted) {
            TrustedUserPickerView { userId in
                viewModel.trustedUserIds.insert(userId)
            }
        }
    }
}

// MARK: - Safe Mode Card

struct SafeModeCard: View {
    let mode: SafeConversationSettings.SafeMode
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .green : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text(mode.description)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.green.opacity(0.1) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

// MARK: - View Model

@MainActor
class SafeConversationViewModel: ObservableObject {
    @Published var isEnabled = false
    @Published var mode: SafeConversationSettings.SafeMode = .requestsOnly
    @Published var trustedUserIds: Set<String> = []
    @Published var enableKindnessFilter = false
    @Published var showSupportiveReplies = false
    @Published var autoEnabledUntil: Date?
    @Published var showAddTrusted = false
    
    private let service = SafeConversationService.shared
    private var settings: SafeConversationSettings?
    
    func load() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let loadedSettings = try await service.loadSettings(userId: userId)
            settings = loadedSettings
            isEnabled = loadedSettings.isEnabled
            mode = loadedSettings.mode
            trustedUserIds = loadedSettings.trustedUserIds
            enableKindnessFilter = loadedSettings.enableKindnessFilter
            showSupportiveReplies = loadedSettings.showSupportiveReplySuggestions
            autoEnabledUntil = loadedSettings.autoEnabledUntil
        } catch {
            dlog("⚠️ Failed to load safe conversation settings: \(error)")
        }
    }
    
    func save() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let updatedSettings = SafeConversationSettings(
            userId: userId,
            isEnabled: isEnabled,
            mode: mode,
            trustedUserIds: trustedUserIds,
            enableKindnessFilter: enableKindnessFilter,
            enableSlowMode: false,  // Managed automatically
            showSupportiveReplySuggestions: showSupportiveReplies,
            autoEnabledUntil: autoEnabledUntil,
            enabledAt: settings?.enabledAt ?? Date(),
            updatedAt: Date()
        )
        
        do {
            try await service.saveSettings(updatedSettings)
            dlog("✅ Safe conversation settings saved")
        } catch {
            dlog("⚠️ Failed to save settings: \(error)")
        }
    }
}

// MARK: - Trusted User Picker

struct TrustedUserPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [ContactUser] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    let onUserSelected: (String) -> Void

    private let messagingService = FirebaseMessagingService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by name or username", text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: searchText) { _, query in
                            scheduleSearch(query: query)
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
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()

                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchText.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Search for people to trust")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No users found for \"\(searchText)\"")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(searchResults) { user in
                        Button {
                            if let userId = user.id {
                                onUserSelected(userId)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "person.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName)
                                        .font(.custom("OpenSans-SemiBold", size: 15))
                                        .foregroundStyle(.primary)
                                    Text("@\(user.username)")
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "shield.checkered")
                                    .foregroundStyle(.green)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add Trusted User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms debounce
            guard !Task.isCancelled else { return }
            isSearching = true
            do {
                let results = try await messagingService.searchUsers(query: query)
                if !Task.isCancelled {
                    searchResults = results
                }
            } catch {
                if !Task.isCancelled { searchResults = [] }
            }
            isSearching = false
        }
    }
}

// MARK: - Preview

#Preview {
    SafeConversationView()
}

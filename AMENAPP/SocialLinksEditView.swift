//
//  SocialLinksEditView.swift
//  AMENAPP
//
//  Created by Steph on 1/21/26.
//
//  Complete UI for adding, editing, and managing social media links
//

import SwiftUI

// MARK: - Social Link Model for UI
// Note: Using enhanced version with additional features needed for editing

struct SocialLinkUI: Identifiable, Equatable {
    let id = UUID()
    let platform: SocialPlatform
    let username: String
    
    enum SocialPlatform: String, CaseIterable {
        case instagram = "Instagram"
        case twitter = "Twitter"
        case youtube = "YouTube"
        case tiktok = "TikTok"
        case linkedin = "LinkedIn"
        
        var icon: String {
            switch self {
            case .instagram: return "camera.circle.fill"
            case .twitter: return "bird.circle.fill"
            case .youtube: return "play.circle.fill"
            case .tiktok: return "music.note.circle.fill"
            case .linkedin: return "briefcase.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .instagram: return Color(red: 0.85, green: 0.35, blue: 0.55)
            case .twitter: return Color(red: 0.2, green: 0.6, blue: 0.95)
            case .youtube: return Color(red: 0.9, green: 0.2, blue: 0.2)
            case .tiktok: return Color.black
            case .linkedin: return Color(red: 0.0, green: 0.5, blue: 0.75)
            }
        }
        
        var displayName: String {
            self.rawValue
        }
    }
    
    // Convert from SocialLinkData
    init(from data: SocialLinkData) {
        self.platform = SocialPlatform(rawValue: data.platform) ?? .instagram
        self.username = data.username
    }
    
    // Direct initializer
    init(platform: SocialPlatform, username: String) {
        self.platform = platform
        self.username = username
    }
    
    // Convert to SocialLinkData
    func toData() -> SocialLinkData {
        SocialLinkData(platform: platform.rawValue, username: username)
    }
}

struct SocialLinksEditView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var socialLinksService = SocialLinksService.shared
    
    @Binding var socialLinks: [SocialLinkUI]
    
    @State private var showAddLinkSheet = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Social Links")
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        Text("Add links to your social media profiles")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Social Links List
                    if socialLinks.isEmpty {
                        EmptySocialLinksView {
                            showAddLinkSheet = true
                        }
                        .padding(.horizontal, 20)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(socialLinks) { link in
                                SocialLinkRow(
                                    link: link,
                                    onDelete: {
                                        removeLink(link)
                                    },
                                    onEdit: {
                                        // TODO: Edit functionality
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Add Link Button
                    if socialLinks.count < 6 {
                        Button {
                            showAddLinkSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                Text("Add Social Link")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black)
                            )
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                            
                            Text("Maximum 6 social links")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
            }
            .background(Color(white: 0.98))
            .navigationTitle("Social Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveLinks()
                    }
                    .font(.custom("OpenSans-Bold", size: 16))
                    .disabled(isLoading)
                }
            }
            .sheet(isPresented: $showAddLinkSheet) {
                AddSocialLinkSheet(onAdd: { platform, username in
                    addLink(platform: platform, username: username)
                })
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Add Link
    
    private func addLink(platform: SocialLinkUI.SocialPlatform, username: String) {
        // Remove existing link for same platform
        socialLinks.removeAll { $0.platform == platform }
        
        // Add new link
        let newLink = SocialLinkUI(platform: platform, username: username)
        socialLinks.append(newLink)
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    // MARK: - Remove Link
    
    private func removeLink(_ link: SocialLinkUI) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            socialLinks.removeAll { $0.id == link.id }
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    // MARK: - Save Links
    
    private func saveLinks() {
        isLoading = true
        
        Task {
            do {
                // Convert to service format
                let linkData = socialLinks.map { link in
                    SocialLinkData(
                        platform: link.platform.rawValue,
                        username: link.username
                    )
                }
                
                // Save to Firestore
                try await socialLinksService.updateSocialLinks(linkData)
                
                print("✅ Social links saved successfully")
                
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    dismiss()
                }
                
            } catch {
                print("❌ Failed to save social links: \(error)")
                
                await MainActor.run {
                    errorMessage = "Failed to save links: \(error.localizedDescription)"
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Empty State View

struct EmptySocialLinksView: View {
    let onAdd: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.circle")
                .font(.system(size: 64))
                .foregroundStyle(.black.opacity(0.2))
            
            Text("No social links yet")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            
            Text("Add links to your social media profiles to help others connect with you")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                onAdd()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Your First Link")
                        .font(.custom("OpenSans-Bold", size: 15))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(Color.black)
                )
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 60)
    }
}

// MARK: - Social Link Row

struct SocialLinkRow: View {
    let link: SocialLinkUI
    let onDelete: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Platform Icon
            ZStack {
                Circle()
                    .fill(link.platform.color.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: link.platform.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(link.platform.color)
            }
            
            // Platform & Username
            VStack(alignment: .leading, spacing: 4) {
                Text(link.platform.displayName)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                
                Text(link.username)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Delete Button
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(0.1))
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }
}

// MARK: - Add Social Link Sheet

struct AddSocialLinkSheet: View {
    @Environment(\.dismiss) var dismiss
    
    let onAdd: (SocialLinkUI.SocialPlatform, String) -> Void
    
    @State private var selectedPlatform: SocialLinkUI.SocialPlatform = .instagram
    @State private var username = ""
    @State private var showValidationError = false
    @State private var validationMessage = ""
    @FocusState private var isUsernameFocused: Bool
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add Social Link")
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        Text("Choose a platform and enter your username")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Platform Selector
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Platform")
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.secondary)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(SocialLinkUI.SocialPlatform.allCases, id: \.self) { platform in
                                PlatformButton(
                                    platform: platform,
                                    isSelected: selectedPlatform == platform
                                ) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedPlatform = platform
                                    }
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Username Input
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Username")
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            Text("@")
                                .font(.custom("OpenSans-SemiBold", size: 18))
                                .foregroundStyle(.secondary)
                            
                            TextField("username", text: $username)
                                .font(.custom("OpenSans-Regular", size: 17))
                                .focused($isUsernameFocused)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                        
                        if showValidationError {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                                
                                Text(validationMessage)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.red)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // Preview URL
                        if !username.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.blue)
                                
                                Text(SocialLinkData.generateURL(platform: selectedPlatform.rawValue, username: username))
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.blue)
                                    .lineLimit(1)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
            }
            .background(Color(white: 0.98))
            .navigationTitle("Add Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addLink()
                    }
                    .font(.custom("OpenSans-Bold", size: 16))
                    .disabled(username.isEmpty)
                }
            }
            .onAppear {
                isUsernameFocused = true
            }
        }
    }
    
    private func addLink() {
        // Validate username
        let validation = SocialLinksService.shared.validateUsername(
            platform: selectedPlatform.rawValue,
            username: username
        )
        
        if !validation.isValid {
            withAnimation {
                showValidationError = true
                validationMessage = validation.error ?? "Invalid username"
            }
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
            return
        }
        
        // Add the link
        onAdd(selectedPlatform, username)
        
        // Success haptic
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        dismiss()
    }
}

// MARK: - Platform Button

struct PlatformButton: View {
    let platform: SocialLinkUI.SocialPlatform
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? platform.color.opacity(0.15) : Color(.systemGray6))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: platform.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isSelected ? platform.color : Color.black.opacity(0.4))
                }
                
                Text(platform.displayName)
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(isSelected ? platform.color : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? platform.color : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: isSelected ? platform.color.opacity(0.2) : Color.black.opacity(0.05), radius: isSelected ? 8 : 4, y: 2)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var links = [
        SocialLinkUI(platform: .instagram, username: "johndoe"),
        SocialLinkUI(platform: .twitter, username: "johndoe")
    ]
    
    SocialLinksEditView(socialLinks: $links)
}


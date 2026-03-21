//
//  ShareSheet.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Share functionality with ability to share to OpenTable, Testimonies, or Prayer
//

import SwiftUI
import UIKit

// MARK: - Standard Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = excludedActivityTypes

        // On iPad, UIActivityViewController must have a sourceView / sourceRect set on its
        // popoverPresentationController, otherwise the app crashes with an NSInvalidArgumentException.
        if UIDevice.current.userInterfaceIdiom == .pad,
           let popover = controller.popoverPresentationController {
            // Anchor to the root view of the key window; callers can override via context if needed.
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })
            let keyWindow = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
            popover.sourceView = keyWindow?.rootViewController?.view
            popover.sourceRect = CGRect(
                x: (keyWindow?.bounds.midX ?? 0),
                y: (keyWindow?.bounds.midY ?? 0),
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

// MARK: - AMEN App Share Options

enum ShareDestination {
    case openTable
    case testimonies
    case prayer
    case external
}

struct AmenShareSheet: View {
    let note: ChurchNote
    @Environment(\.dismiss) var dismiss
    @State private var showExternalShare = false
    @State private var isSharing = false
    @State private var showShareSuccess = false
    @State private var shareSuccessMessage = ""
    @State private var showShareError = false
    @State private var shareErrorMessage = ""
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Share your note with the AMEN community or externally")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                
                Section("Share Within AMEN") {
                    // Share to OpenTable
                    Button {
                        shareToOpenTable()
                    } label: {
                        ShareOptionRow(
                            icon: "table.furniture",
                            title: "Share to OpenTable",
                            description: "Start a discussion about this sermon",
                            color: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Share to Testimonies
                    Button {
                        shareToTestimonies()
                    } label: {
                        ShareOptionRow(
                            icon: "heart.text.square",
                            title: "Share as Testimony",
                            description: "Share how this message impacted you",
                            color: .purple
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Share to Prayer
                    Button {
                        shareToPrayer()
                    } label: {
                        ShareOptionRow(
                            icon: "hands.sparkles",
                            title: "Share as Prayer Request",
                            description: "Ask the community to pray about insights",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Section("Share Externally") {
                    Button {
                        showExternalShare = true
                    } label: {
                        ShareOptionRow(
                            icon: "square.and.arrow.up",
                            title: "Share via...",
                            description: "Messages, social media, and more",
                            color: .green
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Share Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showExternalShare) {
            ShareSheet(items: [generateShareText()])
        }
        .alert("Shared!", isPresented: $showShareSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(shareSuccessMessage)
        }
        .alert("Share Failed", isPresented: $showShareError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(shareErrorMessage)
        }
        .disabled(isSharing)
    }
    
    // MARK: - Share Actions
    
    private func shareToOpenTable() {
        isSharing = true
        Task { @MainActor in
            defer { isSharing = false }
            var content = note.title + "\n\n"
            if let sermon = note.sermonTitle { content += "Sermon: \(sermon)\n" }
            if let pastor = note.pastor { content += "Pastor: \(pastor)\n" }
            if let church = note.churchName { content += "Church: \(church)\n" }
            if let scripture = note.scripture { content += "\n\(scripture)\n" }
            content += "\n\(note.content)"
            if !note.tags.isEmpty {
                content += "\n\n" + note.tags.map { "#\($0)" }.joined(separator: " ")
            }
            PostsManager.shared.createPost(
                content: content,
                category: .openTable,
                topicTag: note.tags.first ?? "ChurchNotes",
                visibility: .everyone,
                allowComments: true,
                imageURLs: nil,
                linkURL: nil,
                churchNoteId: note.id
            )
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            shareSuccessMessage = "Your note has been shared to OpenTable."
            showShareSuccess = true
            dismiss()
        }
    }

    private func shareToTestimonies() {
        isSharing = true
        Task { @MainActor in
            defer { isSharing = false }
            var content = note.title + "\n\n"
            if let scripture = note.scripture { content += "\(scripture)\n\n" }
            content += note.content
            if !note.tags.isEmpty {
                content += "\n\n" + note.tags.map { "#\($0)" }.joined(separator: " ")
            }
            PostsManager.shared.createPost(
                content: content,
                category: .testimonies,
                topicTag: note.tags.first ?? "Testimony",
                visibility: .everyone,
                allowComments: true,
                imageURLs: nil,
                linkURL: nil,
                churchNoteId: note.id
            )
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            shareSuccessMessage = "Your note has been shared as a Testimony."
            showShareSuccess = true
            dismiss()
        }
    }

    private func shareToPrayer() {
        isSharing = true
        Task { @MainActor in
            defer { isSharing = false }
            var content = note.title + "\n\n"
            if let scripture = note.scripture { content += "\(scripture)\n\n" }
            content += note.content
            if !note.tags.isEmpty {
                content += "\n\n" + note.tags.map { "#\($0)" }.joined(separator: " ")
            }
            PostsManager.shared.createPost(
                content: content,
                category: .prayer,
                topicTag: note.tags.first ?? "Prayer",
                visibility: .everyone,
                allowComments: true,
                imageURLs: nil,
                linkURL: nil,
                churchNoteId: note.id
            )
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            shareSuccessMessage = "Your note has been shared as a Prayer Request."
            showShareSuccess = true
            dismiss()
        }
    }
    
    private func generateShareText() -> String {
        var text = "📝 \(note.title)\n\n"
        
        if let sermon = note.sermonTitle {
            text += "🎤 Sermon: \(sermon)\n"
        }
        
        if let church = note.churchName {
            text += "⛪ Church: \(church)\n"
        }
        
        if let pastor = note.pastor {
            text += "👤 Pastor: \(pastor)\n"
        }
        
        if let scripture = note.scripture {
            text += "📖 Scripture: \(scripture)\n"
        }
        
        text += "\n\(note.content)\n"
        
        if !note.tags.isEmpty {
            text += "\n🏷️ " + note.tags.map { "#\($0)" }.joined(separator: " ")
        }
        
        text += "\n\nShared from AMEN App 🙏"
        
        return text
    }
}

// MARK: - Share Option Row

struct ShareOptionRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Simple Share Button

struct SimpleShareButton: View {
    let note: ChurchNote
    @State private var showShareSheet = false
    
    var body: some View {
        Button {
            showShareSheet = true
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .sheet(isPresented: $showShareSheet) {
            AmenShareSheet(note: note)
        }
    }
}

// MARK: - Preview

#Preview("AMEN Share Sheet") {
    AmenShareSheet(note: .preview)
}

#Preview("Share Option Row") {
    List {
        ShareOptionRow(
            icon: "table.furniture",
            title: "Share to OpenTable",
            description: "Start a discussion about this sermon",
            color: .blue
        )
        
        ShareOptionRow(
            icon: "heart.text.square",
            title: "Share as Testimony",
            description: "Share how this message impacted you",
            color: .purple
        )
        
        ShareOptionRow(
            icon: "hands.sparkles",
            title: "Share as Prayer Request",
            description: "Ask the community to pray about insights",
            color: .orange
        )
    }
}

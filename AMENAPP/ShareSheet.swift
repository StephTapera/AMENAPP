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
    }
    
    // MARK: - Share Actions
    
    private func shareToOpenTable() {
        // TODO: Implement OpenTable sharing
        // This would create a new OpenTable post with the note content
        print("📝 Sharing to OpenTable: \(note.title)")
        
        // Post to OpenTable with note content
        Task {
            do {
                // await OpenTableService.shared.createPost(
                //     title: note.title,
                //     content: generateShareText(),
                //     tags: note.tags
                // )
                
                await MainActor.run {
                    dismiss()
                    // Show success toast/alert
                }
            } catch {
                print("❌ Error sharing to OpenTable: \(error)")
            }
        }
    }
    
    private func shareToTestimonies() {
        // TODO: Implement Testimonies sharing
        // This would create a new testimony with the note content
        print("💜 Sharing to Testimonies: \(note.title)")
        
        Task {
            do {
                // await TestimonyService.shared.createTestimony(
                //     title: note.title,
                //     content: note.content,
                //     scripture: note.scripture,
                //     tags: note.tags
                // )
                
                await MainActor.run {
                    dismiss()
                    // Show success toast/alert
                }
            } catch {
                print("❌ Error sharing to Testimonies: \(error)")
            }
        }
    }
    
    private func shareToPrayer() {
        // TODO: Implement Prayer sharing
        // This would create a new prayer request with the note content
        print("🙏 Sharing to Prayer: \(note.title)")
        
        Task {
            do {
                // await PrayerService.shared.createPrayerRequest(
                //     title: note.title,
                //     description: note.content,
                //     scripture: note.scripture,
                //     tags: note.tags
                // )
                
                await MainActor.run {
                    dismiss()
                    // Show success toast/alert
                }
            } catch {
                print("❌ Error sharing to Prayer: \(error)")
            }
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

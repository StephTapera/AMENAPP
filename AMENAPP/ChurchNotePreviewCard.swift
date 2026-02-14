//
//  ChurchNotePreviewCard.swift
//  AMENAPP
//
//  Minimal church note preview card for feed
//  Based on clean typographic design
//

import SwiftUI

/// Minimal church note preview card for displaying in post feed
struct ChurchNotePreviewCard: View {
    let note: ChurchNote
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Header with badge
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Church Note badge
                        HStack(spacing: 6) {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(hex: "#6B6B6B"))
                            
                            Text("Church Note")
                                .font(.custom("OpenSans-SemiBold", size: 11))
                                .foregroundStyle(Color(hex: "#6B6B6B"))
                                .tracking(0.5)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color(hex: "#F5F5F5"))
                        )
                        
                        // Title
                        Text(note.title)
                            .font(.custom("OpenSans-SemiBold", size: 19))
                            .foregroundStyle(Color(hex: "#1A1A1A"))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    // Subtle arrow indicator
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: "#6B6B6B"))
                        .opacity(0.5)
                }
                .padding(.bottom, 12)
                
                // Preview content (2 lines)
                Text(note.content)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(Color(hex: "#4A4A4A"))
                    .lineLimit(2)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 16)
                
                // Divider
                Rectangle()
                    .fill(Color(hex: "#E8E8E8"))
                    .frame(height: 1)
                    .padding(.bottom, 12)
                
                // Metadata row
                HStack(spacing: 0) {
                    // Church name
                    if let churchName = note.churchName {
                        Text(churchName)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(Color(hex: "#6B6B6B"))
                        
                        Text(" • ")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(Color(hex: "#CBCBCB"))
                    }
                    
                    // Date
                    Text(note.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(Color(hex: "#6B6B6B"))
                    
                    Spacer()
                }
                .padding(.bottom, 12)
                
                // Tap to view hint
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(hex: "#9B9B9B"))
                    
                    Text("Tap to view full note")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(Color(hex: "#9B9B9B"))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "#FAFAFA"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(hex: "#EBEBEB"), lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

/// Full-screen church note detail view (modal presentation)
struct ChurchNoteDetailModal: View {
    let note: ChurchNote
    @Environment(\.dismiss) var dismiss
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header section
                    VStack(alignment: .leading, spacing: 16) {
                        // Church Note badge
                        HStack(spacing: 6) {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: "#6B6B6B"))
                            
                            Text("Church Note")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(Color(hex: "#6B6B6B"))
                                .tracking(0.5)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(hex: "#F5F5F5"))
                        )
                        
                        // Title
                        Text(note.title)
                            .font(.custom("OpenSans-Bold", size: 28))
                            .foregroundStyle(Color(hex: "#1A1A1A"))
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                    
                    // Metadata section
                    VStack(alignment: .leading, spacing: 10) {
                        if let sermonTitle = note.sermonTitle {
                            NoteMetadataRow(label: "Sermon", value: sermonTitle)
                        }
                        
                        if let pastor = note.pastor {
                            NoteMetadataRow(label: "Pastor", value: pastor)
                        }
                        
                        if let churchName = note.churchName {
                            NoteMetadataRow(label: "Church", value: churchName)
                        }
                        
                        NoteMetadataRow(label: "Date", value: note.date.formatted(date: .long, time: .omitted))
                        
                        if !note.scriptureReferences.isEmpty {
                            NoteMetadataRow(label: "Scripture", value: note.scriptureReferences.joined(separator: ", "))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    
                    // Divider
                    Rectangle()
                        .fill(Color(hex: "#E8E8E8"))
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    
                    // Content
                    Text(note.content)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(Color(hex: "#2A2A2A"))
                        .lineSpacing(6)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    
                    // Key Points
                    if !note.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Key Points")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(Color(hex: "#6B6B6B"))
                                .tracking(0.5)
                                .padding(.bottom, 4)
                            
                            ForEach(Array(note.keyPoints.enumerated()), id: \.offset) { index, point in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("•")
                                        .font(.custom("OpenSans-Regular", size: 16))
                                        .foregroundStyle(Color(hex: "#4A4A4A"))
                                    
                                    Text(point)
                                        .font(.custom("OpenSans-Regular", size: 15))
                                        .foregroundStyle(Color(hex: "#4A4A4A"))
                                        .lineSpacing(4)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                    
                    // Tags
                    if !note.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Tags")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(Color(hex: "#6B6B6B"))
                                .tracking(0.5)
                                .padding(.bottom, 4)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(note.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(Color(hex: "#6B6B6B"))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(Color(hex: "#F5F5F5"))
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(hex: "#1A1A1A"))
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showShareSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(hex: "#1A1A1A"))
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ChurchNoteShareOptionsSheet(note: note)
            }
        }
    }
}

/// Simple metadata row for church note details
private struct NoteMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(Color(hex: "#9B9B9B"))
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(Color(hex: "#4A4A4A"))
        }
    }
}

/// Share options sheet for church notes
struct ChurchNoteShareOptionsSheet: View {
    let note: ChurchNote
    @Environment(\.dismiss) var dismiss
    @State private var showingShareCommunityConfirmation = false
    @State private var shareSuccessMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Share as Text
                    Button {
                        ChurchNotesShareHelper.shareNote(note, from: nil)
                        dismiss()
                    } label: {
                        Label("Share as Text", systemImage: "doc.text")
                    }

                    // Share as PDF
                    Button {
                        ChurchNotesShareHelper.sharePDF(for: note, from: nil)
                        dismiss()
                    } label: {
                        Label("Share as PDF", systemImage: "doc.richtext")
                    }
                } header: {
                    Text("Export Options")
                }

                Section {
                    // Share to Community
                    Button {
                        showingShareCommunityConfirmation = true
                    } label: {
                        Label("Share to Community Feed", systemImage: "person.3.fill")
                    }
                } header: {
                    Text("Share on AMEN")
                }
            }
            .navigationTitle("Share Church Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Share to Community?", isPresented: $showingShareCommunityConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Share") {
                    shareToCommunit()
                }
            } message: {
                Text("This will create a post in your feed with this church note attached.")
            }
            .alert("Success", isPresented: .constant(shareSuccessMessage != nil)) {
                Button("OK") {
                    shareSuccessMessage = nil
                    dismiss()
                }
            } message: {
                if let message = shareSuccessMessage {
                    Text(message)
                }
            }
        }
    }

    private func shareToCommunit() {
        ChurchNotesShareHelper.shareToCommunit(note) { success in
            if success {
                shareSuccessMessage = "Church note shared to your community feed!"
            }
        }
    }
}

/// Hex color extension
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        ChurchNotePreviewCard(note: ChurchNote.preview) {
            print("Tapped")
        }
        .padding()
        
        Spacer()
    }
    .background(Color.white)
}

//
//  CommunityDuetSheet.swift
//  AMENAPP
//
//  Community Notes sheet — browse and stitch other believers' sermon insights.
//

import SwiftUI

struct CommunityDuetSheet: View {
    @StateObject var viewModel: CommunityDuetViewModel
    @Binding var noteBody: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "050508").ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.35))
                            .font(.subheadline)
                        TextField("Search notes, scripture, author…", text: $viewModel.searchText)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(hex: "050508"))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .onChange(of: viewModel.searchText) { _, _ in viewModel.filterNotes() }

                    // Notes list
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.filteredNotes) { note in
                                CommunityNoteCard(note: note) {
                                    let impact = UIImpactFeedbackGenerator(style: .medium)
                                    impact.impactOccurred()
                                    viewModel.stitchNote(note, into: &noteBody)
                                    dismiss()
                                }
                            }

                            if viewModel.filteredNotes.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "text.bubble")
                                        .font(.largeTitle)
                                        .foregroundColor(.white.opacity(0.2))
                                    Text("No notes match your search.")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.35))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Community Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.cnGold)
                }
            }
        }
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
        .presentationDetents([.medium, .large])
        .onAppear { viewModel.loadDuetCommunityNotes() }
    }
}

// MARK: - CommunityNoteCard

private struct CommunityNoteCard: View {
    let note: DuetCommunityNote
    let onStitch: () -> Void

    @State private var stitchScale: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author row
            HStack(spacing: 10) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: note.avatarColorHex), Color(hex: note.avatarColorHex).opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Text(note.authorInitials)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.authorName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    // Scripture badge
                    Text(note.scriptureRef)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.cnGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.cnGold.opacity(0.15)))
                }

                Spacer()

                // Like count
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundColor(.amenRose.opacity(0.7))
                    Text("\(note.likeCount)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            // Note snippet
            Text(note.noteSnippet)
                .font(.systemScaled(13))
                .foregroundColor(.white.opacity(0.70))
                .lineLimit(3)

            // Footer
            HStack {
                Text(note.churchName)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.35))

                Spacer()

                // Stitch button
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) { stitchScale = 0.97 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) { stitchScale = 1.0 }
                        onStitch()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption2)
                        Text("Stitch")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.amenBlue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.amenBlue.opacity(0.15))
                            .overlay(Capsule().strokeBorder(Color.amenBlue.opacity(0.3), lineWidth: 0.8))
                    )
                }
                .buttonStyle(.plain)
                .scaleEffect(stitchScale)
            }
        }
        .padding(14)
        .glassCard()
    }
}

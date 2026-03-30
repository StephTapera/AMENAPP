//
//  QuoteForgeSheet.swift
//  AMENAPP
//
//  Quote Forge — detect best quote from notes and preview styled reel cards.
//

import SwiftUI

struct QuoteForgeSheet: View {
    @StateObject var viewModel: QuoteForgeViewModel
    @Binding var noteBody: String
    @Environment(\.dismiss) private var dismiss

    @State private var pulseOpacity: Double = 0.2
    @State private var showComingSoon = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "050508").ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        // Detected quote card
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("BEST LINE DETECTED")

                            Text(viewModel.detectedQuote.isEmpty ? "Start writing your notes to detect a powerful quote." : viewModel.detectedQuote)
                                .font(.system(size: 18, weight: .bold, design: .serif))
                                .italic()
                                .foregroundColor(.white.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)
                                        .overlay(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
                                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.cnGold, lineWidth: 1))
                                )
                                .shadow(color: Color.cnGold.opacity(pulseOpacity), radius: 16)
                        }

                        // Style selector
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("STYLE")

                            TabView(selection: $viewModel.selectedStyleIndex) {
                                ForEach(Array(viewModel.reelStyles.enumerated()), id: \.element.id) { idx, style in
                                    QuoteDesignPreviewCard(
                                        style: style,
                                        quote: viewModel.detectedQuote,
                                        isSelected: viewModel.selectedStyleIndex == idx
                                    )
                                    .tag(idx)
                                    .padding(.horizontal, 4)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .always))
                            .frame(height: 210)
                        }

                        // Action buttons
                        HStack(spacing: 12) {
                            Button {
                                showComingSoon = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Save to Photos")
                                        .fontWeight(.semibold)
                                }
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.85))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.ultraThinMaterial)
                                        .overlay(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                showComingSoon = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                        .fontWeight(.semibold)
                                }
                                .font(.subheadline)
                                .foregroundColor(.cnGold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.cnGold.opacity(0.12))
                                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.cnGold.opacity(0.35), lineWidth: 1))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Quote Forge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cnGold)
                }
            }
            .alert("Coming Soon", isPresented: $showComingSoon) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Quote export and sharing will be available in a future update.")
            }
        }
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
        .onAppear {
            viewModel.detectBestQuote(from: noteBody)
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseOpacity = 0.6
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .tracking(2)
            .foregroundColor(.white.opacity(0.4))
    }
}

// MARK: - QuoteDesignPreviewCard

private struct QuoteDesignPreviewCard: View {
    let style: CNReelStyle
    let quote: String
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background gradient
            LinearGradient(
                colors: style.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Emoji top-right
            Text(style.emoji)
                .font(.system(size: 36))
                .padding(12)

            // Quote text center
            VStack {
                Spacer()
                HStack {
                    Text(quote.isEmpty ? "Your powerful quote will appear here." : String(quote.prefix(120)))
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .italic()
                        .foregroundColor(.white)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 36)
                    Spacer()
                }
            }

            // AMEN watermark bottom-left
            VStack {
                Spacer()
                HStack {
                    Text("AMEN")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                    Spacer()
                }
            }
        }
        .frame(width: 280, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isSelected ? Color.cnGold : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
    }
}

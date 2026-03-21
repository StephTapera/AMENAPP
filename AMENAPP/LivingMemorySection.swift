// LivingMemorySection.swift
// AMENAPP
// Resources section — horizontally scrolling Soul Engine cards

import SwiftUI

struct LivingMemorySection: View {
    @StateObject private var service = LivingMemoryService.shared
    @State private var appearedOnce = false
    @State private var heartbeatScale: CGFloat = 1.0
    @State private var selectedPostId: IdentifiableString? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section header
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(red: 0.47, green: 0.73, blue: 1.0))
                        Text("Living Memory")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Text("Resonant with your recent prayer")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if service.isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                } else if !service.resonantItems.isEmpty {
                    Button {
                        Task { await service.loadResonantContent() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)

            // Cards or states
            if service.isLoading {
                loadingRow
            } else if service.resonantItems.isEmpty {
                emptyState
            } else {
                cardsRow
            }
        }
        .sheet(item: $selectedPostId) { wrapper in
            NavigationStack {
                NotificationPostDetailView(postId: wrapper.value)
            }
        }
        .task {
            guard !appearedOnce else { return }
            appearedOnce = true
            await service.loadResonantContent()
        }
    }

    // MARK: - Horizontal scroll of cards

    private var cardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(service.resonantItems) { item in
                    LivingMemoryCard(item: item) {
                        selectedPostId = IdentifiableString(value: item.id)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Skeleton loading row

    private var loadingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    LivingMemorySkeletonCard()
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
                .scaleEffect(heartbeatScale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        heartbeatScale = 1.05
                    }
                }
            Text("Post a prayer to awaken Living Memory")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 20)
    }
}

// MARK: - Identifiable wrapper for sheet(item:)

private struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }
}

// MARK: - Skeleton card

private struct LivingMemorySkeletonCard: View {
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShimmerBar(width: 70, height: 10)
            ShimmerBar(width: 200, height: 12)
            ShimmerBar(width: 160, height: 12)
            ShimmerBar(width: 120, height: 12)
            Spacer(minLength: 4)
            ShimmerBar(width: 90, height: 10)
        }
        .padding(16)
        .frame(width: 230, height: 130)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.08, green: 0.07, blue: 0.12))
        )
    }
}

private struct ShimmerBar: View {
    let width: CGFloat
    let height: CGFloat
    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.white.opacity(0.14),
                        Color.white.opacity(0.06),
                    ],
                    startPoint: animate ? .leading : .trailing,
                    endPoint: animate ? .trailing : .leading
                )
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}

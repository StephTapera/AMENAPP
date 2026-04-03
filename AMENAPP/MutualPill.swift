//
//  MutualPill.swift
//  AMENAPP
//
//  Liquid glass mutual connections pill for UserProfileView
//  Shows stacked avatars + count with expandable panel
//

import SwiftUI

// MARK: - Main Pill Component

struct MutualPill: View {
    let mutuals: [MutualUser]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // PILL
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.72))) {
                    expanded.toggle()
                }
                HapticManager.impact(style: .light)
            } label: {
                HStack(spacing: 5) {
                    StackedAvatars(users: Array(mutuals.prefix(3)))
                    Text("\(mutuals.count) mutual\(mutuals.count == 1 ? "" : "s")")
                        .font(.systemScaled(9, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                    LiveDot()
                }
                .padding(.vertical, 3)
                .padding(.leading, 3)
                .padding(.trailing, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            // ── Expand panel ─────────────────────────────────
            if expanded {
                MutualExpandPanel(mutuals: mutuals)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal:   .move(edge: .top).combined(with: .opacity)
                    ))
                    .padding(.top, 6)
            }
        }
    }
}

// MARK: - Stacked Mini Avatars

struct StackedAvatars: View {
    let users: [MutualUser]
    
    var body: some View {
        ZStack {
            ForEach(Array(users.enumerated().reversed()), id: \.offset) { i, user in
                Group {
                    if let url = user.avatarURL {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(user.color)
                        }
                    } else {
                        Circle().fill(user.color)
                    }
                }
                .frame(width: 18, height: 18)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
                .offset(x: CGFloat(i) * 9)
            }
        }
        .frame(width: 18 + CGFloat(max(users.count - 1, 0)) * 9, height: 18)
    }
}

// MARK: - Live Pulse Dot

struct LiveDot: View {
    @State private var pulse = false
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(0.4), lineWidth: 1)
                .frame(width: pulse ? 11 : 5, height: pulse ? 11 : 5)
                .opacity(pulse ? 0 : 0.8)
            Circle()
                .fill(Color.green)
                .frame(width: 5, height: 5)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - Expand Panel (Liquid Glass Card)

struct MutualExpandPanel: View {
    let mutuals: [MutualUser]
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(mutuals.enumerated()), id: \.offset) { i, user in
                HStack(spacing: 9) {
                    // Avatar
                    Group {
                        if let url = user.avatarURL {
                            CachedAsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(user.color)
                            }
                        } else {
                            Circle().fill(user.color)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.name)
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(user.context)
                            .font(.systemScaled(9))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(user.relationshipLabel)
                        .font(.systemScaled(8, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(user.badgeColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(user.badgeColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                
                if i < mutuals.count - 1 {
                    Divider().padding(.leading, 47)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Model

struct MutualUser: Identifiable {
    let id: String
    let name: String
    let context: String
    let avatarURL: URL?
    let color: Color
    let relationshipLabel: String
    let badgeColor: Color
}

// MARK: - Preview

#Preview {
    let sampleMutuals = [
        MutualUser(
            id: "1",
            name: "Sarah Johnson",
            context: "@sarahj",
            avatarURL: nil,
            color: .blue,
            relationshipLabel: "MUTUAL",
            badgeColor: .orange
        ),
        MutualUser(
            id: "2",
            name: "Michael Chen",
            context: "@mchen",
            avatarURL: nil,
            color: .purple,
            relationshipLabel: "PRAYER",
            badgeColor: .indigo
        ),
        MutualUser(
            id: "3",
            name: "Emily Davis",
            context: "@emilyd",
            avatarURL: nil,
            color: .green,
            relationshipLabel: "COMMUNITY",
            badgeColor: .green
        )
    ]
    
    return VStack(spacing: 20) {
        MutualPill(mutuals: sampleMutuals)
        
        Spacer()
    }
    .padding()
    .background(Color(.systemBackground))
}

// MentorCardView.swift
// AMENAPP
// Liquid Glass mentor discovery card

import SwiftUI

struct MentorCardView: View {
    let mentor: Mentor
    let index: Int
    let isAppeared: Bool
    let hasRelationship: Bool
    let onRequest: () -> Void
    let onMessage: () -> Void

    @State private var isPressed = false
    @State private var limitedPulse: CGFloat = 1.0
    @State private var liftOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar with status dot
            ZStack(alignment: .bottomTrailing) {
                MentorAvatarView(name: mentor.name, photoURL: mentor.photoURL, size: 52)

                Circle()
                    .fill(mentor.availabilityStatus.dotColor)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Name + verified badge
                HStack(spacing: 5) {
                    Text(mentor.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    if mentor.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.82))
                    }
                }

                // Role + church
                Text("\(mentor.role) · \(mentor.church)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Bio
                Text(mentor.bio)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)

                // Specialty pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(mentor.specialties, id: \.self) { spec in
                            Text(spec)
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color(.tertiarySystemBackground)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)

                // Rating + response time + status
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 10))
                        Text(String(format: "%.1f", mentor.rating))
                            .font(.system(size: 11))
                    }
                    Text("~\(mentor.responseTimeHours)h reply")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(mentor.availabilityStatus.dotColor)
                            .frame(width: 7, height: 7)
                        Text(mentor.availabilityStatus.label)
                            .font(.system(size: 10))
                            .foregroundStyle(mentor.availabilityStatus.color)
                    }
                }

                // Price + actions
                HStack(spacing: 8) {
                    Text(mentor.plans.first?.priceLabel ?? "Free")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    // Message button
                    Button(action: onMessage) {
                        Label("Message", systemImage: "message.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                    }
                    // Request button
                    Button(action: onRequest) {
                        Text(hasRelationship ? "Active ✓" : "Request →")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    hasRelationship
                                    ? Color(red: 0.09, green: 0.64, blue: 0.29)
                                    : Color(red: 0.49, green: 0.23, blue: 0.93)
                                )
                            )
                            .scaleEffect(mentor.availabilityStatus == .limited ? limitedPulse : 1.0)
                    }
                    .disabled(hasRelationship)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .cornerRadius(18)
        .shadow(color: .black.opacity(isPressed ? 0.04 : 0.06), radius: isPressed ? 4 : 12, y: isPressed ? 1 : 4)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .offset(y: liftOffset)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in
                    isPressed = false
                    if !reduceMotion {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { liftOffset = -3 }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.65).delay(0.1)) { liftOffset = 0 }
                    }
                }
        )
        // Stagger appear
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 16)
        .animation(.spring(response: 0.45, dampingFraction: 0.75).delay(Double(index) * 0.08), value: isAppeared)
        .onAppear {
            if mentor.availabilityStatus == .limited && !reduceMotion {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    limitedPulse = 1.03
                }
            }
        }
    }
}

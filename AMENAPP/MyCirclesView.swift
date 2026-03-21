// MyCirclesView.swift
// AMENAPP
// Active mentorships view

import SwiftUI
import FirebaseAuth

struct MyCirclesView: View {
    let relationships: [MentorshipRelationship]
    let checkIns: [MentorshipCheckIn]
    @ObservedObject var vm: MentorshipViewModel

    @State private var appearedRelIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if relationships.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(Array(relationships.enumerated()), id: \.element.id) { idx, rel in
                        RelationshipCard(
                            relationship: rel,
                            pendingCheckIn: pendingCheckIn(for: rel),
                            isAppeared: appearedRelIds.contains(rel.id),
                            onMessage: {
                                let uid = Auth.auth().currentUser?.uid ?? ""
                                vm.showChatFor = MentorshipService.shared.chatId(mentorId: rel.mentorId, menteeId: uid)
                            },
                            onCheckIn: {
                                if let ci = pendingCheckIn(for: rel) {
                                    vm.showCheckInFor = ci
                                }
                            },
                            onBook: {
                                dlog("📅 Book session tapped for \(rel.mentorName)")
                            }
                        )
                        .padding(.horizontal, 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.75).delay(Double(idx) * 0.07)) {
                                appearedRelIds.formUnion([rel.id])
                            }
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private func pendingCheckIn(for rel: MentorshipRelationship) -> MentorshipCheckIn? {
        checkIns.first { $0.relationshipId == rel.id && $0.status == .pending }
    }

    // MARK: Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
                .padding(.top, 50)

            Text("No active mentorships")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)

            Text("Find a mentor to begin your journey")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    vm.selectedTab = .findMentor
                }
            } label: {
                Text("Find a Mentor")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color(red: 0.49, green: 0.23, blue: 0.93)))
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Relationship Card
private struct RelationshipCard: View {
    let relationship: MentorshipRelationship
    let pendingCheckIn: MentorshipCheckIn?
    let isAppeared: Bool
    let onMessage: () -> Void
    let onCheckIn: () -> Void
    let onBook: () -> Void

    @State private var progressFill: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                MentorAvatarView(name: relationship.mentorName, photoURL: relationship.mentorPhotoURL, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(relationship.mentorName)
                        .font(.system(size: 14, weight: .semibold))
                    // Plan badge
                    Text(relationship.planName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 0.49, green: 0.23, blue: 0.93))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.10)))
                }
                Spacer()
            }

            // Session progress bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(.systemGray5))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.49, green: 0.23, blue: 0.93))
                            .frame(width: geo.size.width * progressFill)
                    }
                }
                .frame(height: 3)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                        progressFill = relationship.sessionProgress
                    }
                }

                Text("Session \(relationship.sessionsCompleted) of \(relationship.totalSessions) complete")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Action buttons
            HStack(spacing: 8) {
                ActionButton(title: "Message", icon: "message.fill", action: onMessage)
                if pendingCheckIn != nil {
                    ActionButton(title: "Check-in", icon: "checklist", action: onCheckIn, isPrimary: true)
                }
                ActionButton(title: "Book", icon: "calendar.badge.plus", action: onBook)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 16)
    }
}

// MARK: - Action Button
private struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var isPrimary: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isPrimary ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isPrimary ? Color(red: 0.49, green: 0.23, blue: 0.93) : Color(.secondarySystemBackground))
            )
        }
    }
}

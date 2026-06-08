//
//  SuggestedFollowsButton.swift
//  AMENAPP
//
//  System 13: Suggested Follows
//  44x44 glass circle button with person.badge.plus icon.
//  Placed alongside Follow/Message buttons on UserProfileView.
//

import SwiftUI

struct SuggestedFollowsButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                        .clipShape(Circle())
                    )
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.6), lineWidth: 0.5)
                    )

                Image(systemName: "person.badge.plus")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Suggested people to follow")
        .accessibilityHint("Double tap to see follow suggestions")
    }
}

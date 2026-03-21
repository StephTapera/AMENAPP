// MentorAvatarView.swift
// AMENAPP
// Reusable mentor avatar with initials fallback

import SwiftUI

struct MentorAvatarView: View {
    let name: String
    let photoURL: String?
    let size: CGFloat

    private var initials: String {
        name.components(separatedBy: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    var body: some View {
        ZStack {
            if let urlString = photoURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    initialsView
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            Circle().fill(Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.15))
            Text(initials)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(Color(red: 0.49, green: 0.23, blue: 0.93))
        }
    }
}

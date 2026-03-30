//
//  PinBadge.swift
//  AMENAPP
//
//  Whisper-opacity "Pinned" indicator used on PinnedPostCard.
//

import SwiftUI

struct PinBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "paperclip")
                .font(.system(size: 10, weight: .medium))
            Text("Pinned")
                .font(.system(size: 11))
        }
        .foregroundStyle(Color.white.opacity(0.35))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
        )
    }
}

//
//  PinDurationSheet.swift
//  AMENAPP
//
//  AMEN-consistent bottom sheet for choosing how long to pin a post.
//

import SwiftUI

struct PinDurationSheet: View {
    @Binding var isPresented: Bool
    let onConfirm: (PinDuration) -> Void

    @State private var selected: PinDuration = .indefinite

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Title
            Text("Pin to profile")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

            Text("Choose how long this post stays pinned.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            // Duration options
            VStack(spacing: 8) {
                ForEach(PinDuration.allCases) { duration in
                    DurationRow(duration: duration, isSelected: selected == duration) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            selected = duration
                        }
                    }
                }
            }
            .padding(.horizontal, 16)

            // Confirm button
            Button {
                onConfirm(selected)
                isPresented = false
            } label: {
                Text("Pin Post")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0.05, green: 0.05, blue: 0.08))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)

            Spacer().frame(height: 20)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.1))
    }
}

// MARK: - Duration Row

private struct DurationRow: View {
    let duration: PinDuration
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: duration.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
                    .frame(width: 24)

                Text(duration.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.55))

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? Color.white.opacity(0.18) : Color.clear,
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

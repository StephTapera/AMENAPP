// LivingMemoryCard.swift
// AMENAPP
// Individual card surfaced by the Soul Engine in Resources

import SwiftUI

struct LivingMemoryCard: View {
    let item: LivingMemoryItem
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            cardContent
        }
        .buttonStyle(LivingMemoryPressStyle())
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Type badge + resonance pulse
            HStack(spacing: 6) {
                Image(systemName: item.type.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(typeColor)
                Text(item.type.label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(typeColor)
                Spacer()
                ResonancePulse(score: item.resonanceScore)
            }

            // Content preview
            Text(item.content)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(Color(white: 0.88))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: false)

            // Author row
            HStack(spacing: 6) {
                if let url = item.authorPhotoURL, let parsed = URL(string: url) {
                    AsyncImage(url: parsed) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color.white.opacity(0.12))
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text(String(item.authorName.prefix(1)))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                        )
                }
                Text(item.authorName)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(white: 0.60))
                Spacer()
                Text(item.createdAt.relativeLabel)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(Color(white: 0.45))
            }
        }
        .padding(16)
        .frame(width: 230)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.08, green: 0.07, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(typeColor.opacity(0.25), lineWidth: 0.75)
                )
        )
    }

    private var typeColor: Color {
        switch item.type {
        case .prayer:    return Color(red: 0.47, green: 0.73, blue: 1.0)
        case .testimony: return Color(red: 0.98, green: 0.75, blue: 0.25)
        case .post:      return Color(red: 0.55, green: 0.85, blue: 0.65)
        }
    }
}

// MARK: - Resonance pulse dot

private struct ResonancePulse: View {
    let score: Double // 0–1
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if score > 0.75 {
                Circle()
                    .fill(pulseColor.opacity(0.3))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulsing ? 1.4 : 1.0)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulsing)
            }
            Circle()
                .fill(pulseColor)
                .frame(width: 7, height: 7)
        }
        .onAppear { pulsing = true }
    }

    private var pulseColor: Color {
        if score > 0.85 { return Color(red: 0.98, green: 0.75, blue: 0.25) }
        if score > 0.70 { return Color(red: 0.55, green: 0.85, blue: 0.65) }
        return Color(white: 0.40)
    }
}

// MARK: - Press style

private struct LivingMemoryPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Date helper

private extension Date {
    var relativeLabel: String {
        let diff = Date().timeIntervalSince(self)
        if diff < 3600  { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        if diff < 604800 { return "\(Int(diff / 86400))d" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: self)
    }
}

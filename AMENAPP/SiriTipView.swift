//
//  SiriTipView.swift
//  AMENAPP
//
//  Displays Siri shortcut tips to educate users about voice commands.
//  Shows contextual tips based on user location in the app.
//

import SwiftUI
import TipKit

@available(iOS 16.0, *)
struct SiriTipView: View {
    let tipType: SiriTipType
    @State private var isDismissed = false
    
    var body: some View {
        if !isDismissed {
            HStack(spacing: 12) {
                // Siri icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.3, blue: 1.0),
                                    Color(red: 0.6, green: 0.4, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                // Tip content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Siri Tip")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isDismissed = true
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(6)
                                .background(Circle().fill(Color.white.opacity(0.05)))
                        }
                    }
                    
                    Text(tipType.message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .lineSpacing(2)
                    
                    Text("\"\(tipType.phrase)\"")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.8))
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

enum SiriTipType {
    case prayer
    case testimony
    case berean
    case devotional
    
    var message: String {
        switch self {
        case .prayer:
            return "Ask Siri to post a prayer request"
        case .testimony:
            return "Share your testimony with Siri"
        case .berean:
            return "Ask Berean questions using Siri"
        case .devotional:
            return "Open your daily devotional with Siri"
        }
    }
    
    var phrase: String {
        switch self {
        case .prayer:
            return "Hey Siri, post a prayer request"
        case .testimony:
            return "Hey Siri, share a testimony"
        case .berean:
            return "Hey Siri, ask Berean"
        case .devotional:
            return "Hey Siri, show my devotional"
        }
    }
}

// MARK: - Floating Siri Tip Banner (appears at top of screen)

@available(iOS 16.0, *)
struct FloatingSiriTip: View {
    let tipType: SiriTipType
    @Binding var isShowing: Bool
    
    var body: some View {
        VStack {
            if isShowing {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.3, blue: 1.0),
                                    Color(red: 0.6, green: 0.4, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Try this with Siri")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("\"\(tipType.phrase)\"")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isShowing = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Spacer()
        }
    }
}

//
//  BereanStructuredResponseView.swift
//  AMENAPP
//
//  Card-based response rendering for Berean AI messages.
//  Displays structured sections (Direct Answer, Meaning, Context, Application)
//  as distinct Liquid Glass cards with follow-up action chips.
//

import SwiftUI

struct BereanStructuredResponseView: View {
    let message: BereanChatMsg

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let structure = message.structure {
                structuredContent(structure)
            } else if !message.content.isEmpty {
                plainContent
            }
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    // MARK: - Structured Content

    @ViewBuilder
    private func structuredContent(_ structure: BereanResponseStructure) -> some View {
        if let answer = structure.directAnswer, !answer.isEmpty {
            responseCard(
                label: "Direct Answer",
                icon: "checkmark.circle.fill",
                accentColor: Color(red: 0.56, green: 0.61, blue: 0.70),
                content: answer,
                isBold: true
            )
        }

        if let meaning = structure.meaning, !meaning.isEmpty {
            responseCard(
                label: "Meaning",
                icon: "lightbulb.fill",
                accentColor: Color(red: 0.73, green: 0.69, blue: 0.58),
                content: meaning
            )
        }

        if let context = structure.context, !context.isEmpty {
            responseCard(
                label: "Context",
                icon: "book.pages.fill",
                accentColor: Color(red: 0.58, green: 0.65, blue: 0.71),
                content: context
            )
        }

        if let application = structure.application, !application.isEmpty {
            responseCard(
                label: "Application",
                icon: "heart.fill",
                accentColor: Color(red: 0.76, green: 0.65, blue: 0.66),
                content: application
            )
        }

        if !structure.followUpActions.isEmpty {
            followUpChips(structure.followUpActions)
        }
    }

    // MARK: - Response Card

    private func responseCard(
        label: String,
        icon: String,
        accentColor: Color,
        content: String,
        isBold: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(accentColor)
                Text(label)
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.black.opacity(0.48))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.bottom, 2)

            Text(content)
                .font(isBold ? AMENFont.semiBold(17) : AMENFont.regular(15))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.10),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
        )
    }

    // MARK: - Follow-Up Chips

    private func followUpChips(_ actions: [BereanResponseStructure.FollowUpAction]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions) { action in
                    HStack(spacing: 5) {
                        Image(systemName: action.icon)
                            .font(.systemScaled(11, weight: .medium))
                        Text(action.title)
                            .font(AMENFont.regular(13))
                    }
                    .foregroundStyle(.black.opacity(0.68))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.74))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
                            )
                    )
                }
            }
        }
    }

    // MARK: - Plain Content Fallback

    private var plainContent: some View {
        Text(message.content)
            .font(.system(size: 16, weight: .regular))
            .foregroundColor(.black)
            .lineSpacing(2)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.88))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 9, y: 3)
            )
    }
}

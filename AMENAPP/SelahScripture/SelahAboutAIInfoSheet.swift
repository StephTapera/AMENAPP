//
//  SelahAboutAIInfoSheet.swift
//  AMENAPP
//
//  User-facing transparency sheet that explains exactly what AI does in
//  Selah, what it doesn't do, and how to verify outputs. Apple's AI
//  guidance treats user comprehension as a first-class requirement; this
//  is the screen that earns that.
//
//  No content here is dynamic — everything is plain, honest, hand-written
//  copy. Nothing here calls an LLM.
//

import SwiftUI

struct SelahAboutAIInfoSheet: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    section(
                        title: "What AI does in Selah",
                        bullets: [
                            "Summarizes and reformats Berean study responses into reading layouts (TL;DR, Bullets, Outline, Essay, Steps).",
                            "Offers an optional Berean Context deeper-study view with historical / literary notes for a passage.",
                            "Lets you ask the Scripture Companion a short, grounded follow-up question while reading.",
                            "Lets you rewrite your own reflection into a simpler / poetic / journal / prayer tone — only when you ask."
                        ]
                    )

                    section(
                        title: "What it never does",
                        bullets: [
                            "Make up scripture text. The Bible text shown in the reader is real King James Version (public domain).",
                            "Invent quotations from commentators or scholars.",
                            "Speak with certainty when scholarship is contested.",
                            "Rewrite your reflection automatically — every rewrite is started by you and clearly labeled."
                        ]
                    )

                    section(
                        title: "How to verify what you read",
                        bullets: [
                            "Every AI-generated panel is marked with the “AI Generated” badge.",
                            "Citations appear next to AI answers when scripture references are used.",
                            "If something feels off, compare against your trusted translation, or ask your pastor.",
                            "AI can make mistakes. The Word of God doesn't."
                        ]
                    )

                    section(
                        title: "Safety",
                        bullets: [
                            "When the app detects crisis language in what you type (self-harm, ending your life, etc.), it does NOT send your text to the model. Instead it shows you crisis-line guidance.",
                            "If you're in crisis right now, please reach out: 988 in the US, 116 123 (Samaritans) in the UK/Ireland, findahelpline.com worldwide.",
                            "Your reflections, reactions, and prayed-through markers are private to you by default."
                        ]
                    )

                    Text("Selah is meant to help you sit with scripture. If anything you see disrupts that, turn the AI features off in Settings and the calm reader still works on its own.")
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("About Selah AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            SelahAIGeneratedBadge()
            Text("Honest AI in Selah")
                .font(.systemScaled(22, weight: .semibold, design: .serif))
                .foregroundStyle(.primary)
            Text("Selah uses AI to help you read scripture more deeply — never to replace it.")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private func section(title: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.systemScaled(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            ForEach(bullets, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(.secondary)
                    Text(line)
                        .font(.systemScaled(14))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 6)
    }
}

#if DEBUG
#Preview("About Selah AI") {
    SelahAboutAIInfoSheet()
}
#endif

// AmenCreationTemplateLibrary.swift
// AMENAPP
// Template library for the Universal Create platform.
// Provides faith-context post templates that pre-fill the composer
// with structured prompts, scripture placeholders, and hashtag seeds.

import SwiftUI

// MARK: - Model

struct AmenCreationTemplate: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let tintColor: Color
    let intent: AmenCreationIntent
    let bodyTemplate: String
    let seedHashtags: [String]
    let scriptureHint: String?
    let category: TemplateCategory

    enum TemplateCategory: String, CaseIterable, Identifiable {
        case devotional
        case testimony
        case prayerRequest
        case discussion
        case encouragement
        case sermonNotes
        case celebration

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .devotional:   return "Devotional"
            case .testimony:    return "Testimony"
            case .prayerRequest: return "Prayer Request"
            case .discussion:   return "Discussion"
            case .encouragement: return "Encouragement"
            case .sermonNotes:  return "Sermon Notes"
            case .celebration:  return "Celebration"
            }
        }
    }
}

// MARK: - Template Catalog

extension AmenCreationTemplate {
    static let catalog: [AmenCreationTemplate] = [

        AmenCreationTemplate(
            id: "morning_devotional",
            name: "Morning Devotional",
            description: "Share what God placed on your heart this morning",
            icon: "sunrise.fill",
            tintColor: .orange,
            intent: .textPost,
            bodyTemplate: "This morning, God spoke to me through…\n\nScripture: {VERSE}\n\n{REFLECTION}\n\nLet's carry this truth into our day together.",
            seedHashtags: ["#MorningDevotion", "#DailyWord", "#FaithFirstThing"],
            scriptureHint: "Psalm 5:3",
            category: .devotional
        ),

        AmenCreationTemplate(
            id: "prayer_request",
            name: "Prayer Request",
            description: "Ask your community to stand with you in prayer",
            icon: "hands.sparkles.fill",
            tintColor: .purple,
            intent: .textPost,
            bodyTemplate: "I'm asking for prayer over…\n\n{SITUATION}\n\nScripture I'm standing on: {VERSE}\n\nThank you for standing with me. 🙏",
            seedHashtags: ["#PrayerRequest", "#StandingInFaith", "#CommunityPrayer"],
            scriptureHint: "Philippians 4:6",
            category: .prayerRequest
        ),

        AmenCreationTemplate(
            id: "testimony",
            name: "Testimony",
            description: "Declare what God has done in your life",
            icon: "star.fill",
            tintColor: .yellow,
            intent: .textPost,
            bodyTemplate: "I have to share what God did…\n\n{STORY}\n\nGod is faithful. He will do it for you too.\n\n\"{VERSE}\" — {REFERENCE}",
            seedHashtags: ["#Testimony", "#GodIsFaithful", "#Amen"],
            scriptureHint: "Revelation 12:11",
            category: .testimony
        ),

        AmenCreationTemplate(
            id: "discussion_prompt",
            name: "Discussion Prompt",
            description: "Spark a faith conversation in your community",
            icon: "bubble.left.and.bubble.right.fill",
            tintColor: .blue,
            intent: .discussionPrompt,
            bodyTemplate: "Question for the community:\n\n{QUESTION}\n\nDropping my thoughts below ⬇️",
            seedHashtags: ["#FaithConversation", "#AskTheChurch", "#CommunityDiscussion"],
            scriptureHint: nil,
            category: .discussion
        ),

        AmenCreationTemplate(
            id: "encouragement",
            name: "Encouragement",
            description: "Speak life into someone scrolling today",
            icon: "heart.fill",
            tintColor: .pink,
            intent: .textPost,
            bodyTemplate: "To whoever needs to hear this today:\n\n{MESSAGE}\n\n\"{VERSE}\" — {REFERENCE}\n\nYou are not alone. God sees you. 🕊️",
            seedHashtags: ["#Encouragement", "#YouAreNotAlone", "#GodSeesYou"],
            scriptureHint: "Isaiah 41:10",
            category: .encouragement
        ),

        AmenCreationTemplate(
            id: "sermon_notes",
            name: "Sermon Notes",
            description: "Share your Sunday morning insights",
            icon: "note.text",
            tintColor: .green,
            intent: .churchNote,
            bodyTemplate: "📖 Sermon: {SERMON_TITLE}\n🏛️ Church: {CHURCH_NAME}\n\nKey Points:\n• {POINT_1}\n• {POINT_2}\n• {POINT_3}\n\nScripture: {VERSE}\n\nPersonal takeaway: {TAKEAWAY}",
            seedHashtags: ["#SermonNotes", "#SundayService", "#ChurchFamily"],
            scriptureHint: nil,
            category: .sermonNotes
        ),

        AmenCreationTemplate(
            id: "celebration",
            name: "Celebration",
            description: "Praise God for His goodness publicly",
            icon: "party.popper.fill",
            tintColor: .accentColor,
            intent: .textPost,
            bodyTemplate: "Giving God all the glory for…\n\n{CELEBRATION}\n\nWho can shout Amen with me?! 🙌\n\n\"{VERSE}\" — {REFERENCE}",
            seedHashtags: ["#GodIsGood", "#ThankYouJesus", "#Amen"],
            scriptureHint: "Psalm 118:24",
            category: .celebration
        ),

        AmenCreationTemplate(
            id: "selah_reflection",
            name: "Selah Reflection",
            description: "Share a quiet moment of spiritual insight",
            icon: "sparkles",
            tintColor: .indigo,
            intent: .selahReflection,
            bodyTemplate: "Selah. Pause and consider:\n\n{REFLECTION}\n\nScripture I'm sitting with: {VERSE}\n\n— Shared from a quiet moment with God",
            seedHashtags: ["#Selah", "#QuietTime", "#SpiritualGrowth"],
            scriptureHint: "Psalm 46:10",
            category: .devotional
        ),
    ]

    static func templates(for category: TemplateCategory) -> [AmenCreationTemplate] {
        catalog.filter { $0.category == category }
    }
}

// MARK: - Template Library View

struct AmenCreationTemplateLibraryView: View {
    var onSelect: (AmenCreationTemplate) -> Void
    var onDismiss: (() -> Void)? = nil

    @State private var selectedCategory: AmenCreationTemplate.TemplateCategory? = nil
    @State private var searchText = ""

    private var filteredTemplates: [AmenCreationTemplate] {
        var list = AmenCreationTemplate.catalog
        if let cat = selectedCategory {
            list = list.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                $0.description.lowercased().contains(q) ||
                $0.category.displayName.lowercased().contains(q)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter
                categoryFilterRow

                // Template grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filteredTemplates) { template in
                            AmenTemplateLibraryCard(template: template) {
                                onSelect(template)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search templates")
            .toolbar {
                if let onDismiss {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel", action: onDismiss)
                    }
                }
            }
        }
    }

    private var categoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryPill(nil, label: "All")
                ForEach(AmenCreationTemplate.TemplateCategory.allCases) { cat in
                    categoryPill(cat, label: cat.displayName)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func categoryPill(_ cat: AmenCreationTemplate.TemplateCategory?, label: String) -> some View {
        let isSelected = selectedCategory == cat
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = cat
            }
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
                )
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Template Card

private struct AmenTemplateLibraryCard: View {
    let template: AmenCreationTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                // Icon
                ZStack {
                    Circle()
                        .fill(template.tintColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: template.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(template.tintColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    Text(template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if let scripture = template.scriptureHint {
                    Text(scripture)
                        .font(.caption2)
                        .foregroundStyle(template.tintColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(template.tintColor.opacity(0.08), in: Capsule())
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(template.tintColor.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

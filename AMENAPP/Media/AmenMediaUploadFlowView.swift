// AmenMediaUploadFlowView.swift
// AMENAPP
//
// Multi-step upload wizard. AI-generated metadata requires explicit creator
// approval per field before publishing — "Draft — Review before publishing."
// Authenticity badge previewed at final step.

import SwiftUI
import PhotosUI

// MARK: - Models

enum MediaUploadType: String, CaseIterable, Identifiable {
    case photo       = "Photo"
    case video       = "Video"
    case clip        = "Clip"
    case album       = "Album"
    case sermon      = "Sermon / Teaching"
    case communityUpdate = "Community Update"
    case testimony   = "Testimony"
    case creative    = "Creative"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .photo:           return "photo"
        case .video:           return "video"
        case .clip:            return "play.rectangle"
        case .album:           return "rectangle.stack"
        case .sermon:          return "book.closed"
        case .communityUpdate: return "megaphone"
        case .testimony:       return "heart.text.clipboard"
        case .creative:        return "paintbrush"
        }
    }

    var description: String {
        switch self {
        case .photo:           return "A single moment or image"
        case .video:           return "Up to 10 minutes of footage"
        case .clip:            return "Short-form under 90 seconds"
        case .album:           return "A curated set of photos"
        case .sermon:          return "Teaching or message content"
        case .communityUpdate: return "News or announcement for your community"
        case .testimony:       return "A personal story of faith"
        case .creative:        return "Art, poetry, or original expression"
        }
    }
}

enum MediaAudience: String, CaseIterable, Identifiable {
    case everyone    = "Everyone"
    case community   = "My Communities"
    case friendsOnly = "Friends Only"
    case private_    = "Only Me"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .everyone:    return "globe"
        case .community:   return "person.3"
        case .friendsOnly: return "person.2"
        case .private_:    return "lock"
        }
    }
}

enum UploadStep: Int, CaseIterable {
    case typeSelection = 0
    case mediaPick     = 1
    case captionAudience = 2
    case aiReview      = 3
    case publish       = 4
}

struct AIMetadataDraft {
    var captionSuggestion: String
    var altText: String
    var transcriptSnippet: String
    var topicTags: [String]

    var captionApproved: Bool   = false
    var altTextApproved: Bool   = false
    var transcriptApproved: Bool = false
    var tagsApproved: Bool      = false

    var allApproved: Bool {
        captionApproved && altTextApproved && transcriptApproved && tagsApproved
    }
}

// MARK: - Main View

struct AmenMediaUploadFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step: UploadStep = .typeSelection

    @State private var selectedType: MediaUploadType?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var selectedImageData: Data?
    @State private var caption = ""
    @State private var audience: MediaAudience = .community
    @State private var category = ""
    @State private var aiDraft = AIMetadataDraft(
        captionSuggestion: "A moment of quiet prayer before the morning rush — may we all start our days grounded in His presence. 🙏",
        altText: "Person kneeling in morning light by a window, hands clasped.",
        transcriptSnippet: "\"Lord, before this day begins…\"",
        topicTags: ["Morning Prayer", "Devotional", "Faith"]
    )

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                stepContent
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                if step.rawValue > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Back") { withAnimation(.spring(duration: 0.3)) { step = UploadStep(rawValue: step.rawValue - 1) ?? .typeSelection } }
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .toolbarColorScheme(.dark)
        }
    }

    private var navigationTitle: String {
        switch step {
        case .typeSelection:   return "What are you sharing?"
        case .mediaPick:       return "Choose media"
        case .captionAudience: return "Add details"
        case .aiReview:        return "Review AI draft"
        case .publish:         return "Ready to share"
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .typeSelection:   TypeSelectionStep(selected: $selectedType, onNext: advance)
        case .mediaPick:       MediaPickStep(items: $pickerItems, imageData: $selectedImageData, type: selectedType ?? .photo, onNext: advance)
        case .captionAudience: CaptionAudienceStep(caption: $caption, audience: $audience, category: $category, onNext: advance)
        case .aiReview:        AIReviewStep(draft: $aiDraft, caption: caption, onNext: advance)
        case .publish:         PublishStep(type: selectedType ?? .photo, audience: audience, draft: aiDraft, onPublish: { dismiss() })
        }
    }

    private func advance() {
        withAnimation(.spring(duration: 0.35)) {
            step = UploadStep(rawValue: step.rawValue + 1) ?? .publish
        }
    }
}

// MARK: - Step 1: Type Selection

private struct TypeSelectionStep: View {
    @Binding var selected: MediaUploadType?
    let onNext: () -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(MediaUploadType.allCases) { type in
                        TypeCard(type: type, isSelected: selected == type)
                            .onTapGesture { selected = type }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
            bottomBar(enabled: selected != nil) { onNext() }
        }
    }
}

private struct TypeCard: View {
    let type: MediaUploadType
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: type.icon)
                .font(.systemScaled(22, weight: .medium))
                .foregroundStyle(isSelected ? Color(red: 0.4, green: 0.9, blue: 0.7) : .white.opacity(0.8))

            Text(type.rawValue)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.white)

            Text(type.description)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(isSelected ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color(red: 0.4, green: 0.9, blue: 0.7).opacity(0.6) : .white.opacity(0.1), lineWidth: 1)
        )
        .animation(.spring(duration: 0.25), value: isSelected)
    }
}

// MARK: - Step 2: Media Pick

private struct MediaPickStep: View {
    @Binding var items: [PhotosPickerItem]
    @Binding var imageData: Data?
    let type: MediaUploadType
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            PhotosPicker(
                selection: $items,
                maxSelectionCount: type == .album ? 10 : 1,
                matching: type == .video || type == .clip || type == .sermon ? .videos : .images
            ) {
                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.plus")
                        .font(.systemScaled(48, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))

                    Text(items.isEmpty ? "Tap to choose from library" : "\(items.count) item\(items.count == 1 ? "" : "s") selected")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.white)

                    Text("Your media stays on-device until you confirm publish.")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [8, 6]))
                )
                .padding(.horizontal, 24)
            }
            .onChange(of: items) { _, newItems in
                Task {
                    if let item = newItems.first,
                       let data = try? await item.loadTransferable(type: Data.self) {
                        imageData = data
                    }
                }
            }

            Spacer()
            bottomBar(enabled: !items.isEmpty) { onNext() }
        }
    }
}

// MARK: - Step 3: Caption + Audience

private struct CaptionAudienceStep: View {
    @Binding var caption: String
    @Binding var audience: MediaAudience
    @Binding var category: String
    let onNext: () -> Void
    @FocusState private var captionFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Caption
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("CAPTION")
                    TextEditor(text: $caption)
                        .focused($captionFocused)
                        .frame(minHeight: 100)
                        .padding(14)
                        .scrollContentBackground(.hidden)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        )
                        .foregroundStyle(.white)
                        .font(.custom("OpenSans-Regular", size: 15))
                    Text("Optional — AI will suggest one if left blank.")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }

                // Audience
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("WHO CAN SEE THIS")
                    ForEach(MediaAudience.allCases) { opt in
                        HStack(spacing: 12) {
                            Image(systemName: opt.icon)
                                .font(.systemScaled(15))
                                .frame(width: 22)
                                .foregroundStyle(audience == opt ? Color(red: 0.4, green: 0.9, blue: 0.7) : .white.opacity(0.6))
                            Text(opt.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.white)
                            Spacer()
                            if audience == opt {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 0.7))
                            }
                        }
                        .padding(14)
                        .background(.white.opacity(audience == opt ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { audience = opt }
                    }
                }

                // Category / intent
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("CATEGORY / INTENT (optional)")
                    TextField("e.g. Devotional, Worship, Family", text: $category)
                        .padding(14)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
                        .foregroundStyle(.white)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .tint(Color(red: 0.4, green: 0.9, blue: 0.7))
                }

                bottomBar(enabled: true) { onNext() }
                    .padding(.top, 8)
            }
            .padding(20)
        }
    }
}

// MARK: - Step 4: AI Metadata Review

private struct AIReviewStep: View {
    @Binding var draft: AIMetadataDraft
    let caption: String
    let onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header notice
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.sparkles")
                        .font(.systemScaled(14))
                    Text("Draft — Review before publishing")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                    Spacer()
                }
                .padding(14)
                .background(Color(red: 0.8, green: 0.6, blue: 0.0).opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.8, green: 0.6, blue: 0.0).opacity(0.4), lineWidth: 1))
                .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.3))

                Text("AI-generated metadata cannot publish as final without your approval.")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Caption field (may be AI-generated or user's own)
                MetadataReviewCard(
                    label: "CAPTION",
                    icon: "text.alignleft",
                    content: caption.isEmpty ? draft.captionSuggestion : caption,
                    isApproved: $draft.captionApproved,
                    isAI: caption.isEmpty
                )

                MetadataReviewCard(
                    label: "ALT TEXT",
                    icon: "eye",
                    content: draft.altText,
                    isApproved: $draft.altTextApproved,
                    isAI: true
                )

                MetadataReviewCard(
                    label: "TRANSCRIPT SNIPPET",
                    icon: "captions.bubble",
                    content: draft.transcriptSnippet,
                    isApproved: $draft.transcriptApproved,
                    isAI: true
                )

                // Topic tags
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("TOPIC TAGS", systemImage: "tag")
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .textCase(.uppercase)
                        Spacer()
                        approveButton(approved: $draft.tagsApproved)
                    }
                    FlexTagCloud(tags: draft.topicTags)
                    approvalStatus(draft.tagsApproved)
                }
                .padding(16)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))

                bottomBar(enabled: draft.allApproved, label: "Looks good — continue") { onNext() }
                    .padding(.top, 8)
            }
            .padding(20)
        }
    }
}

private struct MetadataReviewCard: View {
    let label: String
    let icon: String
    let content: String
    @Binding var isApproved: Bool
    let isAI: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                if isAI {
                    Text("AI")
                        .font(.custom("OpenSans-SemiBold", size: 10))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(red: 0.8, green: 0.6, blue: 0.0).opacity(0.25), in: Capsule())
                        .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.3))
                }
                Spacer()
                approveButton(approved: $isApproved)
            }
            Text(content)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            approvalStatus(isApproved)
        }
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isApproved ? Color(red: 0.4, green: 0.9, blue: 0.7).opacity(0.4) : .white.opacity(0.1), lineWidth: 1)
        )
        .animation(.spring(duration: 0.25), value: isApproved)
    }
}

@ViewBuilder
private func approveButton(approved: Binding<Bool>) -> some View {
    Button {
        withAnimation(.spring(duration: 0.2)) { approved.wrappedValue.toggle() }
    } label: {
        HStack(spacing: 4) {
            Image(systemName: approved.wrappedValue ? "checkmark.circle.fill" : "circle")
                .font(.systemScaled(16))
            Text(approved.wrappedValue ? "Approved" : "Approve")
                .font(.custom("OpenSans-SemiBold", size: 12))
        }
        .foregroundStyle(approved.wrappedValue ? Color(red: 0.4, green: 0.9, blue: 0.7) : .white.opacity(0.5))
    }
}

@ViewBuilder
private func approvalStatus(_ approved: Bool) -> some View {
    if approved {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.systemScaled(10, weight: .semibold))
            Text("You approved this")
                .font(.custom("OpenSans-Regular", size: 11))
        }
        .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 0.7).opacity(0.8))
        .transition(.opacity)
    }
}

private struct FlexTagCloud: View {
    let tags: [String]

    var body: some View {
        // Simple horizontal wrapping using ViewThatFits approach
        HStack(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white.opacity(0.12), in: Capsule())
            }
        }
    }
}

// MARK: - Step 5: Publish

private struct PublishStep: View {
    let type: MediaUploadType
    let audience: MediaAudience
    let draft: AIMetadataDraft
    let onPublish: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Authenticity badge preview
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.systemScaled(48))
                        .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 0.7))

                    Text("Authenticity Badge")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.white)

                    Text("All AI-generated metadata was reviewed and approved by you. This post will carry a creator-verified badge.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(28)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color(red: 0.4, green: 0.9, blue: 0.7).opacity(0.35), lineWidth: 1)
                )

                // Summary
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("PUBLISH SUMMARY")

                    summaryRow(label: "Type", value: type.rawValue)
                    summaryRow(label: "Audience", value: audience.rawValue)
                    summaryRow(label: "Tags", value: draft.topicTags.map { "#\($0)" }.joined(separator: " "))
                }
                .padding(18)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))

                // Publish button
                Button(action: onPublish) {
                    Text("Share to AMEN")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 0.4, green: 0.9, blue: 0.7), in: RoundedRectangle(cornerRadius: 14))
                }

                Text("Your media will be reviewed for community guidelines before appearing in discovery.")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Shared helpers

@ViewBuilder
private func sectionLabel(_ text: String) -> some View {
    Text(text)
        .font(.custom("OpenSans-SemiBold", size: 11))
        .foregroundStyle(.white.opacity(0.45))
        .tracking(1.2)
}

@ViewBuilder
private func bottomBar(enabled: Bool, label: String = "Continue", action: @escaping () -> Void) -> some View {
    VStack(spacing: 0) {
        Divider().background(.white.opacity(0.08))
        Button(action: action) {
            Text(label)
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(enabled ? .black : .white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    enabled
                        ? Color(red: 0.4, green: 0.9, blue: 0.7)
                        : Color.white.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 14)
                )
        }
        .disabled(!enabled)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .animation(.spring(duration: 0.25), value: enabled)
    }
    .background(.black.opacity(0.6))
}

#Preview {
    AmenMediaUploadFlowView()
}

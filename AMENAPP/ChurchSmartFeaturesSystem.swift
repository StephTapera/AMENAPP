// ChurchSmartFeaturesSystem.swift
// AMENAPP
//
// Smart church features:
//   1. SpiritualNeedsRouter      — intent-first church matching
//   2. PostVisitReflectionSystem — 24h follow-up card + notes integration
//   3. VisitTogetherSystem       — invite flow + #OpenTable + shareable card
//   4. LiveChurchIntelligenceView — next service, parking tips, live signals
//
// Pure UI + local state — no Firebase imports.
// Design: white bg, .ultraThinMaterial glass, AMENFont, black primary.

import SwiftUI
import UIKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 1 · Spiritual Needs Router
// ─────────────────────────────────────────────────────────────────────────────

enum SpiritualNeed: String, CaseIterable, Identifiable {
    case solidTeaching    = "I need solid biblical teaching"
    case healingPrayer    = "I need healing and prayer"
    case familyChurch     = "I need a church for my family"
    case justMoved        = "I just moved here"
    case community        = "I want community and belonging"
    case returningToFaith = "I'm coming back to faith"
    case seriousScripture = "I want verse-by-verse teaching"
    case recovery         = "I need a church with a recovery ministry"
    case multiCultural    = "I want a diverse, multicultural church"
    case youngAdults      = "I want a strong young adults community"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .solidTeaching:    return "book.closed"
        case .healingPrayer:    return "cross.circle"
        case .familyChurch:     return "house"
        case .justMoved:        return "map"
        case .community:        return "heart.circle"
        case .returningToFaith: return "arrow.uturn.left.circle"
        case .seriousScripture: return "text.book.closed"
        case .recovery:         return "figure.walk.circle"
        case .multiCultural:    return "globe.americas"
        case .youngAdults:      return "person.3"
        }
    }

    /// Score modifier keys map to church profile attributes / fit tags.
    /// Values are multiplicative boosts (1.0 = +0%, 1.3 = +30%).
    var fitModifiers: [String: Double] {
        switch self {
        case .solidTeaching:
            return ["strongTeaching": 1.4, "deepBibleTeaching": 1.4, "expository": 1.3]
        case .healingPrayer:
            return ["recoveryHealing": 1.5, "charismatic": 1.2, "prayerFocused": 1.4]
        case .familyChurch:
            return ["hasKidsMinistry": 1.5, "families": 1.4, "multiGenerational": 1.2]
        case .justMoved:
            return ["firstTimeVisitors": 1.4, "goodForNewcomers": 1.5, "welcoming": 1.3]
        case .community:
            return ["strongCommunity": 1.5, "smallGroups": 1.3, "communityOriented": 1.4]
        case .returningToFaith:
            return ["seekers": 1.5, "welcoming": 1.4, "goodForNewcomers": 1.3]
        case .seriousScripture:
            return ["deepBibleTeaching": 1.5, "strongTeaching": 1.4, "expository": 1.5]
        case .recovery:
            return ["recoveryHealing": 1.6, "recoveryFriendly": 1.6, "strongCommunity": 1.2]
        case .multiCultural:
            return ["multiCultural": 1.5, "diverse": 1.4, "bilingual": 1.3]
        case .youngAdults:
            return ["greatForYoungAdults": 1.5, "youngAdults": 1.5, "singles": 1.2]
        }
    }
}

struct SpiritualNeedsRouterView: View {
    @Binding var selectedNeeds: Set<SpiritualNeed>
    let onFind: ([SpiritualNeed]) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What are you looking for?")
                    .font(AMENFont.bold(20))
                    .foregroundStyle(Color.black)
                Text("Select up to 3 — we'll find churches that match.")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(Color(white: 0.55))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(SpiritualNeed.allCases) { need in
                    needCard(need)
                }
            }
            .padding(.horizontal, 16)

            // CTA
            Button {
                onFind(Array(selectedNeeds))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(14, weight: .semibold))
                    Text("Find churches for my needs")
                        .font(AMENFont.bold(15))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    selectedNeeds.isEmpty ? Color(white: 0.82) : Color.black,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedNeeds.isEmpty)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: selectedNeeds.isEmpty)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func needCard(_ need: SpiritualNeed) -> some View {
        let isSelected = selectedNeeds.contains(need)
        let atMax      = selectedNeeds.count >= 3 && !isSelected

        Button {
            guard !atMax else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                if isSelected { selectedNeeds.remove(need) }
                else          { selectedNeeds.insert(need) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: need.icon)
                    .font(.systemScaled(20))
                    .foregroundStyle(isSelected ? Color.white : Color.black)

                Text(need.displayName)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(isSelected ? Color.white : Color.black)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.black : Color.white.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isSelected ? Color.clear : Color(white: 0.88).opacity(0.5))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? Color.clear : Color(white: 0.88).opacity(0.5),
                        lineWidth: 0.5
                    )
            )
            .opacity(atMax ? 0.45 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isSelected)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 2 · Post-Visit Reflection System
// ─────────────────────────────────────────────────────────────────────────────

enum PostVisitQuestion: String, CaseIterable, Codable {
    case howDidItGo        = "How did it go?"
    case feltWelcomed      = "Did you feel welcomed?"
    case spirituallyFed    = "Did you feel spiritually fed?"
    case wouldReturn       = "Would you go back?"
    case bestFitFor        = "Who would this church be great for?"
    case practicalTip      = "Any tips for future first-time visitors?"
}

struct PostVisitReflection: Identifiable, Codable {
    var id: String = UUID().uuidString
    var churchId: String
    var churchName: String
    var visitDate: Date
    var quickRating: QuickRating?
    var responses: [String: String] = [:]  // PostVisitQuestion.rawValue → answer
    var wouldReturn: Bool?
    var savedToChurchNotes: Bool  = false
    var sharedPublicly: Bool      = false

    enum QuickRating: String, Codable {
        case great, good, notForMe
        var label: String {
            switch self {
            case .great:    return "It was great"
            case .good:     return "Pretty good"
            case .notForMe: return "Not for me"
            }
        }
        var icon: String {
            switch self {
            case .great:    return "star.fill"
            case .good:     return "hand.thumbsup"
            case .notForMe: return "xmark.circle"
            }
        }
    }
}

struct PostVisitReflectionCard: View {
    let reflection: PostVisitReflection
    let onWriteNote: () -> Void
    let onShareExperience: () -> Void
    let onFollowChurch: () -> Void
    let onFindSimilar: () -> Void
    let onDismiss: () -> Void

    @State private var selectedRating: PostVisitReflection.QuickRating? = nil
    @State private var feltWelcomed: Bool? = nil
    @State private var spirituallyFed: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("How was your visit?")
                        .font(AMENFont.bold(18))
                        .foregroundStyle(Color.black)
                    Spacer()
                    // Dismiss
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(Color(white: 0.65))
                            .padding(6)
                            .background(Color(white: 0.93), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Text(reflection.churchName)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(Color(white: 0.45))
                Text(formatDate(reflection.visitDate))
                    .font(AMENFont.regular(12))
                    .foregroundStyle(Color(white: 0.65))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().padding(.horizontal, 16)

            // Quick-tap rating
            VStack(alignment: .leading, spacing: 10) {
                Text("Overall")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(Color(white: 0.5))
                    .padding(.horizontal, 20)

                HStack(spacing: 8) {
                    ForEach(PostVisitReflection.QuickRating.allCases, id: \.self) { rating in
                        Button {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                selectedRating = rating
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: rating.icon)
                                    .font(.systemScaled(12))
                                Text(rating.label)
                                    .font(AMENFont.semiBold(12))
                            }
                            .foregroundStyle(selectedRating == rating ? Color.white : Color(white: 0.3))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedRating == rating ? Color.black : Color.white.opacity(0.55),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        selectedRating == rating ? Color.clear : Color(white: 0.88).opacity(0.5),
                                        lineWidth: 0.5
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 14)

            // Quick-yes/no questions
            VStack(spacing: 0) {
                quickYesNo(question: "Did you feel welcomed?", answer: $feltWelcomed)
                Divider().padding(.leading, 20)
                quickYesNo(question: "Did you feel spiritually fed?", answer: $spirituallyFed)
            }
            .padding(.horizontal, 16)

            Divider().padding(.horizontal, 16).padding(.top, 4)

            // Action row
            VStack(spacing: 0) {
                actionRow(icon: "note.text.badge.plus", label: "Write a note",          action: onWriteNote)
                Divider().padding(.leading, 52)
                actionRow(icon: "star.bubble",          label: "Share your experience", action: onShareExperience)
                Divider().padding(.leading, 52)
                actionRow(icon: "bell",                 label: "Follow this church",    action: onFollowChurch)
                Divider().padding(.leading, 52)
                actionRow(icon: "sparkles",             label: "Find similar churches", action: onFindSimilar)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            // Dismiss text
            Button(action: onDismiss) {
                Text("Dismiss")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(Color(white: 0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(white: 0.88).opacity(0.5))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func quickYesNo(question: String, answer: Binding<Bool?>) -> some View {
        HStack {
            Text(question)
                .font(AMENFont.regular(14))
                .foregroundStyle(Color.black)
            Spacer()
            HStack(spacing: 6) {
                yesNoButton(label: "Yes", value: true,  binding: answer)
                yesNoButton(label: "No",  value: false, binding: answer)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func yesNoButton(label: String, value: Bool, binding: Binding<Bool?>) -> some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                binding.wrappedValue = value
            }
        } label: {
            Text(label)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(binding.wrappedValue == value ? Color.white : Color(white: 0.4))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    binding.wrappedValue == value ? Color.black : Color.white.opacity(0.55),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actionRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.systemScaled(16))
                    .foregroundStyle(Color.black)
                    .frame(width: 22)
                Text(label)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(Color.black)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        return f.string(from: date)
    }
}

extension PostVisitReflection.QuickRating: CaseIterable {
    static var allCases: [PostVisitReflection.QuickRating] { [.great, .good, .notForMe] }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 3 · Visit Together System
// ─────────────────────────────────────────────────────────────────────────────

struct ChurchVisitInvite: Identifiable, Codable {
    var id: String         = UUID().uuidString
    var churchId: String
    var churchName: String
    var serviceDate: Date
    var serviceTime: String
    var inviterName: String
    var inviterId: String
    var message: String?
    var isPublic: Bool
}

struct VisitTogetherView: View {
    let church: VisitTogetherChurch

    @State private var showInviteSheet      = false
    @State private var showOpenTableComposer = false
    @State private var showShareCard         = false
    @State private var showSavedConfirm      = false

    /// Lightweight church info — avoids coupling to ChurchEntity/ChurchRichProfile
    struct VisitTogetherChurch {
        let id: String
        let name: String
        let serviceTime: String        // "Sunday 10:30 AM"
        let distanceMiles: Double?
        let address: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Text("Go with someone")
                    .font(AMENFont.bold(16))
                    .foregroundStyle(Color.black)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Option rows
            VStack(spacing: 0) {
                optionRow(
                    icon:   "person.badge.plus",
                    label:  "Invite a friend",
                    detail: "Send a visit invite via DM"
                ) {
                    showInviteSheet = true
                }
                Divider().padding(.leading, 52)

                optionRow(
                    icon:   "number",
                    label:  "Post to #OpenTable",
                    detail: "Let the community know you're visiting"
                ) {
                    showOpenTableComposer = true
                }
                Divider().padding(.leading, 52)

                optionRow(
                    icon:   "message",
                    label:  "Ask in a group chat",
                    detail: "Share with your AMEN groups"
                ) {
                    // Opens group selector — future integration point
                }
                Divider().padding(.leading, 52)

                optionRow(
                    icon:   "calendar.badge.plus",
                    label:  "Save for Sunday",
                    detail: church.serviceTime,
                    highlight: false
                ) {
                    withAnimation { showSavedConfirm = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showSavedConfirm = false }
                    }
                }
                Divider().padding(.leading, 52)

                optionRow(
                    icon:   "map",
                    label:  "Get directions",
                    detail: church.address
                ) {
                    openMapsDirections()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(white: 0.88).opacity(0.5))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)

            // Saved confirmation toast
            if showSavedConfirm {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Added to your Sunday plans")
                        .font(AMENFont.semiBold(13))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.black, in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.top, 12)
                .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $showInviteSheet) {
            ChurchInviteComposer(church: church)
        }
        .sheet(isPresented: $showOpenTableComposer) {
            OpenTablePostComposer(church: church)
        }
    }

    @ViewBuilder
    private func optionRow(
        icon: String,
        label: String,
        detail: String,
        highlight: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.systemScaled(17))
                    .foregroundStyle(Color.black)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(Color.black)
                    Text(detail)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(Color(white: 0.55))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.75))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func openMapsDirections() {
        let query = church.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?daddr=\(query)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: Church Invite Composer

struct ChurchInviteComposer: View {
    let church: VisitTogetherView.VisitTogetherChurch
    @Environment(\.dismiss) private var dismiss
    @State private var messageText: String = ""
    @State private var sent = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Invite someone to visit")
                            .font(AMENFont.bold(20))
                            .foregroundStyle(Color.black)
                        Text("\(church.name) · \(church.serviceTime)")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    // Share card preview
                    ChurchVisitCard(church: church)
                        .padding(.horizontal, 16)

                    // Message field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add a message (optional)")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(Color(white: 0.5))
                            .padding(.horizontal, 24)

                        ZStack(alignment: .topLeading) {
                            if messageText.isEmpty {
                                Text("Hey, thinking of visiting this Sunday…")
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(Color(white: 0.7))
                                    .padding(12)
                            }
                            TextEditor(text: $messageText)
                                .font(AMENFont.regular(14))
                                .foregroundStyle(Color.black)
                                .frame(height: 80)
                                .padding(8)
                                .scrollContentBackground(.hidden)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.55))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(white: 0.88).opacity(0.5))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 16)
                    }

                    Button {
                        withAnimation { sent = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: sent ? "checkmark" : "paperplane")
                                .font(.systemScaled(14, weight: .semibold))
                            Text(sent ? "Invite sent" : "Send invite")
                                .font(AMENFont.bold(15))
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(sent ? Color(white: 0.55) : Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(sent)
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(AMENFont.regular(15))
                        .foregroundStyle(Color(white: 0.45))
                }
            }
        }
    }
}

// MARK: #OpenTable Post Composer

struct OpenTablePostComposer: View {
    let church: VisitTogetherView.VisitTogetherChurch
    @Environment(\.dismiss) private var dismiss
    @State private var postText: String = ""
    @State private var posted = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("#OpenTable")
                                .font(AMENFont.bold(20))
                                .foregroundStyle(Color.black)
                        }
                        Text("Let the community know you're visiting — someone might join you.")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    // Pre-filled text
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $postText)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(Color.black)
                            .frame(minHeight: 120)
                            .padding(10)
                            .scrollContentBackground(.hidden)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(white: 0.88).opacity(0.5))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 16)

                    // Church tag pill
                    HStack(spacing: 6) {
                        Image(systemName: "building.columns")
                            .font(.systemScaled(11))
                        Text(church.name)
                            .font(AMENFont.semiBold(12))
                        Text("·")
                        Text(church.serviceTime)
                            .font(AMENFont.regular(12))
                    }
                    .foregroundStyle(Color(white: 0.35))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(white: 0.95), in: Capsule())
                    .padding(.horizontal, 20)

                    Button {
                        withAnimation { posted = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
                    } label: {
                        Text(posted ? "Posted to #OpenTable" : "Post to #OpenTable")
                            .font(AMENFont.bold(15))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(posted ? Color(white: 0.55) : Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(postText.isEmpty || posted)
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(AMENFont.regular(15))
                        .foregroundStyle(Color(white: 0.45))
                }
                ToolbarItem(placement: .principal) {
                    Text("#OpenTable")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(Color.black)
                }
            }
        }
        .onAppear {
            postText = "Thinking of visiting \(church.name) this \(church.serviceTime). Anyone want to come? #OpenTable"
        }
    }
}

// MARK: ChurchVisitCard (shareable)

struct ChurchVisitCard: View {
    let church: VisitTogetherView.VisitTogetherChurch

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top band
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Going this Sunday")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black, in: Capsule())

                    Text(church.name)
                        .font(AMENFont.bold(20))
                        .foregroundStyle(Color.black)

                    Text(church.serviceTime)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(Color(white: 0.5))

                    if let dist = church.distanceMiles {
                        Text(String(format: "%.1f mi away", dist))
                            .font(AMENFont.regular(12))
                            .foregroundStyle(Color(white: 0.65))
                    }
                }
                Spacer()
                Image(systemName: "building.columns.fill")
                    .font(.systemScaled(40))
                    .foregroundStyle(Color(white: 0.88))
            }
            .padding(18)

            Divider()

            // CTA row
            HStack(spacing: 12) {
                Button {
                    // Join me action — future deep link
                } label: {
                    Text("Join me")
                        .font(AMENFont.bold(13))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    // View on AMEN — future deep link
                } label: {
                    Text("View on AMEN")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(Color(white: 0.35))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Color(white: 0.95), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            // AMEN watermark
            AMENBrandedWatermark(style: .bottomSignature)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(white: 0.88).opacity(0.5))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 4 · Live Church Intelligence
// ─────────────────────────────────────────────────────────────────────────────

enum SignalUrgency {
    case high    // pulsing indicator
    case medium
    case low
}

enum LiveSignalType: Equatable {
    case serviceCountdown
    case parkingTip
    case eventTonight
    case childcare
    case streaming
    case specialEvent
    case sermonSeries
    case language
    case accessibility
}

struct LiveChurchSignal: Identifiable {
    var id: String      { type.sortKey + text }
    let type: LiveSignalType
    let text: String
    let icon: String
    let urgency: SignalUrgency
}

private extension LiveSignalType {
    var sortKey: String {
        switch self {
        case .serviceCountdown: return "0"
        case .specialEvent:     return "1"
        case .eventTonight:     return "2"
        case .parkingTip:       return "3"
        case .childcare:        return "4"
        case .streaming:        return "5"
        case .sermonSeries:     return "6"
        case .language:         return "7"
        case .accessibility:    return "8"
        }
    }
}

struct LiveChurchIntelligenceView: View {
    let signals: [LiveChurchSignal]

    private var sorted: [LiveChurchSignal] {
        signals.sorted { $0.type.sortKey < $1.type.sortKey }
    }

    var body: some View {
        if signals.isEmpty { EmptyView() }
        else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sorted) { signal in
                        liveSignalPill(signal)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func liveSignalPill(_ signal: LiveChurchSignal) -> some View {
        HStack(spacing: 6) {
            if signal.type == .serviceCountdown {
                pulsingDot
            } else {
                Image(systemName: signal.icon)
                    .font(.systemScaled(12))
                    .foregroundStyle(Color(white: 0.35))
            }

            Text(signal.text)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(signal.urgency == .high ? Color.black : Color(white: 0.3))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(signal.urgency == .high ? 0.75 : 0.55))
                .overlay(
                    Capsule()
                        .fill(Color(white: 0.88).opacity(0.5))
                )
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    signal.urgency == .high
                        ? Color.black.opacity(0.15)
                        : Color(white: 0.88).opacity(0.5),
                    lineWidth: signal.urgency == .high ? 1 : 0.5
                )
        )
    }

    private var pulsingDot: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.25))
                .frame(width: 16, height: 16)
                .modifier(PulsingModifier())
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        }
    }
}

// Pulsing animation modifier
private struct PulsingModifier: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.5 : 1.0)
            .opacity(pulsing ? 0 : 0.6)
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: false),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}

// MARK: - Live Signal Factory (convenience)

struct LiveChurchSignalFactory {

    /// Build a representative set of signals from structured church data.
    static func signals(
        nextServiceIn hoursUntil: Double?,
        parkingTip: String?,
        eventTonight: String?,
        hasChildcareAt: String?,
        hasLivestream: Bool,
        specialEvent: String?,
        sermonSeries: String?,
        spanishServiceTime: String?,
        hasASL: Bool
    ) -> [LiveChurchSignal] {
        var result: [LiveChurchSignal] = []

        if let hours = hoursUntil {
            let text: String
            if hours < 1 {
                let mins = Int(hours * 60)
                text = "Service in \(mins)m"
            } else if hours < 24 {
                text = String(format: "Next service in %.0fh", hours)
            } else {
                text = "Sunday service upcoming"
            }
            result.append(LiveChurchSignal(
                type: .serviceCountdown,
                text: text,
                icon: "clock",
                urgency: hours < 2 ? .high : .medium
            ))
        }

        if let parking = parkingTip {
            result.append(LiveChurchSignal(
                type: .parkingTip,
                text: parking,
                icon: "car",
                urgency: .medium
            ))
        }

        if let event = eventTonight {
            result.append(LiveChurchSignal(
                type: .eventTonight,
                text: event,
                icon: "calendar",
                urgency: .medium
            ))
        }

        if let childcare = hasChildcareAt {
            result.append(LiveChurchSignal(
                type: .childcare,
                text: "Childcare at \(childcare)",
                icon: "figure.2.and.child.holdinghands",
                urgency: .low
            ))
        }

        if hasLivestream {
            result.append(LiveChurchSignal(
                type: .streaming,
                text: "Livestream available",
                icon: "play.circle",
                urgency: .low
            ))
        }

        if let special = specialEvent {
            result.append(LiveChurchSignal(
                type: .specialEvent,
                text: special,
                icon: "star",
                urgency: .high
            ))
        }

        if let series = sermonSeries {
            result.append(LiveChurchSignal(
                type: .sermonSeries,
                text: "Series: \(series)",
                icon: "text.book.closed",
                urgency: .low
            ))
        }

        if let spanish = spanishServiceTime {
            result.append(LiveChurchSignal(
                type: .language,
                text: "Español \(spanish)",
                icon: "globe.americas",
                urgency: .low
            ))
        }

        if hasASL {
            result.append(LiveChurchSignal(
                type: .accessibility,
                text: "ASL interpretation",
                icon: "hands.sparkles",
                urgency: .low
            ))
        }

        return result
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Previews
// ─────────────────────────────────────────────────────────────────────────────

struct ChurchSmartFeaturesSystem_Previews: PreviewProvider {
    static var previews: some View {
        Group {

            // 1. Spiritual Needs Router
            ScrollView {
                SpiritualNeedsRouterView(
                    selectedNeeds: .constant([.justMoved, .community]),
                    onFind: { _ in }
                )
                .padding()
            }
            .background(Color.white)
            .previewDisplayName("Spiritual Needs Router")

            // 2. Post-Visit Reflection Card
            ScrollView {
                PostVisitReflectionCard(
                    reflection: PostVisitReflection(
                        churchId:    "c1",
                        churchName:  "Grace City Church",
                        visitDate:   Date().addingTimeInterval(-86400)
                    ),
                    onWriteNote:       {},
                    onShareExperience: {},
                    onFollowChurch:    {},
                    onFindSimilar:     {},
                    onDismiss:         {}
                )
                .padding()
            }
            .background(Color.white)
            .previewDisplayName("Post-Visit Reflection")

            // 3. Visit Together
            ScrollView {
                VisitTogetherView(
                    church: VisitTogetherView.VisitTogetherChurch(
                        id:           "c1",
                        name:         "Grace City Church",
                        serviceTime:  "Sunday 10:30 AM",
                        distanceMiles: 2.4,
                        address:      "123 Faith Ave, New York, NY 10001"
                    )
                )
                .padding(.vertical)
            }
            .background(Color.white)
            .previewDisplayName("Visit Together")

            // 4. Live Church Intelligence
            VStack(alignment: .leading, spacing: 16) {
                Text("Live signals")
                    .font(AMENFont.bold(16))
                    .padding(.horizontal, 16)

                LiveChurchIntelligenceView(signals: LiveChurchSignalFactory.signals(
                    nextServiceIn:   1.25,
                    parkingTip:      "Arrive 15 min early",
                    eventTonight:    "Young adults 7 PM",
                    hasChildcareAt:  "10:30 AM",
                    hasLivestream:   true,
                    specialEvent:    nil,
                    sermonSeries:    "Romans",
                    spanishServiceTime: "12:30 PM",
                    hasASL:          true
                ))
            }
            .padding(.vertical, 20)
            .background(Color.white)
            .previewDisplayName("Live Church Intelligence")

            // 5. Church Visit Card
            ChurchVisitCard(
                church: VisitTogetherView.VisitTogetherChurch(
                    id:           "c1",
                    name:         "Grace City Church",
                    serviceTime:  "Sunday 10:30 AM",
                    distanceMiles: 2.4,
                    address:      "123 Faith Ave, New York, NY"
                )
            )
            .padding()
            .background(Color.white)
            .previewDisplayName("Church Visit Card")
        }
    }
}

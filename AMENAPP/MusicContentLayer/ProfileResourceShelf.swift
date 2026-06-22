// ProfileResourceShelf.swift
// AMENAPP — MusicContentLayer
// Church/organization resource shelf for profiles

import SwiftUI

// MARK: - Data Models

enum ProfileShelfResourceCategory: String, Codable, Sendable, CaseIterable {
    case music = "Music"
    case sermons = "Sermons"
    case notes = "Notes"
    case events = "Events"
    case playlists = "Playlists"
    case podcasts = "Podcasts"
    case devotionals = "Devotionals"
    case books = "Books"
    case courses = "Courses"
    case prayer = "Prayer"
    case store = "Store"
    case about = "About"

    var systemImage: String {
        switch self {
        case .music:       return "music.note"
        case .sermons:     return "mic.fill"
        case .notes:       return "note.text"
        case .events:      return "calendar"
        case .playlists:   return "music.note.list"
        case .podcasts:    return "antenna.radiowaves.left.and.right"
        case .devotionals: return "book.closed.fill"
        case .books:       return "books.vertical.fill"
        case .courses:     return "graduationcap.fill"
        case .prayer:      return "hands.and.sparkles.fill"
        case .store:       return "bag.fill"
        case .about:       return "info.circle.fill"
        }
    }
}

struct ProfileShelfResourceItem: Codable, Sendable, Identifiable {
    let id: String
    let category: ProfileShelfResourceCategory
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let contentURL: URL?
    let description: String?
    let accessPolicy: String
    let isVerified: Bool
    let isFeatured: Bool
    let viewCount: Int
    let publishedAt: String
}

// MARK: - Resource Card

private struct ProfileShelfResourceCard: View {
    let item: ProfileShelfResourceItem

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artworkSection
            VStack(alignment: .leading, spacing: 6) {
                categoryPill
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    accessPolicyBadge
                    Spacer()
                    if item.isFeatured {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Featured")
                    }
                }
            }
            .padding(10)
        }
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.05))
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    contrast == .increased
                        ? Color.primary.opacity(0.45)
                        : Color.white.opacity(0.18),
                    lineWidth: contrast == .increased ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var artworkSection: some View {
        Group {
            if let url = item.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        iconFallback
                    case .empty:
                        Color(uiColor: .tertiarySystemBackground)
                            .overlay(ProgressView().scaleEffect(0.7))
                    @unknown default:
                        iconFallback
                    }
                }
            } else {
                iconFallback
            }
        }
        .frame(height: 110)
        .clipped()
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 16
            )
        )
    }

    private var iconFallback: some View {
        Color(uiColor: .tertiarySystemBackground)
            .overlay {
                Image(systemName: item.category.systemImage)
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
    }

    private var categoryPill: some View {
        Label(item.category.rawValue, systemImage: item.category.systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    private var accessPolicyBadge: some View {
        let config: (String, Color) = {
            switch item.accessPolicy {
            case "paid":       return ("Pro", .purple)
            case "membersOnly": return ("Members", .blue)
            case "donation":   return ("Donation", .green)
            default:           return ("Free", .gray)
            }
        }()

        return Text(config.0)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(config.1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(config.1.opacity(0.12))
            )
    }

    private var accessibilityDescription: String {
        var parts: [String] = [item.title]
        if let subtitle = item.subtitle { parts.append(subtitle) }
        parts.append(item.category.rawValue)
        parts.append("Access: \(item.accessPolicy)")
        if item.isFeatured { parts.append("Featured") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Filter Chip

private struct ProfileShelfCategoryChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        if reduceTransparency {
                            Capsule().fill(Color(uiColor: .secondarySystemBackground))
                        } else {
                            Capsule().fill(.ultraThinMaterial)
                                .overlay(Capsule().fill(Color.white.opacity(0.1)))
                        }
                    } else {
                        Capsule().fill(Color.clear)
                    }
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            isSelected
                                ? (contrast == .increased ? Color.primary.opacity(0.6) : Color.white.opacity(0.3))
                                : Color.clear,
                            lineWidth: contrast == .increased ? 1.5 : 1
                        )
                }
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Empty State

private struct ResourcesEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No resources yet")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Resources added by this organization will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Main View

struct ProfileResourceShelf: View {
    let items: [ProfileShelfResourceItem]
    let isAdmin: Bool
    var onAddResource: (() -> Void)?

    @State private var selectedCategory: ProfileShelfResourceCategory?
    @State private var isLoading: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var presentCategories: [ProfileShelfResourceCategory] {
        var seen = Set<ProfileShelfResourceCategory>()
        return items.compactMap { item in
            guard !seen.contains(item.category) else { return nil }
            seen.insert(item.category)
            return item.category
        }
    }

    private var filteredItems: [ProfileShelfResourceItem] {
        guard let category = selectedCategory else { return items }
        return items.filter { $0.category == category }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if presentCategories.count > 1 {
                filterChipRow
                    .padding(.bottom, 12)
            }

            if isLoading {
                loadingView
            } else if filteredItems.isEmpty {
                ResourcesEmptyState()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredItems) { item in
                        ProfileShelfResourceCard(item: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Text("Resources")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if isAdmin, let addAction = onAddResource {
                Button(action: addAction) {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if reduceTransparency {
                                Capsule().fill(Color.purple.opacity(0.12))
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                                    .overlay(Capsule().fill(Color.purple.opacity(0.1)))
                            }
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    contrast == .increased
                                        ? Color.purple.opacity(0.6)
                                        : Color.purple.opacity(0.25),
                                    lineWidth: contrast == .increased ? 1.5 : 1
                                )
                        }
                }
                .accessibilityLabel("Add resource")
            }
        }
    }

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ProfileShelfCategoryChip(
                    label: "All",
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }
                ForEach(presentCategories, id: \.self) { category in
                    ProfileShelfCategoryChip(
                        label: category.rawValue,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = (selectedCategory == category) ? nil : category
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading resources...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

// MARK: - Preview

#Preview("Resource Shelf") {
    ScrollView {
        ProfileResourceShelf(
            items: [
                ProfileShelfResourceItem(
                    id: "1",
                    category: .sermons,
                    title: "Walking in the Spirit",
                    subtitle: "Pastor Marcus Williams",
                    artworkURL: nil,
                    contentURL: nil,
                    description: "A powerful message on fruit of the Spirit.",
                    accessPolicy: "free",
                    isVerified: true,
                    isFeatured: true,
                    viewCount: 1240,
                    publishedAt: "2026-06-01T10:00:00Z"
                ),
                ProfileShelfResourceItem(
                    id: "2",
                    category: .sermons,
                    title: "The Power of Prayer",
                    subtitle: "Guest Speaker",
                    artworkURL: nil,
                    contentURL: nil,
                    description: nil,
                    accessPolicy: "free",
                    isVerified: false,
                    isFeatured: false,
                    viewCount: 450,
                    publishedAt: "2026-05-18T10:00:00Z"
                ),
                ProfileShelfResourceItem(
                    id: "3",
                    category: .music,
                    title: "Sunday Worship Mix",
                    subtitle: "Cornerstone Worship Team",
                    artworkURL: nil,
                    contentURL: nil,
                    description: "Our latest live worship recording.",
                    accessPolicy: "free",
                    isVerified: true,
                    isFeatured: true,
                    viewCount: 3200,
                    publishedAt: "2026-06-08T09:00:00Z"
                ),
                ProfileShelfResourceItem(
                    id: "4",
                    category: .music,
                    title: "Christmas Cantata 2025",
                    subtitle: "Full choir recording",
                    artworkURL: nil,
                    contentURL: nil,
                    description: nil,
                    accessPolicy: "membersOnly",
                    isVerified: false,
                    isFeatured: false,
                    viewCount: 720,
                    publishedAt: "2025-12-21T10:00:00Z"
                ),
                ProfileShelfResourceItem(
                    id: "5",
                    category: .courses,
                    title: "Foundations of Faith",
                    subtitle: "6-week discipleship course",
                    artworkURL: nil,
                    contentURL: nil,
                    description: "A comprehensive intro to Christian living.",
                    accessPolicy: "paid",
                    isVerified: true,
                    isFeatured: true,
                    viewCount: 890,
                    publishedAt: "2026-01-10T10:00:00Z"
                ),
                ProfileShelfResourceItem(
                    id: "6",
                    category: .courses,
                    title: "Prayer & Fasting",
                    subtitle: "4-week intensive",
                    artworkURL: nil,
                    contentURL: nil,
                    description: nil,
                    accessPolicy: "free",
                    isVerified: false,
                    isFeatured: false,
                    viewCount: 330,
                    publishedAt: "2026-03-05T10:00:00Z"
                )
            ],
            isAdmin: true,
            onAddResource: { print("Add tapped") }
        )
    }
    .background(Color(uiColor: .systemGroupedBackground))
}

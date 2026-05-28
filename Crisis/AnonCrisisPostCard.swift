import SwiftUI

struct AnonCrisisPostCard: View {
    let post: AnonCrisisPost
    @State private var showReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            contentText
            crisisLevelBadge
            if !post.resourcesAutoAdded.isEmpty { resourcesSection }
            footerRow
        }
        .padding(14)
        .background(AmenTheme.Colors.surfaceCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(crisisLevelColor.opacity(0.3), lineWidth: 1))
        .confirmationDialog("Report this post", isPresented: $showReport) {
            Button("Spam", role: .none) { }
            Button("Inappropriate", role: .none) { }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var crisisLevelColor: Color {
        switch post.crisisLevel {
        case .imminent, .high: return Color(red: 0.95, green: 0.40, blue: 0.40)
        case .moderate: return Color(red: 0.95, green: 0.70, blue: 0.30)
        case .low: return Color(red: 0.40, green: 0.70, blue: 0.95)
        }
    }

    private var headerRow: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.40, green: 0.70, blue: 0.95).opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(Image(systemName: "person.fill").font(.caption).foregroundStyle(Color(red: 0.40, green: 0.70, blue: 0.95)))
                Text("Someone in Crisis")
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            Spacer()
            if let ts = post.createdAt?.dateValue() {
                Text(ts.formatted(.relative(presentation: .named)))
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Anonymous crisis post")
    }

    private var contentText: some View {
        Text(post.content)
            .font(.custom("OpenSans-Regular", size: 15))
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .lineSpacing(4)
    }

    private var crisisLevelBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(crisisLevelColor).frame(width: 8, height: 8)
            Text("\(post.crisisLevel.displayName) intensity")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(crisisLevelColor)
        }
        .accessibilityLabel("\(post.crisisLevel.displayName) intensity crisis post")
    }

    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Resources")
                .font(.custom("OpenSans-Bold", size: 13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            ForEach(post.resourcesAutoAdded.prefix(3)) { resource in
                HStack(spacing: 6) {
                    Image(systemName: "link.circle.fill").font(.caption).foregroundStyle(Color(red: 0.40, green: 0.70, blue: 0.95))
                    Text(resource.reason)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
                .accessibilityLabel(resource.reason)
            }
        }
        .padding(8)
        .background(Color(red: 0.40, green: 0.70, blue: 0.95).opacity(0.06))
        .cornerRadius(8)
    }

    private var footerRow: some View {
        HStack {
            Label("\(post.heartsCount)", systemImage: "heart")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .accessibilityLabel("\(post.heartsCount) hearts")
            Spacer()
            Button { showReport = true } label: {
                Label("Report", systemImage: "exclamationmark.triangle")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .accessibilityLabel("Report this post")
        }
    }
}

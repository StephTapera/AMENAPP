import SwiftUI

struct GivingPostCard: View {
    let post: GivingPost
    @State private var versesExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            narrativeSection
            orgSection
            if let goal = post.goalAmount { progressSection(goal: goal) }
            if !post.linkedVerses.isEmpty { versesSection }
            engagementRow
        }
        .padding(14)
        .background(AmenTheme.Colors.surfaceCard)
        .cornerRadius(14)
    }

    private var narrativeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill").foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                Text("Giving Post")
                    .font(.custom("OpenSans-Bold", size: 12))
                    .foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                    .textCase(.uppercase)
                Spacer()
                if let ts = post.createdAt?.dateValue() {
                    Text(ts.formatted(.relative(presentation: .named)))
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }
            Text(post.narrative)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineSpacing(4)
        }
    }

    private var orgSection: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.83, green: 0.69, blue: 0.22).opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "building.columns.fill")
                    .foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(post.organizationName)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(post.tags.prefix(2).joined(separator: " • "))
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
        .padding(10)
        .background(AmenTheme.Colors.backgroundPrimary)
        .cornerRadius(10)
        .accessibilityLabel("Organization: \(post.organizationName)")
    }

    private func progressSection(goal: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: post.progressFraction)
                .tint(Color(red: 0.83, green: 0.69, blue: 0.22))
            HStack {
                Text(post.formattedCurrent).font(.custom("OpenSans-Bold", size: 13)).foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                Text("of \(post.formattedGoal ?? "")").font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(AmenTheme.Colors.textSecondary)
                Spacer()
                Text("\(Int(post.progressFraction * 100))%").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textTertiary)
            }
        }
        .accessibilityLabel("Progress: \(post.formattedCurrent) of \(post.formattedGoal ?? "goal")")
    }

    private var versesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) { versesExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "book.fill").font(.caption).foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                    Text("\(post.linkedVerses.count) Linked Scripture\(post.linkedVerses.count == 1 ? "" : "s")")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                    Spacer()
                    Image(systemName: versesExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }
            .accessibilityLabel("Toggle scripture references")

            if versesExpanded {
                ForEach(post.linkedVerses) { verse in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(verse.book) \(verse.chapter):\(verse.verse)")
                            .font(.custom("OpenSans-Bold", size: 12))
                            .foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                        Text(verse.text)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .italic()
                    }
                }
            }
        }
        .padding(8)
        .background(Color(red: 0.83, green: 0.69, blue: 0.22).opacity(0.05))
        .cornerRadius(8)
    }

    private var engagementRow: some View {
        HStack(spacing: 20) {
            Label("\(post.engagementHearts)", systemImage: "heart")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .accessibilityLabel("\(post.engagementHearts) hearts")
            Label("\(post.engagementComments)", systemImage: "bubble.left")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .accessibilityLabel("\(post.engagementComments) comments")
            Spacer()
            Button {
            } label: {
                Text("Support This Organization")
                    .font(.custom("OpenSans-Bold", size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.83, green: 0.69, blue: 0.22))
                    .cornerRadius(8)
            }
            .accessibilityLabel("Support \(post.organizationName)")
        }
    }
}

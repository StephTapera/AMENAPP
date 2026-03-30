import Combine
import SwiftUI
import FirebaseAuth

/// View for displaying notification digests
struct NotificationDigestView: View {
    @ObservedObject private var digestService = NotificationDigestService.shared
    @State private var selectedDigest: NotificationDigest?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Current Pending Digest
                    if let pending = digestService.pendingDigest, !pending.items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Today's Summary")
                                        .font(.title2.bold())
                                    
                                    Text(pending.summary)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if let deliverAt = pending.deliveredAt {
                                    VStack(alignment: .trailing) {
                                        Text("Delivered")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(deliverAt, style: .time)
                                            .font(.caption)
                                    }
                                }
                            }
                            
                            Divider()
                            
                            ForEach(pending.items) { item in
                                DigestItemRow(item: item)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 10)
                        )
                        .padding(.horizontal)
                        .onTapGesture {
                            selectedDigest = pending
                            Task {
                                try? await digestService.markDigestOpened(digestId: pending.id)
                            }
                        }
                    }
                    
                    // Digest History
                    if !digestService.digestHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Past Summaries")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(digestService.digestHistory) { digest in
                                DigestHistoryCard(digest: digest)
                                    .padding(.horizontal)
                                    .onTapGesture {
                                        selectedDigest = digest
                                    }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Summaries")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                try? await digestService.loadCurrentDigest()
                try? await digestService.loadDigestHistory()
            }
            .refreshable {
                try? await digestService.loadCurrentDigest()
                try? await digestService.loadDigestHistory()
            }
            .sheet(item: $selectedDigest) { digest in
                DigestDetailView(digest: digest)
            }
        }
    }
}

// MARK: - Digest Item Row

struct DigestItemRow: View {
    let item: NotificationDigest.DigestItem
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: categoryIcon)
                .font(.system(size: 20))
                .foregroundColor(categoryColor)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.category.displayName)
                        .font(.subheadline.bold())
                    
                    Spacer()
                    
                    Text("\(item.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(.systemGray6))
                        )
                }
                
                if !item.preview.isEmpty {
                    Text(item.preview.prefix(2).joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var categoryIcon: String {
        switch item.category {
        case .directMessages: return "message"
        case .replies: return "arrowshape.turn.up.left"
        case .mentions: return "at"
        case .reactions: return "heart"
        case .follows: return "person.badge.plus"
        case .prayerUpdates: return "hands.sparkles"
        case .churchNotes: return "building.columns"
        case .reposts: return "arrow.2.squarepath"
        case .groupMessages: return "bubble.left.and.bubble.right"
        case .crisisAlerts: return "exclamationmark.triangle"
        }
    }
    
    private var categoryColor: Color {
        switch item.category {
        case .directMessages, .groupMessages: return .blue
        case .replies, .mentions: return .purple
        case .reactions: return .pink
        case .follows: return .green
        case .prayerUpdates: return .orange
        case .churchNotes: return .indigo
        case .reposts: return .teal
        case .crisisAlerts: return .red
        }
    }
}

// MARK: - Digest History Card

struct DigestHistoryCard: View {
    let digest: NotificationDigest
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(digest.period.start, style: .date)
                    .font(.subheadline.bold())
                
                Text(digest.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if digest.opened {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            } else {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Digest Detail View

struct DigestDetailView: View {
    let digest: NotificationDigest
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerView
                    Divider()
                    itemsView
                }
            }
            .navigationTitle("Summary Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(periodString)
                .font(.title2.bold())
            
            Text(digest.summary)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private var itemsView: some View {
        ForEach(digest.items) { item in
            DigestDetailItemCard(item: item)
                .padding(.horizontal)
        }
    }
    
    private var periodString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        let start = formatter.string(from: digest.period.start)
        let end = formatter.string(from: digest.period.end)
        
        if Calendar.current.isDate(digest.period.start, inSameDayAs: digest.period.end) {
            return start
        } else {
            return "\(start) - \(end)"
        }
    }
    
    private func categoryIcon(for category: NotificationCategory) -> String {
        switch category {
        case .directMessages: return "message"
        case .replies: return "arrowshape.turn.up.left"
        case .mentions: return "at"
        case .reactions: return "heart"
        case .follows: return "person.badge.plus"
        case .prayerUpdates: return "hands.sparkles"
        case .churchNotes: return "building.columns"
        case .reposts: return "arrow.2.squarepath"
        case .groupMessages: return "bubble.left.and.bubble.right"
        case .crisisAlerts: return "exclamationmark.triangle"
        }
    }
    
    private func categoryColor(for category: NotificationCategory) -> Color {
        switch category {
        case .directMessages, .groupMessages: return .blue
        case .replies, .mentions: return .purple
        case .reactions: return .pink
        case .follows: return .green
        case .prayerUpdates: return .orange
        case .churchNotes: return .indigo
        case .reposts: return .teal
        case .crisisAlerts: return .red
        }
    }
}

// MARK: - Digest Detail Item Card

struct DigestDetailItemCard: View {
    let item: NotificationDigest.DigestItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(item.category.displayName, systemImage: categoryIcon)
                    .font(.headline)
                
                Spacer()
                
                countBadge
            }
            
            previewTexts
            
            if item.deepLinks.count > item.preview.count {
                moreText
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    private var countBadge: some View {
        Text("\(item.count)")
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(categoryColor))
    }
    
    private var previewTexts: some View {
        ForEach(Array(item.preview.enumerated()), id: \.offset) { _, preview in
            Text(preview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.leading)
        }
    }
    
    private var moreText: some View {
        Text("+ \(item.deepLinks.count - item.preview.count) more")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.leading)
    }
    
    private var categoryIcon: String {
        switch item.category {
        case .directMessages: return "message"
        case .replies: return "arrowshape.turn.up.left"
        case .mentions: return "at"
        case .reactions: return "heart"
        case .follows: return "person.badge.plus"
        case .prayerUpdates: return "hands.sparkles"
        case .churchNotes: return "building.columns"
        case .reposts: return "arrow.2.squarepath"
        case .groupMessages: return "bubble.left.and.bubble.right"
        case .crisisAlerts: return "exclamationmark.triangle"
        }
    }
    
    private var categoryColor: Color {
        switch item.category {
        case .directMessages, .groupMessages: return .blue
        case .replies, .mentions: return .purple
        case .reactions: return .pink
        case .follows: return .green
        case .prayerUpdates: return .orange
        case .churchNotes: return .indigo
        case .reposts: return .teal
        case .crisisAlerts: return .red
        }
    }
}

#Preview {
    NotificationDigestView()
}

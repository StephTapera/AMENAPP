// KoraCircleDetailView.swift
// AMENAPP
//
// Full-screen detail view for a Kora circle.

import SwiftUI
import FirebaseAuth

struct KoraCircleDetailView: View {
    let circle: KoraCircle
    @ObservedObject var vm: KoraViewModel

    @State private var selectedTab: KoraDetailTab = .checkIns
    @State private var checkIns: [KoraCheckIn] = []
    @State private var journalEntries: [KoraJournalEntry] = []
    @State private var showJournalSheet = false
    @State private var isLoadingContent = false
    @Namespace private var tabIndicatorNS

    enum KoraDetailTab: String, CaseIterable {
        case checkIns = "Check-ins"
        case journal  = "Journal"
        case members  = "Members"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(hex: "0A0A0F").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    circleHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 20)

                    tabPicker
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    tabContent
                        .padding(.horizontal, 16)

                    Spacer(minLength: 80)
                }
            }

            // Journal FAB
            if selectedTab == .journal {
                Button {
                    showJournalSheet = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "6B48FF"), Color(hex: "C084FC")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 52, height: 52)
                            .shadow(color: Color(hex: "6B48FF").opacity(0.4), radius: 10, x: 0, y: 4)
                        Image(systemName: "pencil")
                            .font(.systemScaled(18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(CoCreationPressStyle())
                .padding(.trailing, 20)
                .padding(.bottom, 32)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationTitle(circle.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showJournalSheet) {
            KoraJournalEntrySheet(circleId: circle.id ?? "", vm: vm)
        }
        .task {
            await loadContent()
        }
    }

    // MARK: - Header

    private var circleHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                purposeBadge

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.systemScaled(12))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(circle.memberCount) members")
                        .font(AMENFont.regular(13))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            // Next check-in label
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.systemScaled(12))
                    .foregroundColor(Color(hex: "F59E0B").opacity(0.7))
                Text("Next: \(nextCheckInLabel)")
                    .font(AMENFont.regular(13))
                    .foregroundColor(Color(hex: "F59E0B").opacity(0.7))
            }
        }
    }

    private var nextCheckInLabel: String {
        let diff = circle.nextCheckInAt.timeIntervalSinceNow
        let days = Int(ceil(diff / 86400))
        if days <= 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "in \(days) days"
    }

    private var purposeBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: circle.purpose.icon)
                .font(.systemScaled(11))
            Text(circle.purpose.label)
                .font(AMENFont.semiBold(12))
        }
        .foregroundColor(Color(hex: circle.coverColorHex))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(hex: circle.coverColorHex).opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(KoraDetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(selectedTab == tab ? AMENFont.semiBold(14) : AMENFont.regular(14))
                            .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.4))

                        ZStack {
                            Capsule()
                                .fill(Color.clear)
                                .frame(height: 2)
                            if selectedTab == tab {
                                Capsule()
                                    .fill(Color(hex: circle.coverColorHex))
                                    .frame(height: 2)
                                    .matchedGeometryEffect(id: "tabIndicator", in: tabIndicatorNS)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .checkIns:
            checkInsTab
        case .journal:
            journalTab
        case .members:
            membersTab
        }
    }

    // MARK: - Check-ins Tab

    private var checkInsTab: some View {
        LazyVStack(spacing: 12) {
            if checkIns.isEmpty && !isLoadingContent {
                emptyTabState(
                    icon: "bubble.left.and.bubble.right.fill",
                    message: "No check-ins yet",
                    subtitle: "Your first check-in will appear here."
                )
            } else {
                ForEach(checkIns) { checkIn in
                    NavigationLink(value: KoraCheckInNavItem(checkIn: checkIn, circle: circle)) {
                        KoraCheckInRowCard(checkIn: checkIn, isHighlighted: checkIn.status == .open)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .navigationDestination(for: KoraCheckInNavItem.self) { item in
            KoraCheckInDetailView(checkIn: item.checkIn, circle: item.circle, vm: vm)
        }
    }

    // MARK: - Journal Tab

    private var journalTab: some View {
        LazyVStack(spacing: 12) {
            if journalEntries.isEmpty && !isLoadingContent {
                emptyTabState(
                    icon: "book.closed.fill",
                    message: "Your journal is empty",
                    subtitle: "Start writing to track your spiritual journey."
                )
            } else {
                ForEach(journalEntries) { entry in
                    KoraJournalEntryRowView(entry: entry)
                }
            }
        }
    }

    // MARK: - Members Tab

    private var membersTab: some View {
        LazyVStack(spacing: 10) {
            ForEach(circle.memberIds, id: \.self) { memberId in
                memberRow(memberId: memberId)
            }

            Text("Moods are anonymous")
                .font(AMENFont.regular(11))
                .foregroundColor(.white.opacity(0.25))
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    private func memberRow(memberId: String) -> some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            ZStack {
                Circle()
                    .fill(Color(hex: circle.coverColorHex).opacity(0.2))
                    .frame(width: 40, height: 40)
                Text(String(memberId.prefix(1)).uppercased())
                    .font(AMENFont.bold(14))
                    .foregroundColor(Color(hex: circle.coverColorHex))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Member")
                    .font(AMENFont.semiBold(14))
                    .foregroundColor(.white)
                Text("Circle member")
                    .font(AMENFont.regular(12))
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer()

            // Mood dot (anonymous, random for display)
            let mood = KoraMood.allCases[abs(memberId.hashValue) % KoraMood.allCases.count]
            Circle()
                .fill(Color(hex: mood.colorHex))
                .frame(width: 10, height: 10)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Empty State

    private func emptyTabState(icon: String, message: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.systemScaled(36))
                .foregroundColor(.white.opacity(0.15))
            Text(message)
                .font(AMENFont.semiBold(15))
                .foregroundColor(.white.opacity(0.4))
            Text(subtitle)
                .font(AMENFont.regular(13))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 24)
    }

    // MARK: - Load

    private func loadContent() async {
        guard let circleId = circle.id else { return }
        isLoadingContent = true
        async let ci = vm.loadCheckIns(for: circleId)
        async let je = vm.loadJournalEntries(circleId: circleId)
        let (fetchedCheckIns, fetchedJournal) = await (ci, je)
        checkIns = fetchedCheckIns
        journalEntries = fetchedJournal
        isLoadingContent = false
    }
}

// MARK: - Navigation Helpers

struct KoraCheckInNavItem: Hashable {
    let checkIn: KoraCheckIn
    let circle: KoraCircle

    func hash(into hasher: inout Hasher) {
        hasher.combine(checkIn.id)
    }
    static func == (lhs: KoraCheckInNavItem, rhs: KoraCheckInNavItem) -> Bool {
        lhs.checkIn.id == rhs.checkIn.id
    }
}

// MARK: - Check-in Row Card

struct KoraCheckInRowCard: View {
    let checkIn: KoraCheckIn
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                statusBadge
                Spacer()
                if let date = checkIn.openedAt {
                    Text(date, style: .date)
                        .font(AMENFont.regular(11))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            Text(checkIn.question)
                .font(AMENFont.semiBold(14))
                .foregroundColor(.white)
                .lineLimit(2)

            if let summary = checkIn.aiSummary, !summary.isEmpty {
                Text(summary)
                    .font(.systemScaled(12).italic())
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(
            isHighlighted
                ? AnyShapeStyle(Color(hex: "F59E0B").opacity(0.07))
                : AnyShapeStyle(Material.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isHighlighted
                        ? Color(hex: "F59E0B").opacity(0.3)
                        : Color.white.opacity(0.07),
                    lineWidth: 0.8
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch checkIn.status {
            case .open:        return ("Open", Color(hex: "22C55E"))
            case .closed:      return ("Closed", Color(hex: "6B7280"))
            case .summarized:  return ("Summarized", Color(hex: "6B48FF"))
            }
        }()
        return Text(label)
            .font(AMENFont.semiBold(10))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Journal Entry Row

struct KoraJournalEntryRowView: View {
    let entry: KoraJournalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Author initial circle
            ZStack {
                Circle()
                    .fill(Color(hex: "6B48FF").opacity(0.2))
                    .frame(width: 36, height: 36)
                Text(String(entry.authorId.prefix(1)).uppercased())
                    .font(AMENFont.bold(13))
                    .foregroundColor(Color(hex: "6B48FF"))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    if let date = entry.createdAt {
                        Text(date, style: .date)
                            .font(AMENFont.regular(11))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    Spacer()
                    scopeBadge
                }

                Text(entry.content)
                    .font(AMENFont.regular(13))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(3)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var scopeBadge: some View {
        let (label, color): (String, Color) = {
            switch entry.sharedWith {
            case .private:   return ("Just me", Color(hex: "6B7280"))
            case .circle:    return ("Circle", Color(hex: "6B48FF"))
            case .workspace: return ("Workspace", Color(hex: "C084FC"))
            }
        }()
        return Text(label)
            .font(AMENFont.regular(10))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// SafetySettingsView.swift — AMEN App
// Safety settings, content filter preferences, and past safety review log.
// Also contains: ContentSafetyBadge — inline trust status badge.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - SafetySettingsView

struct SafetySettingsView: View {
    @State private var safetyLogs: [ContentSafetyLog] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @AppStorage("contentFilterLevel") private var filterLevel: String = "standard"
    @State private var showTrustExplainer = false

    // MARK: - Trust score derived from logs

    private var trustScore: Double {
        guard !safetyLogs.isEmpty else { return 0.85 }
        let blocked = safetyLogs.filter { $0.decision == .blocked }.count
        let warned  = safetyLogs.filter { $0.decision == .warned }.count
        let total   = safetyLogs.count
        let badRate = Double(blocked * 3 + warned) / Double(max(total, 1) * 3)
        return max(0, 1.0 - badRate)
    }

    private var trustLabel: String {
        if trustScore >= 0.8 { return "Your content history puts you in good standing." }
        if trustScore >= 0.5 { return "Keep posting faith-centered content to build your trust." }
        return "Recent flags have lowered your trust level. Review past decisions below."
    }

    private var trustTint: Color {
        if trustScore >= 0.8 { return Color(red: 0.25, green: 0.88, blue: 0.56) }
        if trustScore >= 0.5 { return Color(red: 0.96, green: 0.65, blue: 0.14) }
        return Color(red: 0.96, green: 0.38, blue: 0.38)
    }

    private var trustIcon: String {
        if trustScore >= 0.8 { return "shield.fill" }
        if trustScore >= 0.5 { return "shield.lefthalf.filled" }
        return "exclamationmark.shield.fill"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        // Trust Level Card
                        trustLevelCard

                        // Content Filter Card
                        contentFilterCard

                        // Past Reviews
                        pastReviewsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Safety & Trust")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear { Task { await loadSafetyLogs() } }
        .sheet(isPresented: $showTrustExplainer) {
            TrustScoreExplainerSheet(trustScore: trustScore)
        }
    }

    // MARK: - Trust Level Card

    private var trustLevelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(trustTint.opacity(0.13))
                        .frame(width: 44, height: 44)
                    Image(systemName: trustIcon)
                        .font(.systemScaled(20, weight: .semibold))
                        .foregroundColor(trustTint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Trust Level")
                        .font(.systemScaled(16, weight: .bold))
                        .foregroundColor(.white)
                    Text(trustLabel)
                        .font(.systemScaled(13))
                        .foregroundColor(.white.opacity(0.6))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            // Trust score bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Trust score")
                        .font(.systemScaled(12))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Text(String(format: "%.0f%%", trustScore * 100))
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundColor(trustTint)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08)).frame(height: 5)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [trustTint.opacity(0.7), trustTint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(min(trustScore, 1.0)), height: 5)
                            .animation(.spring(response: 0.6, dampingFraction: 0.75), value: trustScore)
                    }
                }
                .frame(height: 5)
            }

            Button {
                showTrustExplainer = true
            } label: {
                HStack(spacing: 4) {
                    Text("How is this calculated?")
                        .font(.systemScaled(12, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(10))
                }
                .foregroundColor(trustTint.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(glassCard(tint: trustTint))
    }

    // MARK: - Content Filter Card

    private var contentFilterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundColor(Color(red: 0.55, green: 0.25, blue: 1.0))
                Text("Content Filter")
                    .font(.systemScaled(16, weight: .bold))
                    .foregroundColor(.white)
            }

            Text("Controls how strictly content is checked before posting.")
                .font(.systemScaled(13))
                .foregroundColor(.white.opacity(0.5))

            HStack(spacing: 8) {
                ForEach(["standard", "sensitive", "relaxed"], id: \.self) { level in
                    filterTab(level)
                }
            }
        }
        .padding(16)
        .background(glassCard(tint: Color(red: 0.55, green: 0.25, blue: 1.0)))
    }

    private func filterTab(_ level: String) -> some View {
        let isSelected = filterLevel == level
        let label: String
        let icon: String
        switch level {
        case "sensitive": label = "More Sensitive"; icon = "shield.fill"
        case "relaxed":   label = "Less Sensitive"; icon = "shield.slash.fill"
        default:          label = "Standard";       icon = "shield.lefthalf.filled"
        }

        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                filterLevel = level
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.systemScaled(14, weight: .medium))
                Text(label)
                    .font(.systemScaled(11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color(red: 0.55, green: 0.25, blue: 1.0).opacity(0.25)
                            : Color.white.opacity(0.05)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? Color(red: 0.55, green: 0.25, blue: 1.0).opacity(0.45)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Past Reviews Section

    private var pastReviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Past Reviews")
                    .font(.systemScaled(16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if isLoading {
                    ProgressView()
                        .tint(Color.purple)
                        .scaleEffect(0.8)
                }
            }

            if let error = loadError {
                Text(error)
                    .font(.systemScaled(13))
                    .foregroundColor(Color(red: 0.96, green: 0.38, blue: 0.38))
            } else if !isLoading && safetyLogs.isEmpty {
                emptyReviewsState
            } else {
                ForEach(safetyLogs) { log in
                    SafetyLogRow(log: log)
                }
            }
        }
    }

    private var emptyReviewsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.systemScaled(32))
                .foregroundColor(Color(red: 0.25, green: 0.88, blue: 0.56).opacity(0.5))
            Text("No past reviews")
                .font(.systemScaled(15, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            Text("Your content hasn't required review. Keep it up!")
                .font(.systemScaled(13))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Load Safety Logs

    private func loadSafetyLogs() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        loadError = nil
        lazy var db = Firestore.firestore()

        do {
            let snap = try await db.collection("contentSafetyLogs")
                .whereField("authorId", isEqualTo: uid)
                .order(by: "reviewedAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            safetyLogs = snap.documents.compactMap { try? $0.data(as: ContentSafetyLog.self) }
        } catch {
            loadError = "Couldn't load safety history."
        }
        isLoading = false
    }

    // MARK: - Glass Card Helper

    private func glassCard(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint.opacity(0.15), lineWidth: 1)
            )
    }
}

// MARK: - SafetyLogRow

private struct SafetyLogRow: View {
    let log: ContentSafetyLog

    private var decisionColor: Color {
        switch log.decision {
        case .approved:    return Color(red: 0.25, green: 0.88, blue: 0.56)
        case .warned:      return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .blocked:     return Color(red: 0.96, green: 0.38, blue: 0.38)
        case .appealed:    return Color(red: 0.55, green: 0.25, blue: 1.0)
        case .underReview: return Color(red: 0.24, green: 0.71, blue: 0.96)
        }
    }

    private var decisionLabel: String {
        switch log.decision {
        case .approved:    return "Approved"
        case .warned:      return "Warned"
        case .blocked:     return "Blocked"
        case .appealed:    return "Appealed"
        case .underReview: return "Under Review"
        }
    }

    private var formattedDate: String {
        guard let date = log.reviewedAt else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Decision badge
                Text(decisionLabel)
                    .font(.systemScaled(11, weight: .bold))
                    .foregroundColor(decisionColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(decisionColor.opacity(0.13))
                            .overlay(Capsule().strokeBorder(decisionColor.opacity(0.25), lineWidth: 1))
                    )

                Spacer()

                if !formattedDate.isEmpty {
                    Text(formattedDate)
                        .font(.systemScaled(11))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            Text(log.aiReasoning.isEmpty ? "No reasoning provided." : log.aiReasoning)
                .font(.systemScaled(13))
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(2)

            if !log.flaggedCategories.isEmpty {
                HStack(spacing: 5) {
                    ForEach(log.flaggedCategories.prefix(3), id: \.self) { cat in
                        Text(cat.capitalized)
                            .font(.systemScaled(10))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.05))
                            )
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(decisionColor.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

// MARK: - TrustScoreExplainerSheet

private struct TrustScoreExplainerSheet: View {
    let trustScore: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("About Trust Score")
                        .font(.systemScaled(20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(22))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }

                Text("Your trust score reflects your content history on AMEN. It's calculated from:")
                    .font(.systemScaled(15))
                    .foregroundColor(.white.opacity(0.7))
                    .lineSpacing(3)

                VStack(alignment: .leading, spacing: 12) {
                    explainerRow(icon: "checkmark.circle.fill", color: Color(red: 0.25, green: 0.88, blue: 0.56),
                                 title: "Approved content", subtitle: "Posts that passed review with no flags.")
                    explainerRow(icon: "exclamationmark.triangle.fill", color: Color(red: 0.96, green: 0.65, blue: 0.14),
                                 title: "Warned content", subtitle: "Posts flagged as potentially sensitive.")
                    explainerRow(icon: "xmark.shield.fill", color: Color(red: 0.96, green: 0.38, blue: 0.38),
                                 title: "Blocked content", subtitle: "Posts removed for policy violations (weighted 3x).")
                }

                Text("A higher score means more posting permissions and less friction. Trust is rebuilt over time with good content.")
                    .font(.systemScaled(13))
                    .foregroundColor(.white.opacity(0.45))
                    .lineSpacing(3)

                Spacer()
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func explainerRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(18))
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text(subtitle)
                    .font(.systemScaled(13))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - TrustScoreBadge

struct TrustScoreBadge: View {
    let trustScore: Double
    @State private var showExplainer = false

    var body: some View {
        Group {
            if trustScore >= 0.8 {
                badgePill(
                    label: "✓ Trusted Creator",
                    foreground: Color(red: 0.25, green: 0.88, blue: 0.56),
                    background: Color(red: 0.25, green: 0.88, blue: 0.56).opacity(0.13),
                    border: Color(red: 0.25, green: 0.88, blue: 0.56).opacity(0.3)
                )
            } else if trustScore < 0.5 {
                badgePill(
                    label: "Building Trust",
                    foreground: Color(red: 0.96, green: 0.65, blue: 0.14),
                    background: Color(red: 0.96, green: 0.65, blue: 0.14).opacity(0.13),
                    border: Color(red: 0.96, green: 0.65, blue: 0.14).opacity(0.25)
                )
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showExplainer) {
            TrustScoreExplainerSheet(trustScore: trustScore)
        }
    }

    private func badgePill(label: String, foreground: Color, background: Color, border: Color) -> some View {
        Button {
            showExplainer = true
        } label: {
            Text(label)
                .font(.systemScaled(12, weight: .semibold))
                .foregroundColor(foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(background)
                        .overlay(Capsule().strokeBorder(border, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}

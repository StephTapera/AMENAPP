import SwiftUI

struct AmenModerationDashboardView: View {
    @StateObject private var service = ModerationService()
    @State private var selectedTab: ModTab = .cases
    @State private var selectedCase: ModerationCase? = nil
    @State private var selectedEscalation: CrisisEscalation? = nil

    enum ModTab: String, CaseIterable { case cases = "Cases", crisis = "Crisis", metrics = "Metrics" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(ModTab.allCases, id: \.self) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented).padding()
                switch selectedTab {
                case .cases: casesTab
                case .crisis: crisisTab
                case .metrics: metricsTab
                }
            }
            .navigationTitle("Moderation")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { service.startListening() }
            .sheet(item: $selectedCase) { c in ModerationCaseDetailView(moderationCase: c, service: service) }
            .sheet(item: $selectedEscalation) { e in CrisisEscalationView(escalation: e, service: service) }
        }
    }

    private var casesTab: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if service.isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
                else if service.openCases.isEmpty {
                    emptyState(icon: "checkmark.circle.fill", title: "All clear", subtitle: "No open moderation cases")
                } else {
                    ForEach(service.openCases) { c in
                        moderationCaseRow(c).onTapGesture { selectedCase = c }
                    }
                }
            }
            .padding(16)
        }
    }

    private var crisisTab: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if service.crisisEscalations.isEmpty {
                    emptyState(icon: "heart.circle.fill", title: "No active escalations", subtitle: "Crisis team is up to date")
                } else {
                    ForEach(service.crisisEscalations) { e in
                        crisisEscalationRow(e).onTapGesture { selectedEscalation = e }
                    }
                }
            }
            .padding(16)
        }
    }

    private var metricsTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    metricCard(value: "\(service.openCases.count)", label: "Open Cases", color: Color(red: 0.95, green: 0.40, blue: 0.40))
                    metricCard(value: "\(service.crisisEscalations.count)", label: "Active Escalations", color: Color(red: 0.95, green: 0.70, blue: 0.30))
                }
                metricCard(value: "\(service.openCases.filter { $0.flag.severity == 3 }.count)", label: "High Severity Cases", color: Color(red: 0.95, green: 0.40, blue: 0.40))
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }

    private func moderationCaseRow(_ c: ModerationCase) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(c.flag.severity == 3 ? Color.red : c.flag.severity == 2 ? Color.orange : Color.yellow)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(c.type.displayName).font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(c.flag.reason).font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary).lineLimit(1)
                if let ts = c.flag.flaggedAt?.dateValue() {
                    Text(ts.formatted(.relative(presentation: .named))).font(.custom("OpenSans-Regular", size: 11)).foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }
            Spacer()
            Text("Sev \(c.flag.severity)").font(.custom("OpenSans-Bold", size: 12)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(c.flag.severity == 3 ? Color.red : c.flag.severity == 2 ? Color.orange : Color.green)
                .cornerRadius(8)
        }
        .padding(12).background(AmenTheme.Colors.surfaceCard).cornerRadius(12)
        .accessibilityLabel("Moderation case: \(c.type.displayName), severity \(c.flag.severity)")
    }

    private func crisisEscalationRow(_ e: CrisisEscalation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(e.severity == 3 ? Color.red : e.severity == 2 ? Color.orange : Color.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.type.capitalized).font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(e.indicators.prefix(2).joined(separator: ", ")).font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Sev \(e.severity)").font(.custom("OpenSans-Bold", size: 11)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(e.severity >= 3 ? Color.red : Color.orange).cornerRadius(6)
                Text(e.contacted ? "Contacted" : "Pending").font(.custom("OpenSans-Regular", size: 10)).foregroundStyle(e.contacted ? .green : AmenTheme.Colors.textTertiary)
            }
        }
        .padding(12).background(AmenTheme.Colors.surfaceCard).cornerRadius(12)
        .accessibilityLabel("Crisis escalation, severity \(e.severity), \(e.contacted ? "contacted" : "pending")")
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.green)
            Text(title).font(.custom("OpenSans-Bold", size: 17)).foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(subtitle).font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func metricCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value).font(.custom("OpenSans-Bold", size: 28)).foregroundStyle(color)
            Text(label).font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary).multilineTextAlignment(.center)
        }
        .padding(16).background(AmenTheme.Colors.surfaceCard).cornerRadius(14)
        .accessibilityElement(children: .combine).accessibilityLabel("\(label): \(value)")
    }
}

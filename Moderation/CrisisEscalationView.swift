import SwiftUI

struct CrisisEscalationView: View {
    let escalation: CrisisEscalation
    let service: ModerationService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMethod: ContactMethod = .text
    @State private var isContacting = false

    enum ContactMethod: String, CaseIterable {
        case phone, text, email
        var displayName: String { rawValue.capitalized }
        var icon: String { switch self { case .phone: return "phone.fill"; case .text: return "message.fill"; case .email: return "envelope.fill" } }
    }

    private let templateMessage = "Hi, we noticed you accessed crisis resources on AMEN. We care about you and want to connect you with 24/7 support. Please call 988 (Suicide & Crisis Lifeline) or text HOME to 741741. We're here for you."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    escalationHeader
                    indicatorsSection
                    contactSection
                    resourcesSection
                }
                .padding(16).padding(.bottom, 32)
            }
            .navigationTitle("Crisis Escalation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }.font(.custom("OpenSans-Regular", size: 16))
                }
            }
        }
    }

    private var escalationHeader: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(escalation.severity == 3 ? .red : escalation.severity == 2 ? .orange : .yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text(escalation.type.capitalized).font(.custom("OpenSans-Bold", size: 17)).foregroundStyle(AmenTheme.Colors.textPrimary)
                if let ts = escalation.detectedAt?.dateValue() {
                    Text("Detected \(ts.formatted(.relative(presentation: .named)))").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
            Spacer()
            Text(escalation.contacted ? "Contacted" : "Pending")
                .font(.custom("OpenSans-Bold", size: 12)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(escalation.contacted ? Color.green : Color.orange).cornerRadius(10)
        }
        .padding(14).background(AmenTheme.Colors.surfaceCard).cornerRadius(14)
    }

    private var indicatorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detected Indicators").font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(AmenTheme.Colors.textPrimary)
            ForEach(escalation.indicators, id: \.self) { indicator in
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Color.red)
                    Text(indicator).font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
                }
                .accessibilityLabel(indicator)
            }
        }
        .padding(14).background(AmenTheme.Colors.surfaceCard).cornerRadius(14)
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contact Options").font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(AmenTheme.Colors.textPrimary)
            Picker("Contact method", selection: $selectedMethod) {
                ForEach(ContactMethod.allCases, id: \.self) { m in
                    Label(m.displayName, systemImage: m.icon).tag(m)
                }
            }
            .pickerStyle(.segmented)
            Text("Template Message").font(.custom("OpenSans-Bold", size: 13)).foregroundStyle(AmenTheme.Colors.textSecondary)
            Text(templateMessage).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(AmenTheme.Colors.textPrimary).lineSpacing(4)
                .padding(10).background(Color(red: 0.40, green: 0.70, blue: 0.95).opacity(0.08)).cornerRadius(8)
            Text("Note: Send this message manually. Log the contact below after sending.")
                .font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textTertiary)
            Button(isContacting ? "Logging..." : "Log Contact Attempt") {
                isContacting = true
                Task {
                    await service.markEscalationContacted(escalationId: escalation.id ?? "", method: selectedMethod.rawValue)
                    isContacting = false
                    dismiss()
                }
            }
            .font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(.white)
            .padding().frame(maxWidth: .infinity)
            .background(Color(red: 0.40, green: 0.70, blue: 0.95)).cornerRadius(12)
            .disabled(isContacting || escalation.contacted)
            .accessibilityLabel("Log contact attempt via \(selectedMethod.displayName)")
        }
        .padding(14).background(AmenTheme.Colors.surfaceCard).cornerRadius(14)
    }

    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Crisis Resources").font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(AmenTheme.Colors.textPrimary)
            Link("988 Suicide & Crisis Lifeline", destination: URL(string: "https://988lifeline.org")!)
                .font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(Color(red: 0.40, green: 0.70, blue: 0.95))
                .accessibilityLabel("988 Suicide and Crisis Lifeline")
            Link("Crisis Text Line (text HOME to 741741)", destination: URL(string: "https://crisistextline.org")!)
                .font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(Color(red: 0.40, green: 0.70, blue: 0.95))
                .accessibilityLabel("Crisis Text Line")
            Link("SAMHSA National Helpline", destination: URL(string: "https://www.samhsa.gov/find-help/national-helpline")!)
                .font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(Color(red: 0.40, green: 0.70, blue: 0.95))
                .accessibilityLabel("SAMHSA National Helpline")
        }
        .padding(14).background(AmenTheme.Colors.surfaceCard).cornerRadius(14)
    }
}

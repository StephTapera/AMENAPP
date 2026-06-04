import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseAnalytics

// MARK: - Sunday Home View
// Replaces the normal home feed on the user's configured rest day.
// Sections: Today's Church · Church Notes · Today's Verse · Prayer Focus · Reflection Feed preview

struct SundayHomeView: View {

    @ObservedObject private var gate = RestModeGate.shared

    // Navigation callbacks wired from HomeView / ContentView
    var onFindChurch: () -> Void
    var onChurchNotes: () -> Void
    var onDailyVerse: () -> Void
    var onPrayerRequest: () -> Void
    var onOpenFeed: () -> Void         // Used by "Return tomorrow" / override tap

    @State private var savedChurch: SundayChurchSnapshot? = nil
    @State private var todayVerse: String = ""
    @State private var todayVerseRef: String = ""
    @State private var isLoadingVerse = false
    @State private var prayerFocus: String = ""
    @State private var reflectionDraftsCount: Int = 0
    @State private var showDraftCount = false
    @State private var showOverrideSheet = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    sundayTopBar
                        .padding(.bottom, 8)

                    greetingCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    if let church = savedChurch {
                        todayChurchCard(church)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    } else {
                        findChurchCard
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    churchNotesCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    verseCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    prayerFocusCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    if showDraftCount {
                        mondayDraftsCard
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    returnTomorrowFooter
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            gate.logRestModeHomeViewed()
            loadSavedChurch()
            loadTodayVerse()
            loadReflectionDrafts()
        }
        .sheet(isPresented: $showOverrideSheet) {
            RestModeOverrideFlowSheet(onOverrideGranted: onOpenFeed)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Top Bar

    private var sundayTopBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(gate.activeName)
                    .font(AMENFont.semiBold(17))
                Text(todayDateString)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "moon.stars")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Greeting

    private var greetingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Good \(timeOfDayGreeting).")
                .font(AMENFont.semiBold(20))

            Text("Today is set aside for worship, rest, and reflection.")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(sundayCardBackground)
    }

    // MARK: - Today's Church

    private func todayChurchCard(_ church: SundayChurchSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Your Church Today")

            VStack(alignment: .leading, spacing: 6) {
                Text(church.name)
                    .font(AMENFont.semiBold(17))
                if let service = church.serviceTime {
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.systemScaled(13))
                            .foregroundStyle(.secondary)
                        Text("Service: \(service)")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                    }
                }
                if let address = church.address {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin")
                            .font(.systemScaled(13))
                            .foregroundStyle(.secondary)
                        Text(address)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            HStack(spacing: 10) {
                SundayActionChip(icon: "arrow.triangle.turn.up.right.circle", title: "Directions") {
                    if let lat = church.latitude, let lon = church.longitude,
                       let url = URL(string: "maps://?daddr=\(lat),\(lon)") {
                        UIApplication.shared.open(url)
                    }
                }
                SundayActionChip(icon: "note.text", title: "Open Notes") {
                    Analytics.logEvent("church_notes_opened_from_rest_mode", parameters: [:])
                    onChurchNotes()
                }
            }
        }
        .padding(20)
        .background(sundayCardBackground)
    }

    // MARK: - Find a Church card (no saved church)

    private var findChurchCard: some View {
        Button(action: {
            Analytics.logEvent("find_church_opened_from_rest_mode", parameters: [:])
            onFindChurch()
        }) {
            HStack(spacing: 16) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Find a Church")
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(.primary)
                    Text("Find a service near you today")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .background(sundayCardBackground)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Church Notes card

    private var churchNotesCard: some View {
        Button(action: {
            Analytics.logEvent("church_notes_opened_from_rest_mode", parameters: [:])
            onChurchNotes()
        }) {
            HStack(spacing: 16) {
                Image(systemName: "note.text")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Church Notes")
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(.primary)
                    Text("Capture today's sermon")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .background(sundayCardBackground)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Verse card

    private var verseCard: some View {
        Button(action: onDailyVerse) {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Today's Verse")

                if isLoadingVerse {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !todayVerse.isEmpty {
                    Text(todayVerse)
                        .font(AMENFont.regular(15))
                        .italic()
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !todayVerseRef.isEmpty {
                        Text("— \(todayVerseRef)")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Tap to read today's verse")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(sundayCardBackground)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Prayer Focus card

    private var prayerFocusCard: some View {
        Button(action: onPrayerRequest) {
            HStack(spacing: 16) {
                Image(systemName: "hands.sparkles")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Prayer")
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(.primary)
                    Text(prayerFocus.isEmpty ? "Share a request or pray for others" : prayerFocus)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .background(sundayCardBackground)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Monday Drafts card

    private var mondayDraftsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Drafts for Tomorrow")

            HStack(spacing: 12) {
                Image(systemName: "tray.2")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)

                Text("\(reflectionDraftsCount) reflection\(reflectionDraftsCount == 1 ? "" : "s") saved for Monday")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
            }

            Text("You can review and publish them when Amen returns to normal tomorrow.")
                .font(AMENFont.regular(13))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(sundayCardBackground)
    }

    // MARK: - Return Tomorrow footer

    private var returnTomorrowFooter: some View {
        VStack(spacing: 12) {
            Text("Social features return tomorrow.")
                .font(AMENFont.regular(13))
                .foregroundStyle(.tertiary)

            if gate.policy?.allowTemporaryOverride == true {
                Button {
                    gate.logOverrideRequested()
                    showOverrideSheet = true
                } label: {
                    Text("I need access for a moment")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var sundayCardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AMENFont.semiBold(12))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .kerning(0.5)
    }

    private var todayDateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d"
        return fmt.string(from: Date())
    }

    private var timeOfDayGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 0..<12: return "morning"
        case 12..<17: return "afternoon"
        default: return "evening"
        }
    }

    // MARK: - Data loading

    private func loadSavedChurch() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            do {
                let snap = try await Firestore.firestore()
                    .collection("users").document(uid)
                    .collection("savedChurch").document("primary")
                    .getDocument()
                if let data = snap.data() {
                    savedChurch = SundayChurchSnapshot(
                        id: snap.documentID,
                        name: data["name"] as? String ?? "",
                        serviceTime: data["serviceTime"] as? String,
                        address: data["address"] as? String,
                        latitude: data["latitude"] as? Double,
                        longitude: data["longitude"] as? Double
                    )
                }
            } catch {}
        }
    }

    private func loadTodayVerse() {
        isLoadingVerse = true
        Task {
            do {
                let snap = try await Firestore.firestore()
                    .collection("dailyVerses")
                    .document(todayKey)
                    .getDocument()
                if let data = snap.data() {
                    todayVerse = data["text"] as? String ?? ""
                    todayVerseRef = data["reference"] as? String ?? ""
                }
            } catch {}
            isLoadingVerse = false
        }
    }

    private func loadReflectionDrafts() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            do {
                let snap = try await Firestore.firestore()
                    .collection("users").document(uid)
                    .collection("postDrafts")
                    .whereField("isDraftForMonday", isEqualTo: true)
                    .getDocuments()
                reflectionDraftsCount = snap.documents.count
                showDraftCount = reflectionDraftsCount > 0
            } catch {}
        }
    }

    private var todayKey: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}

// MARK: - SundayActionChip

private struct SundayActionChip: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(AMENFont.semiBold(13))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SundayChurchSnapshot

struct SundayChurchSnapshot: Identifiable {
    let id: String
    let name: String
    let serviceTime: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
}

// MARK: - Preview

#Preview {
    SundayHomeView(
        onFindChurch: {},
        onChurchNotes: {},
        onDailyVerse: {},
        onPrayerRequest: {},
        onOpenFeed: {}
    )
}

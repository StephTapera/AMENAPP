//
//  ChurchProfileView.swift
//  AMENAPP
//
//  Full church profile with interactive actions
//  Website, Call, Email, Directions, Service Times, Share, Save
//

import SwiftUI
import MapKit
import SafariServices
import Combine
import CoreLocation
import EventKit
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

struct ChurchProfileView: View {
    let churchId: String
    @StateObject private var viewModel: ChurchProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // Live Activity state
    @State private var serviceModeActive = false
    @State private var selectedServiceForMode: ChurchEntity.ServiceTime? = nil

    // Feature 05: Plan My Visit
    @State private var showPlanVisit = false

    // Feature 03: Calendar cross-ref
    @StateObject private var calendarCrossRef = ServiceCalendarManager()
    
    init(churchId: String) {
        self.churchId = churchId
        _viewModel = StateObject(wrappedValue: ChurchProfileViewModel(churchId: churchId))
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .topTrailing) {
                if let profileData = viewModel.profileData {
                    // ── Scroll-driven expanding sheet layout ──────────────
                    ExpandingBottomSheet(
                        minHeight: 260,
                        maxHeight: (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.height ?? 852) * 0.82
                    ) {
                        // Hero: full-bleed photo fills the space behind the sheet
                        churchHeroBackground(profileData.church)
                            .ignoresSafeArea()
                    } expandedContent: {
                        churchSheetContent(profileData)
                    }
                    .ignoresSafeArea(edges: .bottom)

                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Floating dismiss button
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }
                .padding(.top, 54)
                .padding(.trailing, 16)
            }
            .navigationBarHidden(true)
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $viewModel.showSafari) {
                if let url = viewModel.safariURL {
                    SafariView(url: url)
                }
            }
            .sheet(isPresented: $showPlanVisit) {
                if let church = viewModel.profileData?.church {
                    PlanMyVisitView(churchId: church.id, churchName: church.name, churchAddress: church.address)
                }
            }
        }
        .task {
            await viewModel.loadProfile()
        }
    }

    // MARK: - Hero background (sits behind the sheet)

    @ViewBuilder
    private func churchHeroBackground(_ church: ChurchEntity) -> some View {
        ZStack(alignment: .bottom) {
            // Photo
            if let photoURL = church.photoURL {
                CachedAsyncImage(url: URL(string: photoURL)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    churchPhotoPlaceholder
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                churchPhotoPlaceholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Brand color tint + DNA bar overlay (additive, non-blocking)
            ChurchBannerOverlay(churchId: church.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom gradient so hero blends into the sheet
            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 180)

            // Name + denomination visible in hero
            VStack(spacing: 4) {
                Text(church.name)
                    .font(.custom("OpenSans-Bold", size: 26))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

                if let denomination = church.denomination {
                    Text(denomination)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 270) // leave space for the min-height sheet
        }
        // Logo overlay: top-right corner
        .overlay(alignment: .topTrailing) {
            ChurchLogoOverlay(churchId: church.id, churchName: church.name)
                .padding(.top, 60)
                .padding(.trailing, 16)
        }
        // Pulse dot: top-left corner
        .overlay(alignment: .topLeading) {
            SundayPulseDot(churchId: church.id)
                .padding(.top, 64)
                .padding(.leading, 16)
        }
    }

    // MARK: - Sheet content (quick actions + info + services + tips)

    @ViewBuilder
    private func churchSheetContent(_ profileData: ChurchProfileData) -> some View {
        VStack(spacing: 0) {
            // Quick actions
            quickActionsBar(profileData.church)
                .padding(.top, 4)

            Divider()
                .padding(.vertical, 16)
                .padding(.horizontal, 20)

            // Church info
            churchInfoSection(profileData.church)

            // DNA theological profile link
            ChurchDNALink(churchId: profileData.church.id)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            Divider()
                .padding(.vertical, 12)
                .padding(.horizontal, 20)

            // Chemistry score
            ChurchChemistryView(churchId: profileData.church.id)
                .padding(.horizontal, 20)

            // Teaching style compatibility
            TeachingCompatibilityView(churchId: profileData.church.id)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            // Service times
            if !profileData.upcomingServices.isEmpty {
                serviceTimesSection(profileData.upcomingServices)
            }

            // Neighborhood density map
            ChurchNeighborhoodMapView(church: profileData.church)
                .padding(.top, 8)

            // Recent tips
            if !profileData.recentTips.isEmpty {
                tipsSection(profileData.recentTips)
            }

            // Community Vibe analysis (Feature 04)
            ChurchVibeView(churchId: profileData.church.id)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // Church Pulse — active prayers + recent testimonies for this church
            ChurchPulseSection(churchId: profileData.church.id)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // Plan My Visit (Feature 05)
            Button {
                showPlanVisit = true
            } label: {
                Label("Plan My Visit", systemImage: "calendar.badge.plus")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // First visit guide button
            FirstVisitGuideButton(church: profileData.church)
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
    }
    
    
    private var churchPhotoPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: "building.columns.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
    
    // MARK: - Quick Actions Bar
    
    @ViewBuilder
    private func quickActionsBar(_ church: ChurchEntity) -> some View {
        HStack(spacing: 0) {
            // Website
            if church.website != nil {
                quickActionButton(
                    icon: "globe",
                    label: "Website",
                    action: {
                        if let website = church.website {
                            let normalized = website.hasPrefix("http://") || website.hasPrefix("https://") ? website : "https://\(website)"
                            if let url = URL(string: normalized) {
                                viewModel.safariURL = url
                                viewModel.showSafari = true
                            }
                        }
                    }
                )
            }
            
            // Call
            if let phone = church.phoneNumber {
                quickActionButton(
                    icon: "phone.fill",
                    label: "Call",
                    action: {
                        if let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: ""))") {
                            openURL(url)
                        }
                    }
                )
            }
            
            // Email
            if let email = church.email {
                quickActionButton(
                    icon: "envelope.fill",
                    label: "Email",
                    action: {
                        if let url = URL(string: "mailto:\(email)") {
                            openURL(url)
                        }
                    }
                )
            }
            
            // Directions
            quickActionButton(
                icon: "location.fill",
                label: "Directions",
                action: {
                    viewModel.openDirections()
                }
            )
            
            // Share
            quickActionButton(
                icon: "square.and.arrow.up",
                label: "Share",
                action: {
                    viewModel.shareChurch()
                }
            )
            
            // Save
            quickActionButton(
                icon: viewModel.isSaved ? "bookmark.fill" : "bookmark",
                label: viewModel.isSaved ? "Saved" : "Save",
                action: {
                    Task {
                        await viewModel.toggleSave()
                    }
                }
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    
    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
                
                Text(label)
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Church Info Section
    
    @ViewBuilder
    private func churchInfoSection(_ church: ChurchEntity) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Address
            infoRow(
                icon: "mappin.circle.fill",
                label: "Address",
                value: "\(church.address)\n\(church.city), \(church.state ?? "") \(church.zipCode ?? "")"
            )
            
            // Phone
            if let phone = church.phoneNumber {
                infoRow(
                    icon: "phone.circle.fill",
                    label: "Phone",
                    value: phone
                )
            }
            
            // Email
            if let email = church.email {
                infoRow(
                    icon: "envelope.circle.fill",
                    label: "Email",
                    value: email
                )
            }
            
            // Stats
            HStack(spacing: 20) {
                statBadge(value: church.memberCount, label: "Members")
                statBadge(value: church.visitCount, label: "Visitors")
                statBadge(value: church.tipCount, label: "Tips")
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
    }
    
    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.primary)
            }
        }
    }
    
    private func statBadge(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            
            Text(label)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Service Times Section
    
    @ViewBuilder
    private func serviceTimesSection(_ services: [ChurchEntity.ServiceTime]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Service Times")
                    .font(.custom("OpenSans-Bold", size: 18))
                Spacer()
                Button {
                    calendarCrossRef.checkAvailability(for: services)
                } label: {
                    if calendarCrossRef.isChecking {
                        ProgressView().scaleEffect(0.75)
                    } else {
                        Label("My Calendar", systemImage: "calendar")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            ForEach(services, id: \.self) { service in
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dayName(service.dayOfWeek))
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)

                            if let serviceType = service.serviceType {
                                Text(serviceType)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        HStack(spacing: 10) {
                            Text(service.time)
                                .font(.custom("OpenSans-Bold", size: 15))
                                .foregroundStyle(.blue)

                            // Calendar conflict indicator (Feature 03)
                            if calendarCrossRef.hasConflict(for: service) {
                                Label("Conflict", systemImage: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            } else if calendarCrossRef.isLoaded {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }

                            // Start Service Mode button (only if Live Activities available)
                            if LiveActivityManager.shared.isLiveActivitiesAvailable {
                                Button {
                                    startServiceMode(service: service, church: viewModel.profileData?.church)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: serviceModeActive && selectedServiceForMode == service
                                              ? "stop.circle.fill" : "play.circle")
                                            .font(.system(size: 14))
                                        Text(serviceModeActive && selectedServiceForMode == service
                                             ? "End" : "Start")
                                            .font(.custom("OpenSans-SemiBold", size: 12))
                                    }
                                    .foregroundStyle(serviceModeActive && selectedServiceForMode == service
                                                    ? Color.red : Color.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(Color(.secondarySystemBackground))
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 16)
    }

    private func startServiceMode(service: ChurchEntity.ServiceTime, church: ChurchEntity?) {
        guard let church = church else { return }

        if serviceModeActive && selectedServiceForMode == service {
            // End service mode
            Task {
                await LiveActivityManager.shared.endChurchServiceActivity()
                await MainActor.run {
                    serviceModeActive = false
                    selectedServiceForMode = nil
                }
            }
            return
        }

        // Parse service date for today (or next occurrence)
        let serviceDate = nextServiceDate(for: service)

        selectedServiceForMode = service
        serviceModeActive = true

        // Light haptic on start
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()

        LiveActivityManager.shared.startChurchServiceActivity(
            churchId: church.id,
            churchName: church.name,
            serviceType: service.serviceType ?? "Service",
            serviceDate: serviceDate
        )
    }

    /// Returns the next calendar Date for a given ServiceTime (today if upcoming, else next week)
    private func nextServiceDate(for service: ChurchEntity.ServiceTime) -> Date {
        let calendar = Calendar.current
        let today = Date()
        let todayWeekday = calendar.component(.weekday, from: today) // 1=Sun, 7=Sat
        // ChurchEntity uses 1=Sunday, 7=Saturday — matches Calendar.weekday
        var daysUntil = (service.dayOfWeek - todayWeekday + 7) % 7

        // Parse time string e.g. "9:00 AM"
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US")
        let referenceDate = formatter.date(from: service.time) ?? Date()
        let serviceHour = Calendar.current.component(.hour, from: referenceDate)
        let serviceMinute = Calendar.current.component(.minute, from: referenceDate)

        // If today and time already past, move to next week
        if daysUntil == 0 {
            let nowHour = calendar.component(.hour, from: today)
            let nowMinute = calendar.component(.minute, from: today)
            if nowHour > serviceHour || (nowHour == serviceHour && nowMinute >= serviceMinute) {
                daysUntil = 7
            }
        }

        var components = calendar.dateComponents([.year, .month, .day], from: today)
        components.day = (components.day ?? 0) + daysUntil
        components.hour = serviceHour
        components.minute = serviceMinute
        components.second = 0
        return calendar.date(from: components) ?? Date()
    }
    
    private func dayName(_ day: Int) -> String {
        let days = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[min(max(day, 0), 7)]
    }
    
    // MARK: - Tips Section
    
    @ViewBuilder
    private func tipsSection(_ tips: [ChurchTip]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visitor Tips")
                .font(.custom("OpenSans-Bold", size: 18))
                .padding(.horizontal, 20)
            
            ForEach(tips) { tip in
                ChurchTipCard(tip: tip, onHelpful: {
                    Task {
                        await viewModel.markTipHelpful(tipId: tip.id)
                    }
                })
            }
        }
        .padding(.top, 16)
    }
}

// MARK: - Church Tip Card

struct ChurchTipCard: View {
    let tip: ChurchTip
    let onHelpful: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author info
            HStack(spacing: 8) {
                if let photoURL = tip.authorPhotoURL {
                    CachedAsyncImage(url: URL(string: photoURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                }
                
                Text(tip.authorName)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Category badge
                HStack(spacing: 4) {
                    Image(systemName: tip.category.icon)
                        .font(.system(size: 10))
                    
                    Text(tip.category.displayName)
                        .font(.custom("OpenSans-Regular", size: 11))
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Tip content
            Text(tip.content)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Helpful button
            Button(action: onHelpful) {
                HStack(spacing: 4) {
                    Image(systemName: tip.isHelpful ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 12))
                    
                    Text("Helpful (\(tip.helpfulCount))")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
                .foregroundStyle(tip.isHelpful ? .blue : .secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }
}

// MARK: - Safari View

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - View Model

@MainActor
class ChurchProfileViewModel: ObservableObject {
    let churchId: String
    
    @Published var profileData: ChurchProfileData?
    @Published var isLoading = false
    @Published var error: String?
    @Published var userLocation: CLLocation?
    @Published var isSaved = false
    @Published var showSafari = false
    @Published var safariURL: URL?
    
    private let service = ChurchDataService.shared
    private let locationManager = CLLocationManager()
    
    init(churchId: String) {
        self.churchId = churchId
        setupLocation()
    }
    
    private func setupLocation() {
        locationManager.requestWhenInUseAuthorization()
        userLocation = locationManager.location
    }
    
    func loadProfile() async {
        isLoading = true
        error = nil
        
        do {
            profileData = try await service.loadProfile(
                churchId: churchId,
                userLocation: userLocation
            )
            isSaved = profileData?.havePlannedVisit ?? false
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func toggleSave() async {
        guard profileData != nil else { return }
        
        do {
            if isSaved {
                // Remove save (would need to implement)
                isSaved = false
            } else {
                try await service.setRelation(
                    churchId: churchId,
                    relation: .interested
                )
                isSaved = true
            }
        } catch {
            dlog("⚠️ Failed to toggle save: \(error)")
        }
    }
    
    func openDirections() {
        guard let church = profileData?.church else { return }
        
        let coordinate = church.coordinate
        let mapItem = MKMapItem(location: CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ), address: nil)
        mapItem.name = church.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
    
    func shareChurch() {
        guard let church = profileData?.church else { return }
        
        let deepLink = ChurchDeepLink(churchId: church.id)
        let urlString = deepLink.url?.absoluteString ?? "https://amenapp.com/church/\(church.id)"
        let text = "Check out \(church.name) on AMEN: \(urlString)"
        
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    func markTipHelpful(tipId: String) async {
        do {
            try await service.markTipHelpful(tipId: tipId)
            // Reload profile to update tip counts
            await loadProfile()
        } catch {
            dlog("⚠️ Failed to mark tip helpful: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    ChurchProfileView(churchId: "sample-church-id")
}

// ================================================================
// FEATURE 03 — SERVICE TIME CALENDAR CROSS-REF
// ================================================================

class ServiceCalendarManager: ObservableObject {
    @Published var isChecking = false
    @Published var isLoaded = false
    @Published var conflictDays: Set<Int> = []  // dayOfWeek values that conflict

    private let eventStore = EKEventStore()

    func checkAvailability(for services: [ChurchEntity.ServiceTime]) {
        isChecking = true
        requestAccess { [weak self] granted in
            guard granted, let self else {
                DispatchQueue.main.async { self?.isChecking = false }
                return
            }
            let now = Date()
            let in30Days = Calendar.current.date(byAdding: .day, value: 30, to: now)!
            let predicate = self.eventStore.predicateForEvents(withStart: now, end: in30Days, calendars: nil)
            let events = self.eventStore.events(matching: predicate)

            var conflicts: Set<Int> = []
            for service in services {
                for event in events {
                    let weekday = Calendar.current.component(.weekday, from: event.startDate) // 1=Sun
                    if weekday == service.dayOfWeek {
                        // Rough time overlap check
                        let fmt = DateFormatter(); fmt.dateFormat = "h:mm a"; fmt.locale = Locale(identifier: "en_US")
                        if let svcDate = fmt.date(from: service.time) {
                            let svcHour = Calendar.current.component(.hour, from: svcDate)
                            let evtHour = Calendar.current.component(.hour, from: event.startDate)
                            let evtEndHour = Calendar.current.component(.hour, from: event.endDate)
                            if svcHour >= evtHour && svcHour <= evtEndHour {
                                conflicts.insert(service.dayOfWeek)
                            }
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                self.conflictDays = conflicts
                self.isChecking = false
                self.isLoaded = true
            }
        }
    }

    func hasConflict(for service: ChurchEntity.ServiceTime) -> Bool {
        conflictDays.contains(service.dayOfWeek)
    }

    private func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents { granted, _ in completion(granted) }
        } else {
            eventStore.requestAccess(to: .event) { granted, _ in completion(granted) }
        }
    }
}

// ================================================================
// FEATURE 04 — COMMUNITY VIBE ANALYSIS
// ================================================================

class ChurchVibeManager: ObservableObject {
    @Published var warmth: Int = 0
    @Published var engagement: Int = 0
    @Published var sermonDepth: Int = 0
    @Published var ageRange: String = ""
    @Published var communityHealth: String = ""
    @Published var isLoading = false
    @Published var hasData = false

    func load(churchId: String) {
        isLoading = true
        Firestore.firestore().collection("churches").document(churchId)
            .getDocument { [weak self] snap, _ in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    guard let vibe = snap?.data()?["vibe"] as? [String: Any] else { return }
                    self?.warmth = vibe["warmth"] as? Int ?? 0
                    self?.engagement = vibe["engagement"] as? Int ?? 0
                    self?.sermonDepth = vibe["sermonDepth"] as? Int ?? 0
                    self?.ageRange = vibe["ageRangeDominant"] as? String ?? ""
                    self?.communityHealth = vibe["communityHealth"] as? String ?? ""
                    self?.hasData = self?.warmth ?? 0 > 0 || self?.engagement ?? 0 > 0
                }
            }
    }
}

struct ChurchVibeView: View {
    let churchId: String
    @StateObject private var mgr = ChurchVibeManager()

    var body: some View {
        Group {
            if mgr.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
            } else if mgr.hasData {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Community Vibe", systemImage: "heart.text.square")
                        .font(.custom("OpenSans-Bold", size: 16))

                    VStack(spacing: 8) {
                        vibeMeter(label: "Warmth", value: mgr.warmth)
                        vibeMeter(label: "Engagement", value: mgr.engagement)
                        vibeMeter(label: "Sermon Depth", value: mgr.sermonDepth)
                    }

                    if !mgr.ageRange.isEmpty || !mgr.communityHealth.isEmpty {
                        HStack(spacing: 8) {
                            if !mgr.ageRange.isEmpty {
                                vibeTag(label: mgr.ageRange, icon: "person.2")
                            }
                            if !mgr.communityHealth.isEmpty {
                                vibeTag(label: mgr.communityHealth, icon: "heart")
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
        .onAppear { mgr.load(churchId: churchId) }
    }

    private func vibeMeter(label: String, value: Int) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            ProgressView(value: Double(value), total: 100)
                .tint(.orange)
                .frame(maxWidth: .infinity)
            Text("\(value)%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.orange)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func vibeTag(label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.orange.opacity(0.1))
            .foregroundStyle(.orange)
            .cornerRadius(20)
    }
}

// ================================================================
// FEATURE 05 — ONE-TAP PLAN MY VISIT
// ================================================================

class PlanVisitManager: ObservableObject {
    enum VisitStep: Equatable {
        case idle, booking, booked, notifying, scheduled, complete, failed
    }

    @Published var step: VisitStep = .idle
    @Published var errorMessage: String?

    func planVisit(churchId: String, churchName: String, serviceLabel: String, serviceDate: Date) {
        guard let uid = Auth.auth().currentUser?.uid else { errorMessage = "Not signed in"; return }
        step = .booking

        let db = Firestore.firestore()
        let visitorRef = db.collection("churchVisitors").document()
        let fmt = ISO8601DateFormatter(); fmt.formatOptions = [.withFullDate]

        visitorRef.setData([
            "churchId": churchId,
            "churchName": churchName,
            "userId": uid,
            "serviceLabel": serviceLabel,
            "serviceDate": fmt.string(from: serviceDate),
            "bookedAt": FieldValue.serverTimestamp(),
            "status": "planned"
        ]) { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    self?.step = .failed
                    self?.errorMessage = error.localizedDescription
                }
                return
            }
            self?.scheduleReminder(churchName: churchName, serviceLabel: serviceLabel, serviceDate: serviceDate)
            self?.animateSteps()
        }
    }

    private func scheduleReminder(churchName: String, serviceLabel: String, serviceDate: Date) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "📍 Visit Reminder"
            content.body = "\(serviceLabel) at \(churchName) is tomorrow!"
            content.sound = .default
            let reminderDate = Calendar.current.date(byAdding: .day, value: -1, to: serviceDate) ?? serviceDate
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "visit_\(serviceDate.timeIntervalSince1970)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func animateSteps() {
        let steps: [(VisitStep, Double)] = [(.booked, 0.4), (.notifying, 0.9), (.scheduled, 1.5), (.complete, 2.1)]
        for (s, delay) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.step = s }
        }
    }
}

struct PlanMyVisitView: View {
    let churchId: String
    let churchName: String
    let churchAddress: String

    @StateObject private var mgr = PlanVisitManager()
    @State private var selectedDate = nextSundayDate()
    @State private var selectedService = "Sunday Morning"
    @Environment(\.dismiss) private var dismiss

    let services = ["Sunday Morning", "Sunday Evening", "Wednesday Night", "First Service", "Second Service"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Church header
                    VStack(spacing: 4) {
                        Text(churchName)
                            .font(.custom("OpenSans-Bold", size: 22))
                        Text(churchAddress)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    if mgr.step == .idle || mgr.step == .failed {
                        VStack(spacing: 16) {
                            DatePicker("Visit Date", selection: $selectedDate, displayedComponents: .date)
                                .padding(.horizontal)

                            Picker("Service", selection: $selectedService) {
                                ForEach(services, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .padding(.horizontal)

                            if let err = mgr.errorMessage {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }

                            Button {
                                mgr.planVisit(churchId: churchId, churchName: churchName,
                                              serviceLabel: selectedService, serviceDate: selectedDate)
                            } label: {
                                Label("Plan My Visit", systemImage: "calendar.badge.plus")
                                    .font(.custom("OpenSans-SemiBold", size: 16))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.orange)
                                    .foregroundStyle(.white)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                    } else {
                        // Step-by-step reveal
                        VStack(alignment: .leading, spacing: 16) {
                            visitStepRow(label: "Visit slot saved",
                                         sub: "\(selectedService) · \(selectedDate.formatted(date: .abbreviated, time: .omitted))",
                                         done: isStepDone(.booked), active: mgr.step == .booking)
                            visitStepRow(label: "Day-before reminder set",
                                         sub: "You'll get a notification the day before",
                                         done: isStepDone(.notifying), active: mgr.step == .booked)
                            visitStepRow(label: "All set!",
                                         sub: "See you \(selectedDate.formatted(.dateTime.weekday(.wide)))!",
                                         done: isStepDone(.complete), active: mgr.step == .scheduled)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)

                        if mgr.step == .complete {
                            Button("Done") { dismiss() }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Plan My Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.disabled(mgr.step == .booking)
                }
            }
        }
    }

    private func visitStepRow(label: String, sub: String, done: Bool, active: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(done ? Color.green : active ? Color.orange : Color.gray.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
                } else if active {
                    ProgressView().scaleEffect(0.5)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(done ? .primary : .secondary)
                Text(sub).font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: done)
    }

    private func isStepDone(_ step: PlanVisitManager.VisitStep) -> Bool {
        let order: [PlanVisitManager.VisitStep] = [.idle, .booking, .booked, .notifying, .scheduled, .complete]
        guard let cur = order.firstIndex(of: mgr.step),
              let target = order.firstIndex(of: step) else { return false }
        return cur > target
    }
}

private func nextSundayDate() -> Date {
    var comps = DateComponents(); comps.weekday = 1
    return Calendar.current.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) ?? Date()
}

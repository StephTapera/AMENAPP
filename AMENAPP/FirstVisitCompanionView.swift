//
//  FirstVisitCompanionView.swift
//  AMENAPP
//
//  Editorial dark accordion redesign — true black background, thin dividers,
//  expandable rows, outline pill buttons. All original functionality preserved.
//

import SwiftUI
import FirebaseFirestore

// MARK: - Design Tokens

private enum PVTokens {
    // Colors
    static let background   = Color(red: 0.04, green: 0.04, blue: 0.04)   // #0A0A0A
    static let surface      = Color(red: 0.09, green: 0.09, blue: 0.09)   // #161616
    static let divider      = Color.white.opacity(0.10)
    static let primary      = Color.white
    static let secondary    = Color(white: 0.55)
    static let tertiary     = Color(white: 0.38)
    static let accent       = Color(red: 0.95, green: 0.82, blue: 0.45)   // warm gold
    static let pillBorder   = Color.white.opacity(0.30)

    // Typography
    static let labelFont    = Font.system(size: 11, weight: .semibold, design: .monospaced)
    static let rowTitleFont = Font.system(size: 22, weight: .bold)
    static let rowMetaFont  = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let bodyFont     = Font.system(size: 15, weight: .regular)
    static let pillFont     = Font.system(size: 12, weight: .semibold, design: .monospaced)

    // Metrics
    static let hPad: CGFloat        = 20
    static let dividerHeight: CGFloat = 0.5
    static let pillHeight: CGFloat  = 38
    static let pillCorner: CGFloat  = 19
    static let chevronSize: CGFloat = 12
    static let heroAspect: CGFloat  = 16 / 9

    // Animations
    static let expandSpring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let pressScale: CGFloat  = 0.97
}

// MARK: - Reusable Components

/// Thin 0.5pt horizontal rule.
private struct ThinDivider: View {
    var opacity: Double = 1.0
    var body: some View {
        Rectangle()
            .fill(PVTokens.divider.opacity(opacity))
            .frame(height: PVTokens.dividerHeight)
            .frame(maxWidth: .infinity)
    }
}

/// Outline pill button matching reference image style.
private struct OutlinePillButton: View {
    let label: String
    let icon: String?
    var isDestructive = false
    var isAccent = false
    let action: () -> Void

    @State private var pressed = false

    var borderColor: Color {
        if isDestructive { return Color.red.opacity(0.6) }
        if isAccent { return PVTokens.accent.opacity(0.8) }
        return PVTokens.pillBorder
    }

    var labelColor: Color {
        if isDestructive { return .red }
        if isAccent { return PVTokens.accent }
        return PVTokens.primary
    }

    var fillColor: Color {
        if isAccent { return PVTokens.accent.opacity(0.08) }
        return Color.clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(label)
                    .font(PVTokens.pillFont)
                    .kerning(0.5)
            }
            .foregroundStyle(labelColor)
            .frame(height: PVTokens.pillHeight)
            .padding(.horizontal, 18)
            .background(fillColor)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(borderColor, lineWidth: 1))
            .scaleEffect(pressed ? PVTokens.pressScale : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: pressed)
        }
        .buttonStyle(.plain)
        ._onButtonGesture(pressing: { p in pressed = p }, perform: {})
    }
}

/// Single accordion row — collapsed shows title + meta tag, expanded reveals content.
private struct AccordionRow<Content: View>: View {
    let title: String
    let meta: String?
    let isExpanded: Bool
    let onTap: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Collapsed header
            Button(action: onTap) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title.uppercased())
                        .font(PVTokens.rowTitleFont)
                        .foregroundStyle(PVTokens.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let meta {
                        Text(meta.uppercased())
                            .font(PVTokens.rowMetaFont)
                            .foregroundStyle(PVTokens.tertiary)
                            .kerning(0.8)
                    }

                    // Dash expander indicator (reference image uses "—" / "–" for expanded)
                    Text(isExpanded ? "—" : "+")
                        .font(.system(size: 16, weight: .light, design: .monospaced))
                        .foregroundStyle(PVTokens.secondary)
                        .frame(width: 20, alignment: .trailing)
                }
                .padding(.vertical, 18)
                .padding(.horizontal, PVTokens.hPad)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.bottom, 20)
            }

            ThinDivider()
        }
    }
}

/// Minimal calendar — black bg, white text, thin chevrons, outlined circle selection.
private struct MinimalCalendarView: View {
    @Binding var selectedDate: Date
    let minDate: Date

    @State private var displayMonth: Date = Date()

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let dayNames = ["S","M","T","W","T","F","S"]

    var body: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: PVTokens.chevronSize, weight: .light))
                        .foregroundStyle(PVTokens.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthLabel)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PVTokens.primary)
                    .kerning(1)

                Spacer()

                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: PVTokens.chevronSize, weight: .light))
                        .foregroundStyle(PVTokens.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, PVTokens.hPad)

            // Day headers
            HStack(spacing: 0) {
                ForEach(Array(dayNames.enumerated()), id: \.offset) { _, d in
                    Text(d)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(PVTokens.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, PVTokens.hPad)

            // Date grid
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(paddedDays, id: \.self) { date in
                    if let date {
                        let isPast    = date < startOfToday
                        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
                        let isToday   = cal.isDateInToday(date)

                        Button {
                            if !isPast {
                                withAnimation(PVTokens.expandSpring) {
                                    selectedDate = date
                                }
                            }
                        } label: {
                            ZStack {
                                if isSelected {
                                    Circle()
                                        .stroke(PVTokens.accent, lineWidth: 1.5)
                                        .padding(2)
                                }
                                if isToday && !isSelected {
                                    Circle()
                                        .fill(PVTokens.secondary.opacity(0.15))
                                        .padding(4)
                                }
                                Text("\(cal.component(.day, from: date))")
                                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(
                                        isSelected ? PVTokens.accent :
                                        isPast ? PVTokens.tertiary.opacity(0.4) :
                                        PVTokens.primary
                                    )
                            }
                            .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                        .disabled(isPast)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
            .padding(.horizontal, PVTokens.hPad)
        }
    }

    private var startOfToday: Date {
        cal.startOfDay(for: Date())
    }

    private var monthLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: displayMonth).uppercased()
    }

    private var paddedDays: [Date?] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: displayMonth)),
              let range = cal.range(of: .day, in: .month, for: monthStart)
        else { return [] }
        let firstWeekday = cal.component(.weekday, from: monthStart) - 1
        let days: [Date?] = (0..<firstWeekday).map { _ in nil }
            + range.compactMap { offset -> Date? in
                cal.date(byAdding: .day, value: offset - 1, to: monthStart)
            }
        return days
    }

    private func shiftMonth(_ delta: Int) {
        if let newMonth = cal.date(byAdding: .month, value: delta, to: displayMonth) {
            withAnimation(PVTokens.expandSpring) { displayMonth = newMonth }
        }
    }
}

// MARK: - Main View

struct FirstVisitCompanionView: View {
    @StateObject private var viewModel = FirstVisitCompanionViewModel()
    @Environment(\.dismiss) private var dismiss

    let church: VisitCompanionChurch

    // Accordion state — only one section open at a time
    @State private var expanded: AccordionSection? = .church

    private enum AccordionSection: Equatable {
        case church, expect, service, date, reminders
    }

    var body: some View {
        ZStack(alignment: .top) {
            PVTokens.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    pageHeader
                    ThinDivider()

                    // ── CHURCH ──────────────────────────────────────────────
                    AccordionRow(
                        title: church.name,
                        meta: church.denomination,
                        isExpanded: expanded == .church,
                        onTap: { toggle(.church) }
                    ) {
                        churchExpanded
                    }

                    // ── WHAT TO EXPECT ──────────────────────────────────────
                    AccordionRow(
                        title: "What to Expect",
                        meta: nil,
                        isExpanded: expanded == .expect,
                        onTap: { toggle(.expect) }
                    ) {
                        expectExpanded
                    }

                    // ── SERVICE ─────────────────────────────────────────────
                    AccordionRow(
                        title: "Service",
                        meta: viewModel.selectedService.map { "\($0.dayOfWeek)  \($0.startTime)" },
                        isExpanded: expanded == .service,
                        onTap: { toggle(.service) }
                    ) {
                        serviceExpanded
                    }

                    // ── DATE ────────────────────────────────────────────────
                    AccordionRow(
                        title: "Date",
                        meta: formattedSelectedDate,
                        isExpanded: expanded == .date,
                        onTap: { toggle(.date) }
                    ) {
                        dateExpanded
                    }

                    // ── REMINDERS & CALENDAR ────────────────────────────────
                    AccordionRow(
                        title: "Reminders",
                        meta: nil,
                        isExpanded: expanded == .reminders,
                        onTap: { toggle(.reminders) }
                    ) {
                        remindersExpanded
                    }

                    // ── ACTION AREA ─────────────────────────────────────────
                    actionArea
                        .padding(.top, 28)
                        .padding(.bottom, 60)
                }
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage { Text(error) }
        }
        .alert("Visit Plan Created", isPresented: $viewModel.showSuccess) {
            Button("Done") { dismiss() }
        } message: {
            Text("Your visit to \(church.name) has been planned.")
        }
        .onAppear {
            viewModel.selectedChurch = church
            Task {
                await viewModel.loadExistingVisitPlan(
                    church: church,
                    serviceDate: viewModel.selectedDate
                )
            }
        }
        // Calendar permission: request access the moment user enables the toggle
        // so the system prompt appears immediately rather than mid-plan-creation.
        .onChange(of: viewModel.addToCalendar) { _, newValue in
            if newValue {
                Task {
                    let granted = await viewModel.requestCalendarAccess()
                    if !granted {
                        viewModel.addToCalendar = false
                    }
                }
            }
        }
    }

    // MARK: - Toggle Accordion

    private func toggle(_ section: AccordionSection) {
        let opening = expanded != section
        withAnimation(PVTokens.expandSpring) {
            expanded = opening ? section : nil
        }
        // Auto-trigger AI visit guide when "What to Expect" opens
        if section == .expect && opening && viewModel.aiVisitTips == nil && !viewModel.isLoadingAITips {
            Task { await viewModel.generateVisitPreparation(for: church) }
        }
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        HStack {
            Text("PLAN YOUR VISIT")
                .font(PVTokens.labelFont)
                .foregroundStyle(PVTokens.tertiary)
                .kerning(1.5)
                .frame(maxWidth: .infinity)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PVTokens.secondary)
                    .frame(width: 32, height: 32)
                    .background(PVTokens.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, PVTokens.hPad)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Church Expanded

    private var churchExpanded: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Hero image placeholder (swap in real church photo via AsyncImage if URL exists)
            GeometryReader { geo in
                ZStack {
                    if let website = church.website,
                       let url = URL(string: website.hasPrefix("http://") || website.hasPrefix("https://") ? website : "https://\(website)") {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                heroPlaceholder
                            }
                        }
                    } else {
                        heroPlaceholder
                    }
                }
                .frame(width: geo.size.width, height: geo.size.width / PVTokens.heroAspect)
                .clipped()
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(PVTokens.heroAspect, contentMode: .fit)
            .padding(.horizontal, PVTokens.hPad)
            .padding(.bottom, 16)

            // Meta row: denomination + verified badge
            HStack(spacing: 0) {
                if let denomination = church.denomination {
                    Text(denomination.uppercased())
                        .font(PVTokens.rowMetaFont)
                        .foregroundStyle(PVTokens.tertiary)
                        .kerning(0.8)
                }
                Spacer()
                if church.verified {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(PVTokens.accent)
                        Text("VERIFIED")
                            .font(PVTokens.rowMetaFont)
                            .foregroundStyle(PVTokens.accent)
                            .kerning(0.8)
                    }
                }
            }
            .padding(.horizontal, PVTokens.hPad)
            .padding(.bottom, 12)

            // Description
            if let desc = church.description, !desc.isEmpty {
                Text(desc)
                    .font(PVTokens.bodyFont)
                    .foregroundStyle(PVTokens.secondary)
                    .lineSpacing(5)
                    .padding(.horizontal, PVTokens.hPad)
                    .padding(.bottom, 20)
            } else {
                Text(church.address.fullAddress)
                    .font(PVTokens.bodyFont)
                    .foregroundStyle(PVTokens.secondary)
                    .lineSpacing(5)
                    .padding(.horizontal, PVTokens.hPad)
                    .padding(.bottom, 20)
            }

            // Action pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    OutlinePillButton(label: "DIRECTIONS", icon: "map") {
                        openMaps()
                    }
                    if let phone = church.phoneNumber {
                        OutlinePillButton(label: "CALL", icon: "phone") {
                            callChurch(phone)
                        }
                    }
                    OutlinePillButton(
                        label: viewModel.visitPlan != nil ? "SAVED" : "SAVE",
                        icon: viewModel.visitPlan != nil ? "checkmark" : "heart",
                        isAccent: viewModel.visitPlan != nil
                    ) {
                        if viewModel.visitPlan == nil {
                            withAnimation(PVTokens.expandSpring) { expanded = .service }
                        }
                    }
                    if let website = church.website,
                       let url = URL(string: website.hasPrefix("http://") || website.hasPrefix("https://") ? website : "https://\(website)") {
                        OutlinePillButton(label: "WEBSITE", icon: "globe") {
                            UIApplication.shared.open(url)
                        }
                    }
                    OutlinePillButton(label: "SHARE", icon: "square.and.arrow.up") {
                        shareChurch()
                    }
                }
                .padding(.horizontal, PVTokens.hPad)
                .padding(.bottom, 4)
            }
        }
    }

    private var heroPlaceholder: some View {
        ZStack {
            PVTokens.surface
            VStack(spacing: 8) {
                Image(systemName: "building.2")
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundStyle(PVTokens.tertiary)
                Text(church.name.prefix(1))
                    .font(.system(size: 52, weight: .thin))
                    .foregroundStyle(PVTokens.tertiary.opacity(0.4))
            }
        }
        .cornerRadius(4)
    }

    // MARK: - What to Expect Expanded

    private var expectExpanded: some View {
        VStack(spacing: 0) {
            let items: [(icon: String, title: String, value: String)] = [
                church.dressCode.map { ("tshirt", "Dress Code", $0) },
                church.parkingInfo.map { ("parkingsign.circle", "Parking", $0) },
                church.accessibilityInfo.map { ("figure.roll", "Accessibility", $0) },
                church.childcareAvailable ? ("figure.2.and.child.holdinghands", "Childcare", "Available") : nil,
                church.welcomeTeamContact.map { ("person.2", "Welcome Team", $0) }
            ].compactMap { $0 }

            if items.isEmpty {
                Text("Contact the church for details.")
                    .font(PVTokens.bodyFont)
                    .foregroundStyle(PVTokens.tertiary)
                    .padding(.horizontal, PVTokens.hPad)
                    .padding(.vertical, 14)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(PVTokens.tertiary)
                            .frame(width: 20)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title.uppercased())
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(PVTokens.tertiary)
                                .kerning(0.6)
                            Text(item.value)
                                .font(PVTokens.bodyFont)
                                .foregroundStyle(PVTokens.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, PVTokens.hPad)
                    .padding(.vertical, 14)

                    if idx < items.count - 1 {
                        ThinDivider()
                            .padding(.horizontal, PVTokens.hPad)
                    }
                }
            }

            // ── AI VISIT GUIDE ───────────────────────────────────────────
            ThinDivider().padding(.horizontal, PVTokens.hPad)

            if viewModel.isLoadingAITips {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(PVTokens.accent)
                        .scaleEffect(0.8)
                    Text("PREPARING YOUR VISIT GUIDE...")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PVTokens.tertiary)
                        .kerning(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PVTokens.hPad)
                .padding(.vertical, 16)

            } else if let tips = viewModel.aiVisitTips {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .light))
                            .foregroundStyle(PVTokens.accent)
                        Text("AI VISIT GUIDE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PVTokens.accent)
                            .kerning(0.6)
                    }
                    Text(tips)
                        .font(PVTokens.bodyFont)
                        .foregroundStyle(PVTokens.secondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, PVTokens.hPad)
                .padding(.vertical, 14)

            } else {
                Button {
                    Task { await viewModel.generateVisitPreparation(for: church) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .light))
                        Text("Get AI Visit Guide")
                            .font(PVTokens.bodyFont)
                    }
                    .foregroundStyle(PVTokens.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PVTokens.hPad)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Service Expanded

    private var serviceExpanded: some View {
        VStack(spacing: 0) {
            if church.services.isEmpty {
                Text("Contact the church for service times.")
                    .font(PVTokens.bodyFont)
                    .foregroundStyle(PVTokens.tertiary)
                    .padding(.horizontal, PVTokens.hPad)
                    .padding(.bottom, 4)
            } else {
                ForEach(Array(church.services.enumerated()), id: \.element.id) { idx, service in
                    Button {
                        withAnimation(PVTokens.expandSpring) {
                            viewModel.selectedService = service
                        }
                    } label: {
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(service.serviceType.uppercased())
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(
                                        viewModel.selectedService?.id == service.id ?
                                        PVTokens.primary : PVTokens.secondary
                                    )
                                    .kerning(0.4)

                                HStack(spacing: 8) {
                                    Text("\(service.dayOfWeek)  \(service.startTime)")
                                        .font(.system(size: 12, weight: .light, design: .monospaced))
                                        .foregroundStyle(PVTokens.tertiary)
                                    if let lang = service.language, lang != "English" {
                                        Text("·  \(lang)")
                                            .font(.system(size: 12, weight: .light, design: .monospaced))
                                            .foregroundStyle(PVTokens.tertiary)
                                    }
                                    if service.streamingAvailable {
                                        Text("·  STREAM")
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(PVTokens.accent.opacity(0.7))
                                    }
                                }
                            }

                            Spacer()

                            // Selection indicator
                            if viewModel.selectedService?.id == service.id {
                                ZStack {
                                    Circle()
                                        .stroke(PVTokens.accent, lineWidth: 1.5)
                                        .frame(width: 20, height: 20)
                                    Circle()
                                        .fill(PVTokens.accent)
                                        .frame(width: 8, height: 8)
                                }
                            } else {
                                Circle()
                                    .stroke(PVTokens.tertiary, lineWidth: 1)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .padding(.horizontal, PVTokens.hPad)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if idx < church.services.count - 1 {
                        ThinDivider()
                            .padding(.horizontal, PVTokens.hPad)
                    }
                }
            }
        }
    }

    // MARK: - Date Expanded

    private var dateExpanded: some View {
        VStack(spacing: 12) {
            MinimalCalendarView(
                selectedDate: $viewModel.selectedDate,
                minDate: Date()
            )

            if !viewModel.isValidVisitDate() {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .light))
                    Text("Please select a future date")
                        .font(.system(size: 12, weight: .light, design: .monospaced))
                }
                .foregroundStyle(Color.orange.opacity(0.85))
                .padding(.horizontal, PVTokens.hPad)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Reminders Expanded

    private var remindersExpanded: some View {
        VStack(spacing: 0) {
            reminderToggleRow(
                icon: "calendar.badge.plus",
                label: "Add to Calendar",
                binding: $viewModel.addToCalendar
            )
            ThinDivider().padding(.horizontal, PVTokens.hPad)
            reminderToggleRow(
                icon: "bell",
                label: "24 hours before",
                binding: $viewModel.enable24HourReminder
            )
            ThinDivider().padding(.horizontal, PVTokens.hPad)
            reminderToggleRow(
                icon: "bell.badge",
                label: "1 hour before",
                binding: $viewModel.enableDayOfReminder
            )
            ThinDivider().padding(.horizontal, PVTokens.hPad)
            reminderToggleRow(
                icon: "note.text.badge.plus",
                label: "Prompt for church note after",
                binding: $viewModel.enablePostVisitReminder
            )
        }
    }

    private func reminderToggleRow(icon: String, label: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(PVTokens.tertiary)
                .frame(width: 20)

            Text(label)
                .font(PVTokens.bodyFont)
                .foregroundStyle(PVTokens.secondary)

            Spacer()

            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(PVTokens.accent)
                .scaleEffect(0.85, anchor: .trailing)
        }
        .padding(.horizontal, PVTokens.hPad)
        .padding(.vertical, 14)
    }

    // MARK: - Action Area

    private var actionArea: some View {
        VStack(spacing: 16) {
            ThinDivider()

            if viewModel.visitPlan == nil {
                // Create button
                VStack(spacing: 10) {
                    Button {
                        Task { await viewModel.createVisitPlan() }
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(PVTokens.background)
                                    .scaleEffect(0.8)
                            } else {
                                Text("PLAN THIS VISIT")
                                    .font(PVTokens.pillFont)
                                    .kerning(1.5)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(isReadyToCreate ? PVTokens.primary : PVTokens.surface)
                        .foregroundStyle(isReadyToCreate ? PVTokens.background : PVTokens.tertiary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isReadyToCreate || viewModel.isLoading)
                    .padding(.horizontal, PVTokens.hPad)
                    .animation(PVTokens.expandSpring, value: isReadyToCreate)

                    if !isReadyToCreate {
                        Text(readinessHint)
                            .font(.system(size: 12, weight: .light, design: .monospaced))
                            .foregroundStyle(PVTokens.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }

            } else {
                // Plan exists
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(PVTokens.accent)
                        Text("VISIT PLANNED")
                            .font(PVTokens.rowMetaFont)
                            .foregroundStyle(PVTokens.accent)
                            .kerning(1.5)
                    }

                    OutlinePillButton(
                        label: "CANCEL VISIT PLAN",
                        icon: "xmark",
                        isDestructive: true
                    ) {
                        Task { await viewModel.cancelVisitPlan() }
                    }
                }
                .padding(.horizontal, PVTokens.hPad)
            }
        }
    }

    // MARK: - Helpers

    private var isReadyToCreate: Bool {
        viewModel.selectedService != nil && viewModel.isValidVisitDate()
    }

    private var readinessHint: String {
        if viewModel.selectedService == nil && !viewModel.isValidVisitDate() {
            return "Select a service and a future date"
        } else if viewModel.selectedService == nil {
            return "Select a service to continue"
        } else {
            return "Select a future date to continue"
        }
    }

    private var formattedSelectedDate: String? {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: viewModel.selectedDate).uppercased()
    }

    // MARK: - Actions

    private func openMaps() {
        let addr = church.address.fullAddress
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?address=\(addr)") {
            UIApplication.shared.open(url)
        }
    }

    private func callChurch(_ phone: String) {
        let clean = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if let url = URL(string: "tel://\(clean)") {
            UIApplication.shared.open(url)
        }
    }

    private func shareChurch() {
        let text = "Check out \(church.name) — \(church.address.fullAddress)"
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}

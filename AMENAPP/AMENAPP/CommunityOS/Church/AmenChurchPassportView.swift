// AmenChurchPassportView.swift
// AMEN Community OS — Church OS (Phase 3 / Agent A8)
//
// The user's Church Passport — a private record of churches visited.
//
// Privacy invariants:
//   - Passport is PRIVATE by default (isPrivate = true)
//   - Lock badge visible at all times when private
//   - visitCount is NEVER displayed publicly (anti-engagement)
//   - Stamps are private by default; user may set individual stamps visible
//
// Design: 3-column grid of stamp cards, home church highlighted with house badge,
// "Add Visit" toolbar button → AddPassportStampSheet.
// Feature-gated by community_os_church_os_enabled (default false).

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - AmenChurchPassportView

struct AmenChurchPassportView: View {

    let userId: String

    @AppStorage("community_os_church_os_enabled")
    private var featureEnabled: Bool = false

    @StateObject private var service = AmenChurchService()

    @State private var showAddStampSheet = false
    @State private var confirmSetHome: ChurchPassportStamp? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        Group {
            if featureEnabled {
                passportContent
            } else {
                unavailablePlaceholder
            }
        }
        .navigationTitle("Church Passport")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadPassport() }
    }

    // MARK: - Unavailable placeholder

    private var unavailablePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text("Church Passport coming soon.")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Passport content

    private var passportContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                passportHeader
                stampsGrid
                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddStampSheet = true } label: {
                    Label("Add Visit", systemImage: "plus")
                }
                .accessibilityLabel("Add a church visit stamp")
            }
        }
        .sheet(isPresented: $showAddStampSheet) {
            AddPassportStampSheet(userId: userId, service: service)
        }
        .confirmationDialog(
            "Set as Home Church?",
            isPresented: Binding(get: { confirmSetHome != nil },
                                 set: { if !$0 { confirmSetHome = nil } }),
            titleVisibility: .visible
        ) {
            if let stamp = confirmSetHome {
                Button("Set \"\(stamp.churchName)\" as Home Church") {
                    Task { await setHomeChurch(churchId: stamp.churchId) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Passport header card

    private var passportHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "book.pages.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("My Church Passport")
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .label))

                if let passport = service.passport {
                    Label(
                        passport.isPrivate ? "Private" : "Visible to followers",
                        systemImage: passport.isPrivate ? "lock.fill" : "globe"
                    )
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }

            Spacer()

            if let passport = service.passport {
                Button {
                    Task { await togglePrivacy(current: passport.isPrivate) }
                } label: {
                    Image(systemName: passport.isPrivate ? "lock.fill" : "lock.open")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(uiColor: .secondarySystemBackground)))
                }
                .accessibilityLabel(passport.isPrivate
                    ? "Passport is private. Tap to make visible."
                    : "Passport is visible. Tap to make private.")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 4)
        )
    }

    // MARK: - Stamps grid

    @ViewBuilder
    private var stampsGrid: some View {
        if service.isLoading {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .frame(height: 100)
                        .accessibilityHidden(true)
                }
            }
        } else if let passport = service.passport {
            let stamps = passport.visibleStamps(showingPrivate: true)
            if stamps.isEmpty {
                emptyPassport
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(stamps) { stamp in
                        PassportStampCard(
                            stamp: stamp,
                            isHomeChurch: stamp.churchId == passport.homeChurchId
                        )
                        .contextMenu {
                            Button {
                                confirmSetHome = stamp
                            } label: {
                                Label("Set as Home Church", systemImage: "house.fill")
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyPassport: some View {
        VStack(spacing: 14) {
            Image(systemName: "building.columns")
                .font(.system(size: 44))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
            Text("No visits yet")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            Text("Tap + to record your first church visit.")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
            Button("Add Visit") { showAddStampSheet = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 4)
                .accessibilityLabel("Add a church visit stamp")
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No church visits recorded. Add a visit to get started.")
    }

    // MARK: - Data loading

    private func loadPassport() async {
        do { try await service.loadPassport(userId: userId) }
        catch { service.error = error.localizedDescription }
    }

    private func setHomeChurch(churchId: String) async {
        do {
            try await Firestore.firestore()
                .collection("churchPassports")
                .document(userId)
                .setData(["homeChurchId": churchId], merge: true)
            try await service.loadPassport(userId: userId)
        } catch { service.error = error.localizedDescription }
    }

    private func togglePrivacy(current: Bool) async {
        do {
            try await Firestore.firestore()
                .collection("churchPassports")
                .document(userId)
                .setData(["isPrivate": !current], merge: true)
            try await service.loadPassport(userId: userId)
        } catch { service.error = error.localizedDescription }
    }
}

// MARK: - PassportStampCard

private struct PassportStampCard: View {
    let stamp: ChurchPassportStamp
    let isHomeChurch: Bool

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return f.string(from: stamp.visitDate)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let logoStr = stamp.churchLogoUrl, let url = URL(string: logoStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                stampFallback
                            }
                        }
                    } else {
                        stampFallback
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if isHomeChurch {
                    Image(systemName: "house.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.accentColor))
                        .offset(x: 4, y: -4)
                        .accessibilityLabel("Home church")
                }
            }

            Text(stamp.churchName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(dateString)
                .font(.caption2)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))

            if stamp.isPrivate {
                Label("Private", systemImage: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(stamp.churchName). Visited \(dateString)." +
            (isHomeChurch ? " Home church." : "") +
            (stamp.isPrivate ? " Private." : "")
        )
    }

    private var stampFallback: some View {
        Color(uiColor: .secondarySystemBackground)
            .overlay(
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            )
    }
}

// MARK: - AddPassportStampSheet

private struct AddPassportStampSheet: View {
    let userId: String
    let service: AmenChurchService

    @Environment(\.dismiss) private var dismiss
    @State private var churchName = ""
    @State private var visitDate  = Date()
    @State private var notes      = ""
    @State private var isSaving   = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Church") {
                    TextField("Church name", text: $churchName)
                        .accessibilityLabel("Church name")
                }
                Section("Visit Details") {
                    DatePicker("Date", selection: $visitDate, displayedComponents: .date)
                        .accessibilityLabel("Visit date")
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Optional visit notes")
                }
                if let err = saveError {
                    Section {
                        Text(err).font(.footnote)
                            .foregroundStyle(Color(uiColor: .systemRed))
                    }
                }
            }
            .navigationTitle("Add Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .font(.subheadline.weight(.semibold))
                        .disabled(churchName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .accessibilityLabel("Save visit stamp")
                }
            }
            .disabled(isSaving)
        }
    }

    private func save() async {
        let trimmed = churchName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true; saveError = nil
        do {
            try await service.addPassportStamp(
                churchId:   UUID().uuidString,
                churchName: trimmed,
                date:       visitDate,
                notes:      notes.isEmpty ? nil : notes,
                userId:     userId
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Preview

#Preview("Church Passport") {
    NavigationStack {
        AmenChurchPassportView(userId: "preview_user_01")
    }
    .onAppear {
        UserDefaults.standard.set(true, forKey: "community_os_church_os_enabled")
    }
}

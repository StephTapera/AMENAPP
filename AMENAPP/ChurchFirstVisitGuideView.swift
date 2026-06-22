// ChurchFirstVisitGuideView.swift
// AMENAPP
//
// First Visit Guide:
//   - "Plan my first visit" button on church detail screen
//   - Calls generateFirstVisitGuide Cloud Function (Claude claude-sonnet-4-6)
//   - Caches in Firestore at churches/{churchId}/firstVisitGuide (30-day TTL)
//   - Displays structured guide: parking, arrival, dress, service flow, convo starters
//   - "Save to notes" button creates a ChurchNote with the guide

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - FirstVisitGuideService

@MainActor
final class FirstVisitGuideService: ObservableObject {
    @Published var guide: FirstVisitGuideData?
    @Published var isLoading = false
    @Published var error: String?

    private lazy var functions = Functions.functions()
    private let db        = Firestore.firestore()

    func load(church: ChurchEntity) async {
        isLoading = true
        error     = nil
        defer { isLoading = false }

        // Try cached Firestore value first
        if let snap = try? await db.collection("churches").document(church.id).getDocument(),
           let d = snap.data(),
           let guideData = d["firstVisitGuide"] as? [String: Any] {
            let cached = FirstVisitGuideData(from: guideData)
            if !cached.isStale {
                guide = cached
                return
            }
        }

        // Call Cloud Function
        do {
            let params: [String: Any] = [
                "churchId":   church.id,
                "churchName": church.name,
                "denomination": church.denomination ?? "",
                "memberCount": church.memberCount,
            ]
            let result = try await functions.httpsCallable("generateFirstVisitGuide").call(params)
            guard let data = result.data as? [String: Any] else {
                error = "Unexpected server response."
                return
            }
            guide = FirstVisitGuideData(from: data)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - FirstVisitGuideView

struct FirstVisitGuideView: View {
    let church: ChurchEntity
    @StateObject private var service = FirstVisitGuideService()
    @State private var notesService  = ChurchNotesService()
    @State private var savedToNotes  = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Preparing your guide…")
                            .font(.systemScaled(14))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let g = service.guide {
                    guideContent(g)
                } else if let err = service.error {
                    VStack(spacing: 12) {
                        Text(err)
                            .font(.systemScaled(14))
                            .foregroundStyle(Color(.secondaryLabel))
                        Button("Retry") { Task { await service.load(church: church) } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("First Visit Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await service.load(church: church) }
    }

    @ViewBuilder
    private func guideContent(_ g: FirstVisitGuideData) -> some View {
        ScrollView {
            VStack(spacing: 0) {

                // MARK: Single-body sections (Parking, Arrival, What to Wear)
                let singleSections: [(String, String?)] = [
                    ("PARKING", g.parking),
                    ("ARRIVAL", g.arrivalTip),
                    ("WHAT TO WEAR", g.whatToWear)
                ]
                ForEach(singleSections, id: \.0) { title, body in
                    if let body {
                        guideSectionCard(title: title, body: body)
                    }
                }

                // MARK: Service Flow
                if !g.serviceFlow.isEmpty {
                    Text("SERVICE FLOW")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(g.serviceFlow.enumerated()), id: \.offset) { index, moment in
                            Text(moment)
                                .font(.systemScaled(15))
                                .foregroundStyle(Color(.label))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            if index < g.serviceFlow.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)
                }

                // MARK: Conversation Starters
                if !g.conversationStarters.isEmpty {
                    Text("CONVERSATION STARTERS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(g.conversationStarters.enumerated()), id: \.offset) { index, starter in
                            Text("\"\(starter)\"")
                                .font(.systemScaled(15))
                                .foregroundStyle(Color(.secondaryLabel))
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            if index < g.conversationStarters.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)
                }

                // MARK: Save to Notes
                VStack(spacing: 0) {
                    Button {
                        saveToNotes(g)
                    } label: {
                        HStack {
                            Image(systemName: savedToNotes ? "checkmark.circle.fill" : "note.text.badge.plus")
                            Text(savedToNotes ? "Saved to Notes" : "Save to Notes")
                                .font(.systemScaled(15, weight: .semibold))
                        }
                        .foregroundStyle(savedToNotes ? .green : Color(.label))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .disabled(savedToNotes)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 24)

                Spacer(minLength: 32)
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func guideSectionCard(title: String, body: String) -> some View {
        let isFirst = title == "PARKING"
        Text(title)
            .font(AMENFont.bold(11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, isFirst ? 16 : 24)
            .padding(.bottom, 8)

        VStack(spacing: 0) {
            Text(body)
                .font(.systemScaled(15))
                .foregroundStyle(Color(.label))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }

    private func saveToNotes(_ g: FirstVisitGuideData) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var content = ""
        if let p = g.parking    { content += "Parking: \(p)\n\n" }
        if let a = g.arrivalTip { content += "Arrival: \(a)\n\n" }
        if let w = g.whatToWear { content += "Dress: \(w)\n\n" }
        if !g.serviceFlow.isEmpty {
            content += "Service Flow:\n" + g.serviceFlow.map { "• \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !g.conversationStarters.isEmpty {
            content += "Conversation Starters:\n" + g.conversationStarters.map { "• \($0)" }.joined(separator: "\n")
        }
        let note = ChurchNote(
            userId:  uid,
            title:   "\(church.name) — First Visit Guide",
            date:    Date(),
            content: content,
            keyPoints: [],
            tags:    ["first-visit", church.name.lowercased()],
            scriptureReferences: []
        )
        Task {
            try? await notesService.createNote(note)
            await MainActor.run { savedToNotes = true }
        }
    }
}

// MARK: - FirstVisitGuideButton (entry point for ChurchProfileView)

struct FirstVisitGuideButton: View {
    let church: ChurchEntity
    @State private var showGuide = false

    var body: some View {
        Button {
            showGuide = true
        } label: {
            Text("Plan my first visit")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(Color(.secondaryLabel))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .sheet(isPresented: $showGuide) {
            FirstVisitGuideView(church: church)
        }
    }
}

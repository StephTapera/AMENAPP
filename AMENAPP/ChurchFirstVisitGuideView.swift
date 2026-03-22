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
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - FirstVisitGuideService

@MainActor
final class FirstVisitGuideService: ObservableObject {
    @Published var guide: FirstVisitGuideData?
    @Published var isLoading = false
    @Published var error: String?

    private let functions = Functions.functions()
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
        NavigationView {
            Group {
                if service.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Preparing your guide…")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let g = service.guide {
                    guideContent(g)
                } else if let err = service.error {
                    VStack(spacing: 12) {
                        Text(err)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(.secondaryLabel))
                        Button("Retry") { Task { await service.load(church: church) } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
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
        List {
            if let parking = g.parking {
                guideSection(title: "Parking", body: parking)
            }
            if let arrival = g.arrivalTip {
                guideSection(title: "Arrival", body: arrival)
            }
            if let wear = g.whatToWear {
                guideSection(title: "What to Wear", body: wear)
            }
            if !g.serviceFlow.isEmpty {
                Section(header: Text("Service Flow").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(.secondaryLabel))) {
                    ForEach(g.serviceFlow, id: \.self) { moment in
                        Text(moment)
                            .font(.system(size: 15))
                            .foregroundStyle(Color(.label))
                    }
                }
            }
            if !g.conversationStarters.isEmpty {
                Section(header: Text("Conversation Starters").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(.secondaryLabel))) {
                    ForEach(g.conversationStarters, id: \.self) { starter in
                        Text(""\(starter)"")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(.secondaryLabel))
                            .italic()
                    }
                }
            }

            Section {
                Button {
                    saveToNotes(g)
                } label: {
                    HStack {
                        Image(systemName: savedToNotes ? "checkmark.circle.fill" : "note.text.badge.plus")
                        Text(savedToNotes ? "Saved to Notes" : "Save to Notes")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(savedToNotes ? .green : Color(.label))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                }
                .disabled(savedToNotes)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func guideSection(title: String, body: String) -> some View {
        Section(header: Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(.secondaryLabel))) {
            Text(body)
                .font(.system(size: 15))
                .foregroundStyle(Color(.label))
        }
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
                .font(.system(size: 15, weight: .semibold))
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

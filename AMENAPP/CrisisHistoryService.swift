//
//  CrisisHistoryService.swift
//  AMENAPP
//
//  Encrypted local-only crisis visit logging.
//  Never sent to a server. User can export or delete at will.
//

import Foundation
import Combine
import CryptoKit
import SwiftUI

// MARK: - Data Model

struct CrisisVisit: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    var durationSeconds: Int
    var actionsUsed: [String]  // e.g. "called_988", "grounding_exercise", "berean_chat"

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: timestamp)
    }

    var formattedDuration: String {
        let mins = durationSeconds / 60
        if mins < 1 { return "< 1 min" }
        return "\(mins) min"
    }
}

// MARK: - Service

@MainActor
final class CrisisHistoryService: ObservableObject {
    static let shared = CrisisHistoryService()

    @Published var visits: [CrisisVisit] = []

    private let fileURL: URL
    private let symmetricKey: SymmetricKey

    // Active session tracking
    private var activeVisitID: UUID?
    private var sessionStart: Date?

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent(".crisis_history.enc")

        // Derive a key from a stable device-specific seed stored in UserDefaults
        // (For a production app, use Keychain — this is a reasonable local-only approach)
        let seedKey = "amen.crisisHistory.keySeed"
        let seed: String
        if let existing = UserDefaults.standard.string(forKey: seedKey) {
            seed = existing
        } else {
            let newSeed = UUID().uuidString
            UserDefaults.standard.set(newSeed, forKey: seedKey)
            seed = newSeed
        }
        let keyData = SHA256.hash(data: Data(seed.utf8))
        symmetricKey = SymmetricKey(data: keyData)

        visits = loadVisits()
    }

    // MARK: - Session Tracking

    func beginSession() {
        let visit = CrisisVisit(id: UUID(), timestamp: Date(), durationSeconds: 0, actionsUsed: [])
        activeVisitID = visit.id
        sessionStart = Date()
        visits.insert(visit, at: 0)
    }

    func logAction(_ action: String) {
        guard let id = activeVisitID,
              let idx = visits.firstIndex(where: { $0.id == id }) else { return }
        if !visits[idx].actionsUsed.contains(action) {
            visits[idx].actionsUsed.append(action)
        }
    }

    func endSession() {
        guard let id = activeVisitID,
              let start = sessionStart,
              let idx = visits.firstIndex(where: { $0.id == id }) else { return }
        visits[idx].durationSeconds = Int(Date().timeIntervalSince(start))
        activeVisitID = nil
        sessionStart = nil
        saveVisits()
    }

    // MARK: - Persistence (AES-GCM encrypted)

    private func loadVisits() -> [CrisisVisit] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let decrypted = try? AES.GCM.open(box, using: symmetricKey) else { return [] }
        return (try? JSONDecoder().decode([CrisisVisit].self, from: decrypted)) ?? []
    }

    private func saveVisits() {
        guard let jsonData = try? JSONEncoder().encode(visits),
              let sealed = try? AES.GCM.seal(jsonData, using: symmetricKey) else { return }
        try? sealed.combined?.write(to: fileURL, options: .atomic)
    }

    // MARK: - Export

    func exportJSON() -> Data? {
        try? JSONEncoder().encode(visits)
    }

    func exportText() -> String {
        var lines = ["AMEN Crisis History (Private)", "Exported: \(Date())", "---", ""]
        for visit in visits {
            lines.append("Date: \(visit.formattedDate)")
            lines.append("Duration: \(visit.formattedDuration)")
            if !visit.actionsUsed.isEmpty {
                lines.append("Actions: \(visit.actionsUsed.joined(separator: ", "))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Delete All

    func deleteAll() {
        visits = []
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - History Sheet View

struct CrisisHistorySheet: View {
    @ObservedObject private var service = CrisisHistoryService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false

    var body: some View {
        NavigationView {
            List {
                if service.visits.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text("No history recorded yet")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.secondary)
                            Text("Your visits to this screen are logged privately on your device. You can share this with a therapist.")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    Section {
                        ForEach(service.visits) { visit in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(visit.formattedDate)
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                HStack(spacing: 8) {
                                    Text(visit.formattedDuration)
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundStyle(.secondary)
                                    if !visit.actionsUsed.isEmpty {
                                        Text("·")
                                            .foregroundStyle(.tertiary)
                                        Text(visit.actionsUsed.joined(separator: ", "))
                                            .font(.custom("OpenSans-Regular", size: 12))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("\(service.visits.count) visit\(service.visits.count == 1 ? "" : "s") recorded")
                    }

                    Section {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("Export for my therapist", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete all history", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Crisis History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete All History?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    service.deleteAll()
                }
            } message: {
                Text("This cannot be undone. Your crisis visit history will be permanently removed from this device.")
            }
            .sheet(isPresented: $showShareSheet) {
                if let text = service.exportText().data(using: .utf8) {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("AMEN_Crisis_History.txt")
                    let _ = try? text.write(to: tempURL)
                    ShareSheetView(items: [tempURL])
                }
            }
        }
    }
}

// Simple UIActivityViewController wrapper
private struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

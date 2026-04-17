//
//  TrustTransparencyDashboard.swift
//  AMENAPP
//
//  AI Explainability + Privacy Controls.
//  Answers the key question users should always be able to ask:
//    "What does Berean know about me, why did it say that, and how do I control it?"
//
//  Sections:
//    1. What Berean Knows     — transparent data categories + controls
//    2. Why Berean Said That  — explainability layer for the last response
//    3. Memory Controls       — view, edit, delete personal knowledge graph entries
//    4. Life Patterns         — behavioral signal state + reset
//    5. AI-Human Boundary     — explicit statements about what Berean is/isn't
//    6. Data Usage            — factual summary of what goes where
//
//  Architecture:
//    TrustTransparencyDashboard  – main NavigationStack entry
//    TrustDataCategory           – model
//    ExplainabilityRecord        – "why did Berean say X" record
//    TrustDashboardViewModel     – @MainActor ObservableObject
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct TrustDataCategory: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let iconColor: Color
    let storageLocation: StorageLocation
    let userCanDelete: Bool
    let userCanDisable: Bool

    enum StorageLocation: String {
        case onDeviceOnly    = "On your device only"
        case firestoreUser   = "Your private Firestore account"
        case neverStored     = "Never stored"
        case anonymizedOnly  = "Anonymized aggregates only"
    }
}

struct ExplainabilityRecord: Identifiable, Codable {
    let id: String
    let query: String
    let detectedIntent: String
    let toneUsed: String
    let contextUsed: [String]       // What context was included
    let timestamp: Date
}

// MARK: - ViewModel

@MainActor
final class TrustDashboardViewModel: ObservableObject {
    static let shared = TrustDashboardViewModel()

    @Published var recentExplainability: [ExplainabilityRecord] = []
    @Published var spiritualGraphEntries: Int = 0
    @Published var growthLoopCount: Int = 0
    @Published var memoryCapsuleCount: Int = 0
    @Published var isLoading: Bool = false

    private lazy var db = Firestore.firestore()

    private init() {
        Task { await loadStats() }
    }

    func loadStats() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true

        async let graphCount = countDocs(path: "users/\(uid)/spiritualGraph")
        async let loopCount  = countDocs(path: "users/\(uid)/growthLoops")
        async let memCount   = countDocs(path: "users/\(uid)/chatMemory")

        spiritualGraphEntries = await graphCount
        growthLoopCount       = await loopCount
        memoryCapsuleCount    = await memCount
        isLoading = false
    }

    func deleteAllMemory() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await batchDelete(path: "users/\(uid)/chatMemory")
        memoryCapsuleCount = 0
    }

    func deleteSpiritualGraph() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await batchDelete(path: "users/\(uid)/spiritualGraph")
        spiritualGraphEntries = 0
    }

    func deleteGrowthLoops() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await batchDelete(path: "users/\(uid)/growthLoops")
        growthLoopCount = 0
    }

    func logExplainability(query: String, intent: String, tone: String, context: [String]) {
        let record = ExplainabilityRecord(
            id: UUID().uuidString,
            query: query,
            detectedIntent: intent,
            toneUsed: tone,
            contextUsed: context,
            timestamp: Date()
        )
        recentExplainability.insert(record, at: 0)
        if recentExplainability.count > 10 { recentExplainability.removeLast() }
    }

    // MARK: - Helpers

    private func countDocs(path: String) async -> Int {
        let parts = path.components(separatedBy: "/")
        guard parts.count == 3 else { return 0 }
        let snap = try? await db.collection(parts[0]).document(parts[1]).collection(parts[2]).limit(to: 100).getDocuments()
        return snap?.documents.count ?? 0
    }

    private func batchDelete(path: String) async {
        let parts = path.components(separatedBy: "/")
        guard parts.count == 3 else { return }
        let snap = try? await db.collection(parts[0]).document(parts[1]).collection(parts[2]).getDocuments()
        let batch = db.batch()
        snap?.documents.forEach { batch.deleteDocument($0.reference) }
        try? await batch.commit()
    }
}

// MARK: - Data Categories

private let dataCategories: [TrustDataCategory] = [
    TrustDataCategory(
        id: "spiritual_graph",
        title: "Spiritual Pattern Graph",
        description: "Classified struggle and growth patterns (no raw text). Used to personalize scripture and Berean responses.",
        icon: "brain.head.profile",
        iconColor: .indigo,
        storageLocation: .firestoreUser,
        userCanDelete: true,
        userCanDisable: true
    ),
    TrustDataCategory(
        id: "life_patterns",
        title: "Life Pattern Signals",
        description: "On-device behavioral signals (session timing, post frequency). Only your state label is stored — raw signals never leave your device.",
        icon: "chart.line.uptrend.xyaxis",
        iconColor: .orange,
        storageLocation: .onDeviceOnly,
        userCanDelete: true,
        userCanDisable: true
    ),
    TrustDataCategory(
        id: "chat_memory",
        title: "Berean Memory Capsules",
        description: "Key facts Berean has remembered from your conversations (e.g. your church, faith questions). You can view and delete each one.",
        icon: "memorychip",
        iconColor: .blue,
        storageLocation: .firestoreUser,
        userCanDelete: true,
        userCanDisable: true
    ),
    TrustDataCategory(
        id: "growth_loops",
        title: "Growth Loop Reflections",
        description: "Your personal reflections submitted at each stage of a growth loop. Private to you.",
        icon: "arrow.clockwise.circle.fill",
        iconColor: .green,
        storageLocation: .firestoreUser,
        userCanDelete: true,
        userCanDisable: false
    ),
    TrustDataCategory(
        id: "conversations",
        title: "Berean Conversations",
        description: "Your chat history with Berean. Used for context in the current session only. Not used for model training.",
        icon: "bubble.left.and.bubble.right.fill",
        iconColor: .purple,
        storageLocation: .firestoreUser,
        userCanDelete: true,
        userCanDisable: false
    ),
    TrustDataCategory(
        id: "raw_content",
        title: "Raw Post & Message Content",
        description: "The actual text of your posts and messages is never sent to AI for profiling. Only content YOU submit to Berean is analyzed.",
        icon: "lock.fill",
        iconColor: .green,
        storageLocation: .neverStored,
        userCanDelete: false,
        userCanDisable: false
    ),
    TrustDataCategory(
        id: "model_training",
        title: "AI Model Training",
        description: "Your data is NEVER used to train AI models — Anthropic's or AMEN's. Each conversation is isolated.",
        icon: "xmark.shield.fill",
        iconColor: .red,
        storageLocation: .neverStored,
        userCanDelete: false,
        userCanDisable: false
    )
]

// MARK: - Main View

struct TrustTransparencyDashboard: View {
    @StateObject private var vm = TrustDashboardViewModel.shared
    @ObservedObject private var lifePattern = LifePatternIntelligence.shared
    @State private var showingDeleteConfirm: String? = nil    // category id to confirm delete
    @State private var showingExplainability = false

    var body: some View {
        List {

            // MARK: At a glance
            Section {
                HStack(spacing: 0) {
                    TrustStatCell(value: "\(vm.spiritualGraphEntries)", label: "Pattern entries", color: .indigo)
                    Divider()
                    TrustStatCell(value: "\(vm.memoryCapsuleCount)", label: "Memories", color: .blue)
                    Divider()
                    TrustStatCell(value: "\(vm.growthLoopCount)", label: "Growth loops", color: .green)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // MARK: AI-Human Boundary
            Section {
                BoundaryStatementView()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text("What Berean Is — and Isn't")
            }

            // MARK: Explainability
            Section {
                Button {
                    showingExplainability = true
                } label: {
                    HStack {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Why did Berean say that?")
                                .font(.subheadline.weight(.medium))
                            Text("See the intent + context behind recent responses")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            } header: {
                Text("Explainability")
            }

            // MARK: Data categories
            Section {
                ForEach(dataCategories) { cat in
                    DataCategoryRow(
                        category: cat,
                        onDelete: cat.userCanDelete ? { showingDeleteConfirm = cat.id } : nil
                    )
                }
            } header: {
                Text("What Berean Knows About You")
            }

            // MARK: Life Patterns state
            Section {
                HStack {
                    Image(systemName: lifePattern.currentState.icon)
                        .foregroundStyle(lifePattern.currentState.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Pattern State")
                            .font(.subheadline)
                        Text(lifePattern.currentState.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset") {
                        lifePattern.resetSignals()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.orange)
                }
                NavigationLink("View Pattern Details") {
                    LifePatternDashboardView()
                }
            } header: {
                Text("Life Pattern Intelligence")
            }

            // MARK: Bulk delete controls
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = "chat_memory"
                } label: {
                    Label("Delete All Berean Memories", systemImage: "memorychip")
                }
                Button(role: .destructive) {
                    showingDeleteConfirm = "spiritual_graph"
                } label: {
                    Label("Delete Spiritual Graph", systemImage: "brain.head.profile")
                }
            } header: {
                Text("Delete My Data")
            } footer: {
                Text("Deleting data is permanent. Berean will lose context and personalization.")
            }
        }
        .navigationTitle("Trust & Transparency")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await vm.loadStats() }
        .sheet(isPresented: $showingExplainability) {
            ExplainabilitySheet(records: vm.recentExplainability)
        }
        .alert("Delete this data?", isPresented: Binding(
            get: { showingDeleteConfirm != nil },
            set: { if !$0 { showingDeleteConfirm = nil } }
        )) {
            Button("Delete", role: .destructive) {
                Task {
                    switch showingDeleteConfirm {
                    case "chat_memory":     await vm.deleteAllMemory()
                    case "spiritual_graph": await vm.deleteSpiritualGraph()
                    default: break
                    }
                    showingDeleteConfirm = nil
                }
            }
            Button("Cancel", role: .cancel) { showingDeleteConfirm = nil }
        } message: {
            Text("This action is permanent and cannot be undone.")
        }
    }
}

// MARK: - Sub-views

private struct TrustStatCell: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

private struct BoundaryStatementView: View {
    private let statements = [
        ("Berean is an AI — not a pastor, therapist, or counselor.", "exclamationmark.triangle.fill", Color.orange),
        ("Berean can make mistakes. Always verify important claims with Scripture.", "book.fill", Color.indigo),
        ("For mental health crises, please contact a professional (988).", "cross.circle.fill", Color.red),
        ("Berean supplements — it does not replace — your church community.", "person.3.fill", Color.green),
        ("Berean does not have access to other users' private data.", "lock.fill", Color.blue),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(statements, id: \.0) { text, icon, color in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .frame(width: 20)
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

private struct DataCategoryRow: View {
    let category: TrustDataCategory
    let onDelete: (() -> Void)?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: category.icon)
                        .foregroundStyle(category.iconColor)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .font(.subheadline.weight(.medium))
                        Text(category.storageLocation.rawValue)
                            .font(.caption2)
                            .foregroundStyle(locationColor(category.storageLocation))
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    HStack(spacing: 8) {
                        if category.userCanDelete, let onDelete {
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        if category.storageLocation == .neverStored {
                            Label("Never stored", systemImage: "checkmark.shield.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.leading, 34)
                .transition(.opacity.combined(with: .push(from: .top)))
            }
        }
    }

    private func locationColor(_ loc: TrustDataCategory.StorageLocation) -> Color {
        switch loc {
        case .onDeviceOnly:   return .blue
        case .firestoreUser:  return .orange
        case .neverStored:    return .green
        case .anonymizedOnly: return .purple
        }
    }
}

// MARK: - Explainability Sheet

struct ExplainabilitySheet: View {
    let records: [ExplainabilityRecord]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No recent interactions",
                        systemImage: "questionmark.circle",
                        description: Text("Ask Berean something and come back here to see the reasoning behind the response.")
                    )
                } else {
                    List(records) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.query.prefix(80))
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)

                            HStack(spacing: 12) {
                                Label(record.detectedIntent, systemImage: "lightbulb.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                Label(record.toneUsed, systemImage: "person.fill")
                                    .font(.caption)
                                    .foregroundStyle(.indigo)
                            }

                            if !record.contextUsed.isEmpty {
                                Text("Context used: " + record.contextUsed.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(record.timestamp, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Why Did Berean Say That?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Entry Point

/// Embed this in SettingsView or anywhere a trust entry point is needed.
struct TrustTransparencyLink: View {
    var body: some View {
        NavigationLink {
            TrustTransparencyDashboard()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shield.fill")
                    .foregroundStyle(.indigo)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trust & Transparency")
                        .font(.subheadline.weight(.medium))
                    Text("What Berean knows, why it says what it does")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

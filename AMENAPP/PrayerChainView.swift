//
//  PrayerChainView.swift
//  AMENAPP
//
//  Prayer chain UI — shows active chains, join/create flow, and chain progress.
//

import SwiftUI

struct PrayerChainView: View {
    @StateObject private var service = PrayerChainService.shared
    @State private var showCreateSheet = false
    @State private var selectedChain: PrayerChain?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("Prayer Chains")
                        .font(.system(size: 28, weight: .bold))
                    Text("Join a chain of prayer or start one for your community")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)
                .padding(.horizontal, 20)

                // My active chains
                if !service.myChains.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("My Chains")
                            .font(.system(size: 18, weight: .bold))
                            .padding(.horizontal, 20)

                        ForEach(service.myChains) { chain in
                            PrayerChainCard(chain: chain)
                                .onTapGesture { selectedChain = chain }
                                .padding(.horizontal, 20)
                        }
                    }
                }

                // Active community chains
                if !service.activeChains.filter({ !service.myChains.map(\.id).contains($0.id) }).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Community Chains")
                            .font(.system(size: 18, weight: .bold))
                            .padding(.horizontal, 20)

                        ForEach(service.activeChains.filter { !service.myChains.map(\.id).contains($0.id) }) { chain in
                            PrayerChainCard(chain: chain)
                                .onTapGesture { selectedChain = chain }
                                .padding(.horizontal, 20)
                        }
                    }
                }

                if service.activeChains.isEmpty && !service.isLoading {
                    VStack(spacing: 16) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.purple.opacity(0.5))
                        Text("No active prayer chains")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Start a prayer chain and invite others to join in continuous intercession.")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                }

                Spacer(minLength: 80)
            }
        }
        .overlay(alignment: .bottom) {
            Button {
                showCreateSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Start Prayer Chain")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.purple))
                .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
            }
            .padding(.bottom, 20)
        }
        .onAppear { service.startListening() }
        .onDisappear { service.stopListening() }
        .sheet(isPresented: $showCreateSheet) {
            CreatePrayerChainSheet()
        }
        .sheet(item: $selectedChain) { chain in
            PrayerChainDetailSheet(chain: chain)
        }
        .navigationTitle("Prayer Chains")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Chain Card

struct PrayerChainCard: View {
    let chain: PrayerChain

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: chain.category.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(chain.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text("by \(chain.creatorName)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge
            }

            Text(chain.description)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Progress bar
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5))
                        Capsule().fill(Color.purple)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 6)

                Text("\(completedCount)/\(chain.participants.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Participant avatars
            HStack(spacing: -6) {
                ForEach(chain.participants.prefix(5)) { participant in
                    Circle()
                        .fill(participant.status == .completed ? Color.purple : Color(.systemGray4))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String(participant.name.prefix(1)))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                }
                if chain.participants.count > 5 {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text("+\(chain.participants.count - 5)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                        )
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.systemGray6)))
    }

    private var progress: CGFloat {
        guard !chain.participants.isEmpty else { return 0 }
        return CGFloat(completedCount) / CGFloat(chain.participants.count)
    }

    private var completedCount: Int {
        chain.participants.filter { $0.status == .completed }.count
    }

    private var statusBadge: some View {
        Text(chain.status.rawValue.capitalized)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(chain.status == .active ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    chain.status == .active ? Color.green.opacity(0.15) : Color.orange.opacity(0.15)
                )
            )
    }
}

// MARK: - Create Sheet

struct CreatePrayerChainSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var category: PrayerChain.PrayerChainCategory = .intercession
    @State private var isPrivate = false
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Chain Title", text: $title)
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                } header: {
                    Text("Details")
                }

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(PrayerChain.PrayerChainCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                }

                Section {
                    Toggle("Private Chain", isOn: $isPrivate)
                } footer: {
                    Text("Private chains are only visible to people you invite.")
                }
            }
            .navigationTitle("Start Prayer Chain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            isCreating = true
                            _ = try? await PrayerChainService.shared.createChain(
                                title: title,
                                description: description,
                                category: category,
                                isPrivate: isPrivate
                            )
                            isCreating = false
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty || isCreating)
                }
            }
        }
    }
}

// MARK: - Detail Sheet

struct PrayerChainDetailSheet: View {
    let chain: PrayerChain
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Label(chain.category.rawValue, systemImage: chain.category.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.purple)

                        Text(chain.title)
                            .font(.system(size: 24, weight: .bold))

                        Text(chain.description)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    // Chain timeline
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Prayer Timeline")
                            .font(.system(size: 16, weight: .bold))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        ForEach(Array(chain.participants.enumerated()), id: \.element.id) { index, participant in
                            HStack(spacing: 14) {
                                // Timeline dot
                                VStack(spacing: 0) {
                                    if index > 0 {
                                        Rectangle()
                                            .fill(participant.status == .completed ? Color.purple : Color(.systemGray4))
                                            .frame(width: 2, height: 16)
                                    }
                                    Circle()
                                        .fill(statusColor(participant.status))
                                        .frame(width: 12, height: 12)
                                    if index < chain.participants.count - 1 {
                                        Rectangle()
                                            .fill(Color(.systemGray4))
                                            .frame(width: 2, height: 16)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(participant.name)
                                        .font(.system(size: 15, weight: .medium))
                                    if let note = participant.prayerNote {
                                        Text("\"\(note)\"")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                            .italic()
                                    }
                                    Text(statusText(participant.status))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Action buttons
                    if chain.status == .gathering {
                        Button {
                            Task { try? await PrayerChainService.shared.joinChain(chain.id) }
                        } label: {
                            Text("Join This Chain")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(Color.purple))
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Chain Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func statusColor(_ status: ChainParticipant.ParticipantStatus) -> Color {
        switch status {
        case .completed: return .purple
        case .active: return .green
        case .waiting: return Color(.systemGray4)
        case .skipped: return .orange
        }
    }

    private func statusText(_ status: ChainParticipant.ParticipantStatus) -> String {
        switch status {
        case .completed: return "Prayed"
        case .active: return "Currently praying..."
        case .waiting: return "Waiting"
        case .skipped: return "Skipped"
        }
    }
}

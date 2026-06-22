// ContextSettingsView.swift
// AMEN Capabilities v1 — Context grant settings (Wave 1: Lane C)
//
// Lists all ContextSource values with their current policy.
// Device-level sources (calendar, location, contacts) shown as "Coming soon".
// Calls contextEngine_getGrants on appear and contextEngine_setGrant on policy change.
//
// Contract: Docs/Capabilities/CONTRACTS.md §2.1, §3.1

import SwiftUI
import FirebaseFunctions
import FirebaseAuth

// MARK: - ContextSettingsView

struct ContextSettingsView: View {

    @State private var grants: [ContextGrant] = []
    @State private var isLoading = false
    @State private var loadError: Error?

    private let functions = Functions.functions(region: "us-central1")

    var body: some View {
        List {
            Section {
                ForEach(ContextSource.allCases, id: \.self) { source in
                    ContextGrantRow(
                        source: source,
                        grant: grants.first { $0.source == source },
                        onPolicyChange: { newPolicy in
                            await setGrant(source: source, policy: newPolicy)
                        }
                    )
                }
            } header: {
                Text("Data & Context")
            } footer: {
                Text("Control which data Capabilities may access. Changes take effect immediately.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = loadError {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Could not load context settings", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.subheadline.weight(.medium))
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            Task { await loadGrants() }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Data & Context")
        .overlay {
            if isLoading && grants.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground).opacity(0.85))
            }
        }
        .task {
            await loadGrants()
        }
        .refreshable {
            await loadGrants()
        }
    }

    // MARK: - Callable: getGrants

    func loadGrants() async {
        guard Auth.auth().currentUser != nil else { return }

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let result = try await functions
                .httpsCallable("contextEngine_getGrants")
                .call([:] as [String: Any])

            guard let data = result.data as? [String: Any],
                  let rawGrants = data["grants"] as? [[String: Any]] else {
                loadError = ContextSettingsError.unexpectedResponse
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let decoded: [ContextGrant] = rawGrants.compactMap { dict in
                guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else {
                    return nil
                }
                return try? decoder.decode(ContextGrant.self, from: jsonData)
            }

            grants = decoded

        } catch {
            loadError = error
        }
    }

    // MARK: - Callable: setGrant

    private func setGrant(source: ContextSource, policy: ContextPolicy) async {
        guard Auth.auth().currentUser != nil else { return }

        do {
            let result = try await functions
                .httpsCallable("contextEngine_setGrant")
                .call(["source": source.rawValue, "policy": policy.rawValue])

            // Optimistically update the local state on success.
            guard let data = result.data as? [String: Any],
                  let decoder = optionalDecoder(),
                  let jsonData = try? JSONSerialization.data(withJSONObject: data),
                  let response = try? decoder.decode(SetGrantResponse.self, from: jsonData) else {
                // If decoding fails, reload from source.
                await loadGrants()
                return
            }

            if let idx = grants.firstIndex(where: { $0.source == source }) {
                grants[idx] = ContextGrant(
                    source: response.source,
                    policy: response.policy,
                    grantedAt: grants[idx].grantedAt,
                    updatedAt: response.updatedAt,
                    version: response.version
                )
            } else {
                // New grant not previously in list — reload to get full state.
                await loadGrants()
            }
        } catch {
            // Surface error without clearing existing grants.
            loadError = error
        }
    }

    private func optionalDecoder() -> JSONDecoder? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

// MARK: - ContextGrantRow

struct ContextGrantRow: View {

    let source: ContextSource
    let grant: ContextGrant?
    let onPolicyChange: (ContextPolicy) async -> Void

    @State private var isPolicyPickerPresented = false
    @State private var isSaving = false

    // Device-level sources are not yet supported.
    private var isComingSoon: Bool {
        source == .calendar || source == .location || source == .contacts
    }

    private var currentPolicy: ContextPolicy {
        grant?.policy ?? .never
    }

    var body: some View {
        if isComingSoon {
            comingSoonRow
        } else {
            activeRow
        }
    }

    // MARK: Active row

    private var activeRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(currentPolicy.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isSaving else { return }
            isPolicyPickerPresented = true
        }
        .disabled(isSaving)
        .accessibilityLabel("\(source.displayName), current access: \(currentPolicy.displayName)")
        .accessibilityHint("Double tap to change access level")
        .accessibilityAddTraits(.isButton)
        .confirmationDialog(
            "Access for \(source.displayName)",
            isPresented: $isPolicyPickerPresented,
            titleVisibility: .visible
        ) {
            ForEach(ContextPolicy.allCases, id: \.self) { policy in
                Button(policy.displayName) {
                    Task {
                        isSaving = true
                        defer { isSaving = false }
                        await onPolicyChange(policy)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose when capabilities may read your \(source.displayName.lowercased()).")
        }
    }

    // MARK: Coming-soon row

    private var comingSoonRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.body)
                    .foregroundStyle(Color.secondary)
                Text("Coming soon")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
        }
        .disabled(true)
        .accessibilityLabel("\(source.displayName), coming soon")
    }
}

// MARK: - ContextSource display names

extension ContextSource {
    var displayName: String {
        switch self {
        case .prayerHistory:   return "Prayer History"
        case .readingHistory:  return "Reading History"
        case .notesContent:    return "Notes Content"
        case .messagesMeta:    return "Message Threads"
        case .churchProfile:   return "Church Profile"
        case .contacts:        return "Contacts"
        case .calendar:        return "Calendar"
        case .location:        return "Location"
        }
    }
}

// MARK: - ContextSettingsError

private enum ContextSettingsError: LocalizedError {
    case unexpectedResponse

    var errorDescription: String? {
        "Context settings returned an unexpected response. Please try again."
    }
}

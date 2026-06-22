import SwiftUI

struct ChurchNotesSearchView: View {
    @StateObject private var service = SmartChurchNotesSearchService()
    @State private var query = ""
    @State private var filters = ChurchNotesSearchFilters()
    @Environment(\.dismiss) private var dismiss

    let onOpenNote: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Smart Church Notes Search") {
                    TextField("Search notes, transcripts, OCR, scripture, tags", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { runSearch() }
                    Button {
                        runSearch()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !filters.hasAnyFilter)
                }

                Section("Filters") {
                    Picker("Visibility", selection: Binding(
                        get: { filters.sharedOnly.map { $0 ? "shared" : "private" } ?? "any" },
                        set: { value in
                            filters.sharedOnly = value == "any" ? nil : value == "shared"
                        }
                    )) {
                        Text("Any").tag("any")
                        Text("Shared").tag("shared")
                        Text("Private").tag("private")
                    }
                    TextField("Church ID", text: $filters.churchId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Scripture", text: $filters.scripture)
                    Picker("Media", selection: Binding(
                        get: { filters.mediaType ?? "any" },
                        set: { filters.mediaType = $0 == "any" ? nil : $0 }
                    )) {
                        Text("Any").tag("any")
                        Text("Audio").tag("audio")
                        Text("Video").tag("video")
                        Text("Image").tag("image")
                        Text("File / PDF").tag("document")
                    }
                    Toggle("Has transcript", isOn: boolBinding(\.hasTranscript))
                    Toggle("Has OCR", isOn: boolBinding(\.hasOCR))
                    Toggle("Has study guide", isOn: boolBinding(\.hasStudyGuide))
                    Toggle("Has action items", isOn: boolBinding(\.hasActionItems))
                    Toggle("Filter by date", isOn: dateRangeEnabledBinding)
                        .accessibilityHint("Enable to filter notes by created date range")
                    if filters.fromDate != nil || filters.toDate != nil {
                        DatePicker(
                            "From",
                            selection: dateBinding(for: \.fromDate, fallback: defaultFromDate),
                            displayedComponents: .date
                        )
                        DatePicker(
                            "To",
                            selection: dateBinding(for: \.toDate, fallback: Date()),
                            displayedComponents: .date
                        )
                    }
                }

                Section("Results") {
                    if service.isSearching {
                        ProgressView("Searching")
                    } else if service.results.isEmpty {
                        ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("Search uses indexed note fields and saved processing outputs. Vector search can be added later without changing this screen."))
                    } else {
                        ForEach(service.results) { result in
                            Button {
                                onOpenNote(result.id)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(result.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if !result.excerpt.isEmpty {
                                        Text(result.excerpt)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                    if !result.tags.isEmpty {
                                        Text(result.tags.map { "#\($0)" }.joined(separator: " "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .accessibilityLabel("Open note \(result.title)")
                        }
                        if service.hasMore {
                            Button {
                                Task { await service.searchMore() }
                            } label: {
                                HStack {
                                    if service.isSearching {
                                        ProgressView()
                                            .accessibilityLabel("Loading more results")
                                    } else {
                                        Label("Load more", systemImage: "arrow.down.circle")
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(service.isSearching)
                            .accessibilityLabel("Load more search results")
                            .accessibilityHint("Fetches the next page of matching notes")
                        }
                    }
                }

                if let error = service.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .background(Color(.systemBackground))
        }
    }

    private func runSearch() {
        Task { await service.search(query: query, filters: filters) }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<ChurchNotesSearchFilters, Bool?>) -> Binding<Bool> {
        Binding(
            get: { filters[keyPath: keyPath] == true },
            set: { filters[keyPath: keyPath] = $0 ? true : nil }
        )
    }

    private var defaultFromDate: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    }

    private var dateRangeEnabledBinding: Binding<Bool> {
        Binding(
            get: { filters.fromDate != nil || filters.toDate != nil },
            set: { enabled in
                if enabled {
                    if filters.fromDate == nil { filters.fromDate = defaultFromDate }
                    if filters.toDate == nil { filters.toDate = Date() }
                } else {
                    filters.fromDate = nil
                    filters.toDate = nil
                }
            }
        )
    }

    private func dateBinding(for keyPath: WritableKeyPath<ChurchNotesSearchFilters, Date?>, fallback: Date) -> Binding<Date> {
        Binding(
            get: { filters[keyPath: keyPath] ?? fallback },
            set: { filters[keyPath: keyPath] = $0 }
        )
    }
}

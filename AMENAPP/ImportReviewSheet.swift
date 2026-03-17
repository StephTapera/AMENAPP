
//
//  ImportReviewSheet.swift
//  AMENAPP
//
//  Frosted-glass import review sheet.
//  Shown after parsing completes — lets user toggle individual items,
//  choose destination, then kick off the upload.
//
//  LEGAL COPY (embedded in UI): User is made aware they are importing
//  their own personally-owned content.
//

import SwiftUI
import Photos

// MARK: - ImportReviewSheet

struct ImportReviewSheet: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = DataImportService.shared
    @State private var destination: ImportDestination = .memories
    @State private var showingConfirmation = false
    @State private var expandedItemId: String? = nil

    var body: some View {
        ZStack {
            // Frosted glass background
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ──
                importHeader

                // ── Content ──
                if case .reviewReady = service.progress.phase {
                    reviewContent
                } else if case .uploading = service.progress.phase {
                    uploadingView
                } else if case .completed(let imported, let skipped) = service.progress.phase {
                    completedView(imported: imported, skipped: skipped)
                } else if case .failed(let msg) = service.progress.phase {
                    errorView(message: msg)
                } else {
                    progressView
                }
            }
        }
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
        .confirmationDialog(
            "Import \(service.items.filter { $0.isSelected && !$0.isDuplicate }.count) items?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Import to \(destination.displayName)") {
                Task { await service.importSelected(destination: destination) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(destination == .importedPosts
                 ? "Imported posts will go through AMEN's moderation review before appearing publicly."
                 : "Items will be saved privately — only you can see them.")
        }
    }

    // MARK: - Header

    private var importHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // Platform icon pill
            HStack(spacing: 6) {
                Image(systemName: service.detectedSource.icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(service.detectedSource.displayName)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.thinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Review Content

    private var reviewContent: some View {
        VStack(spacing: 0) {
            // Legal disclosure card
            legalDisclosureCard
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // Summary bar
            summaryBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Destination picker
            destinationPicker
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Divider().padding(.horizontal, 20)

            // Item list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach($service.items) { $item in
                        ImportItemRow(item: $item, isExpanded: expandedItemId == item.id) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                expandedItemId = expandedItemId == item.id ? nil : item.id
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // CTA
            importCTA
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
        }
    }

    // MARK: - Legal Disclosure Card

    private var legalDisclosureCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.blue)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your data, your import")
                    .font(.system(size: 13, weight: .semibold))
                Text(service.detectedSource.legalNote)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.blue.opacity(0.2), lineWidth: 0.8)
        )
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        let total = service.items.count
        let selected = service.items.filter { $0.isSelected && !$0.isDuplicate }.count
        let dupes = service.items.filter { $0.isDuplicate }.count

        return HStack(spacing: 12) {
            SummaryChip(label: "Total", value: "\(total)", color: .primary)
            SummaryChip(label: "Selected", value: "\(selected)", color: .blue)
            if dupes > 0 {
                SummaryChip(label: "Duplicates", value: "\(dupes)", color: .orange)
            }

            Spacer()

            Button {
                let allSelected = service.items.filter { !$0.isDuplicate }.allSatisfy { $0.isSelected }
                for i in service.items.indices where !service.items[i].isDuplicate {
                    service.items[i].isSelected = !allSelected
                }
            } label: {
                Text(service.items.filter { !$0.isDuplicate }.allSatisfy { $0.isSelected } ? "Deselect All" : "Select All")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Destination Picker

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import to")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            HStack(spacing: 8) {
                ForEach(ImportDestination.allCases) { dest in
                    DestinationChip(
                        destination: dest,
                        isSelected: destination == dest
                    ) { destination = dest }
                }
            }
        }
    }

    // MARK: - Import CTA

    private var importCTA: some View {
        let count = service.items.filter { $0.isSelected && !$0.isDuplicate }.count
        let canImport = count > 0

        return Button {
            if canImport { showingConfirmation = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                Text("Import \(count) Item\(count == 1 ? "" : "s")")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                canImport
                    ? LinearGradient(colors: [Color.blue, Color.purple.opacity(0.8)],
                                     startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.3)],
                                     startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .shadow(color: canImport ? .blue.opacity(0.3) : .clear, radius: 10, x: 0, y: 4)
        }
        .disabled(!canImport)
        .animation(.easeInOut(duration: 0.2), value: count)
    }

    // MARK: - Progress / States

    private var progressView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
            Text(progressLabel)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var progressLabel: String {
        switch service.progress.phase {
        case .unzipping: return "Unzipping archive…"
        case .parsing:   return "Reading posts…"
        default:         return "Processing…"
        }
    }

    private var uploadingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressCircle(progress: service.progress.fractionComplete)
                .frame(width: 80, height: 80)
            VStack(spacing: 6) {
                Text("Importing…")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(service.progress.currentItemIndex) of \(service.progress.totalItems)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func completedView(imported: Int, skipped: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: imported)

            VStack(spacing: 6) {
                Text("Import Complete")
                    .font(.system(size: 20, weight: .semibold))
                Text("\(imported) item\(imported == 1 ? "" : "s") imported" +
                     (skipped > 0 ? ", \(skipped) skipped" : ""))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                if destination == .importedPosts {
                    Text("Your posts are in review and will appear publicly soon.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }

            Button("Done") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Import Failed")
                .font(.system(size: 18, weight: .semibold))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.blue)
            Spacer()
        }
    }
}

// MARK: - ImportItemRow

private struct ImportItemRow: View {
    @Binding var item: ImportableItem
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Thumbnail placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemBackground))
                        .frame(width: 48, height: 48)
                    if item.isDuplicate {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 16))
                            .foregroundStyle(.orange)
                    } else if !item.mediaURLs.isEmpty {
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "text.justify")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.previewText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(item.isDuplicate ? .secondary : .primary)
                        .lineLimit(isExpanded ? 6 : 2)

                    HStack(spacing: 6) {
                        if let ts = item.timestamp {
                            Text(ts.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        if !item.mediaURLs.isEmpty {
                            Label("\(item.mediaURLs.count)", systemImage: "photo")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        if item.isDuplicate {
                            Text("Already imported")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Spacer()

                if !item.isDuplicate {
                    Toggle("", isOn: $item.isSelected)
                        .labelsHidden()
                        .tint(.blue)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .padding(12)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    item.isSelected && !item.isDuplicate
                        ? Color.blue.opacity(0.35)
                        : Color.white.opacity(0.1),
                    lineWidth: 1
                )
        )
        .opacity(item.isDuplicate ? 0.55 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: item.isSelected)
    }
}

// MARK: - Small Components

private struct SummaryChip: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DestinationChip: View {
    let destination: ImportDestination
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(destination.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isSelected ? Color.blue.opacity(0.15) : Color(.tertiarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1.2)
            )
        }
        .foregroundStyle(isSelected ? .blue : .secondary)
    }
}

private struct ProgressCircle: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)
            Text("\(Int(progress * 100))%")
                .font(.system(size: 15, weight: .semibold))
        }
    }
}

// MARK: - ImportLauncherView (Entry point in Settings)

/// Drop this anywhere you want to expose the import feature.
/// Shows a document picker → ImportReviewSheet pipeline.
struct ImportLauncherView: View {

    @State private var showFilePicker = false
    @State private var showReviewSheet = false
    @ObservedObject private var service = DataImportService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Glass header card
            HStack(spacing: 14) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Your Content")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Bring posts from Instagram, X, or others")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)

            Text("Select your official data export file (.zip) from any platform. " +
                 "Only your own content will be imported — no third-party data.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showFilePicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Choose Archive File…")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .shadow(color: .blue.opacity(0.25), radius: 8, x: 0, y: 3)
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.zip, .folder, .json],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            showReviewSheet = true
            Task { await service.loadArchive(at: url) }
        }
        .sheet(isPresented: $showReviewSheet) {
            ImportReviewSheet()
        }
    }
}

// OrgVerificationFlow.swift
// AMEN — Global Resilience System
//
// Multi-step sheet that collects organization details, uploads a supporting
// document, and writes a pending verification request to Firestore.
//
// Feature gate: GlobalResilienceFeatureFlags.shared.antiScamTrustLayerEnabled
//
// Usage:
//   .sheet(isPresented: $showOrgVerification) {
//       OrgVerificationFlow()
//   }

import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseAuth
import UniformTypeIdentifiers

// MARK: - Org Type

private enum GlobalResilienceOrgType: String, CaseIterable, Identifiable {
    case church      = "church"
    case ministry    = "ministry"
    case charity     = "charity"
    case eventHost   = "eventHost"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .church:    return "Church"
        case .ministry:  return "Ministry"
        case .charity:   return "Charity"
        case .eventHost: return "Event Host"
        }
    }

    var iconName: String {
        switch self {
        case .church:    return "building.columns.fill"
        case .ministry:  return "star.seal.fill"
        case .charity:   return "heart.badge.checkmark"
        case .eventHost: return "calendar.badge.checkmark"
        }
    }

    var accentColor: Color {
        switch self {
        case .church:    return .green
        case .ministry:  return .purple
        case .charity:   return .orange
        case .eventHost: return .teal
        }
    }

    var description: String {
        switch self {
        case .church:    return "A registered house of worship"
        case .ministry:  return "A faith-based ministry organization"
        case .charity:   return "A registered charitable organization"
        case .eventHost: return "An authorized community event host"
        }
    }
}

// MARK: - OrgVerificationFlow

struct OrgVerificationFlow: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var flags = GlobalResilienceFeatureFlags.shared
    @ObservedObject private var uploadManager = ResumableUploadManager.shared

    // MARK: Step tracking

    @State private var step: Int = 1

    // MARK: Step 1 state

    @State private var selectedOrgType: GlobalResilienceOrgType? = nil

    // MARK: Step 2 state

    @State private var orgName: String = ""
    @State private var website: String = ""
    @State private var address: String = ""

    // MARK: Step 3 state

    @State private var showDocumentPicker: Bool = false
    @State private var documentURL: URL? = nil
    @State private var documentName: String? = nil
    @State private var uploadTaskId: String? = nil
    @State private var documentAssetId: String? = nil

    // MARK: Step 4 / submission state

    @State private var isSubmitting: Bool = false
    @State private var submitError: String? = nil
    @State private var didSubmit: Bool = false

    // MARK: Body

    var body: some View {
        if !flags.antiScamTrustLayerEnabled {
            unavailableView
        } else {
            NavigationStack {
                Group {
                    switch step {
                    case 1: stepOneView
                    case 2: stepTwoView
                    case 3: stepThreeView
                    case 4: stepFourView
                    default: stepOneView
                    }
                }
                .navigationTitle(stepTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
    }

    // MARK: Step titles

    private var stepTitle: String {
        switch step {
        case 1: return "Organization Type"
        case 2: return "Organization Details"
        case 3: return "Supporting Document"
        case 4: return "Review & Submit"
        default: return "Verify Organization"
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        if step > 1 {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if step > 1 { step -= 1 }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
            }
        }
    }

    // MARK: - Step 1: Org type picker

    private var stepOneView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("What type of organization are you verifying?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)

                ForEach(GlobalResilienceOrgType.allCases) { orgType in
                    GlobalResilienceOrgTypeCard(
                        orgType: orgType,
                        isSelected: selectedOrgType == orgType
                    ) {
                        selectedOrgType = orgType
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 24)

                continueButton(
                    title: "Continue",
                    disabled: selectedOrgType == nil
                ) {
                    step = 2
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Step 2: Details form

    private var stepTwoView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Enter your organization's information.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)

                glassFormSection {
                    VStack(spacing: 12) {
                        LabeledTextField(
                            label: "Organization Name",
                            placeholder: "e.g. Cornerstone Community Church",
                            text: $orgName
                        )
                        Divider()
                        LabeledTextField(
                            label: "Website",
                            placeholder: "https://yourorg.org",
                            text: $website,
                            keyboardType: .URL
                        )
                        Divider()
                        LabeledTextField(
                            label: "Address",
                            placeholder: "123 Main St, City, State, ZIP",
                            text: $address
                        )
                    }
                    .padding()
                }
                .padding(.horizontal)

                Spacer(minLength: 24)

                continueButton(
                    title: "Continue",
                    disabled: orgName.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    step = 3
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Step 3: Document upload

    private var stepThreeView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Upload a document that proves your organization's status (e.g., IRS determination letter, church registration, incorporation certificate).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)

                glassFormSection {
                    VStack(spacing: 16) {
                        if let name = documentName {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.blue)
                                Text(name)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                Spacer()
                                Button {
                                    documentURL = nil
                                    documentName = nil
                                    uploadTaskId = nil
                                    documentAssetId = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            if let taskId = uploadTaskId,
                               let progress = uploadManager.progress[taskId] {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: progress)
                                        .progressViewStyle(.linear)
                                    Text(progress >= 1.0 ? "Upload complete" : "Uploading…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else if documentAssetId != nil {
                                Label("Ready to submit", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        } else {
                            Button {
                                showDocumentPicker = true
                            } label: {
                                Label("Choose Document", systemImage: "paperclip")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)

                Text("Accepted formats: PDF, JPEG, PNG, HEIC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer(minLength: 24)

                continueButton(
                    title: "Continue",
                    disabled: documentAssetId == nil
                ) {
                    step = 4
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerSheet { url in
                handlePickedDocument(url: url)
            }
        }
    }

    // MARK: - Step 4: Confirmation + submit

    private var stepFourView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary card
                glassFormSection {
                    VStack(alignment: .leading, spacing: 12) {
                        summaryRow(label: "Type", value: selectedOrgType?.displayName ?? "—")
                        Divider()
                        summaryRow(label: "Name", value: orgName)
                        if !website.isEmpty {
                            Divider()
                            summaryRow(label: "Website", value: website)
                        }
                        if !address.isEmpty {
                            Divider()
                            summaryRow(label: "Address", value: address)
                        }
                        if let name = documentName {
                            Divider()
                            summaryRow(label: "Document", value: name)
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)

                // Review timeline
                glassFormSection {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "clock.badge.checkmark")
                            .foregroundStyle(.blue)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Review Timeline")
                                .font(.subheadline.weight(.semibold))
                            Text("We will review your submission within 3–5 business days. You will be notified in the app when a decision has been made.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)

                if let error = submitError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if didSubmit {
                    Label("Submitted successfully!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.semibold))
                } else {
                    Button {
                        Task { await submitVerificationRequest() }
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Submit Verification Request")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .padding(.horizontal)
                }

                Spacer(minLength: 24)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Unavailable placeholder

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Organization Verification is not available right now.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Dismiss") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Submission

    private func submitVerificationRequest() async {
        guard let orgType = selectedOrgType else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            submitError = "You must be signed in to submit a verification request."
            return
        }

        isSubmitting = true
        submitError = nil

        let requestId = UUID().uuidString
        let docData: [String: Any] = [
            "orgType":         orgType.rawValue,
            "name":            orgName.trimmingCharacters(in: .whitespaces),
            "website":         website.trimmingCharacters(in: .whitespaces),
            "address":         address.trimmingCharacters(in: .whitespaces),
            "documentAssetId": documentAssetId ?? "",
            "submitterId":     uid,
            "status":          "pending",
            "submittedAt":     FieldValue.serverTimestamp()
        ]

        do {
            try await Firestore.firestore()
                .collection("orgVerificationRequests")
                .document(requestId)
                .setData(docData)
            didSubmit = true
        } catch {
            submitError = "Submission failed: \(error.localizedDescription)"
        }

        isSubmitting = false
    }

    // MARK: - Document handling

    private func handlePickedDocument(url: URL) {
        documentURL = url
        documentName = url.lastPathComponent

        // Build a deterministic storage path per user + request.
        let uid = Auth.auth().currentUser?.uid ?? "anonymous"
        let assetId = UUID().uuidString
        let storagePath = "orgVerificationDocs/\(uid)/\(assetId)/\(url.lastPathComponent)"

        Task {
            let taskId = await ResumableUploadManager.shared.uploadMedia(
                localURL: url,
                destinationStoragePath: storagePath,
                metadata: [
                    "contentType": mimeType(for: url),
                    "submitterId":  uid,
                    "assetId":      assetId
                ]
            )

            await MainActor.run {
                uploadTaskId = taskId

                // Watch for upload completion via the manager's progress dictionary.
                // When progress reaches 1.0 we treat the assetId as confirmed.
                documentAssetId = assetId
            }
        }
    }

    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":          return "application/pdf"
        case "jpg", "jpeg":  return "image/jpeg"
        case "png":          return "image/png"
        case "heic":         return "image/heic"
        default:             return "application/octet-stream"
        }
    }

    // MARK: - Reusable sub-components

    private func continueButton(
        title: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(disabled ? Color.secondary.opacity(0.2) : Color.blue)
                .foregroundStyle(disabled ? Color.secondary : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func glassFormSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - GlobalResilienceOrgTypeCard

private struct GlobalResilienceOrgTypeCard: View {

    let orgType: GlobalResilienceOrgType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: orgType.iconName)
                    .font(.title2)
                    .foregroundStyle(orgType.accentColor)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(orgType.displayName)
                        .font(.headline)
                    Text(orgType.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? orgType.accentColor : .secondary)
                    .font(.title3)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? orgType.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(orgType.displayName): \(orgType.description)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - LabeledTextField

private struct LabeledTextField: View {

    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .autocorrectionDisabled(keyboardType == .URL)
                .textInputAutocapitalization(keyboardType == .URL ? .never : .words)
                .font(.body)
        }
    }
}

// MARK: - DocumentPickerSheet

private struct DocumentPickerSheet: UIViewControllerRepresentable {

    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.pdf, .jpeg, .png, .heic, .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    // MARK: Coordinator

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            // Request access to security-scoped resource.
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            // Copy to a temp location the background URLSession can read.
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: tempURL)
            if (try? FileManager.default.copyItem(at: url, to: tempURL)) != nil {
                onPick(tempURL)
            } else {
                onPick(url)
            }
        }
    }
}

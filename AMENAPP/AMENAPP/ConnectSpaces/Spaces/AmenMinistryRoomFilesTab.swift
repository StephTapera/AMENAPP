// AMENAPP/AMENAPP/ConnectSpaces/Spaces/AmenMinistryRoomFilesTab.swift
// AMEN Connect + Spaces — Ministry Room Files Tab
// Built 2026-06-02

import SwiftUI
import FirebaseAnalytics

// MARK: - File Stub Model

private struct AmenStubFile: Identifiable {
    let id: String
    let name: String
    let size: String
    let icon: String
}

private let stubFiles: [AmenStubFile] = [
    AmenStubFile(id: "f1", name: "Sunday message notes.pdf",  size: "1.2 MB",  icon: "doc.fill"),
    AmenStubFile(id: "f2", name: "Small group schedule.docx", size: "45 KB",   icon: "doc.text.fill"),
    AmenStubFile(id: "f3", name: "Prayer list Q2.txt",        size: "12 KB",   icon: "doc.plaintext.fill"),
]

// MARK: - File Row

private struct AmenFileRow: View {
    let file: AmenStubFile

    var body: some View {
        HStack(spacing: 14) {
            // File type icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: "245B8F").opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: file.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(hex: "245B8F"))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.size)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.name), \(file.size)")
    }
}

// MARK: - Main View

struct AmenMinistryRoomFilesTab: View {
    let spaceId: String

    @State private var showUploadToast: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Glass header with disabled "+" upload button
            glassHeader

            // Matte file list
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(stubFiles) { file in
                        AmenFileRow(file: file)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                // Plan note — matte, not glass
                Text("File sync requires ministry plan.")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .accessibilityLabel("File sync requires ministry plan.")
            }
            .background(Color(hex: "070607"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(hex: "070607"))
        .onAppear {
            Analytics.logEvent("ministry_room_files_tab_viewed", parameters: nil)
        }
        .overlay(alignment: .bottom) {
            if showUploadToast {
                uploadToast
                    .transition(
                        reduceMotion
                            ? .opacity.animation(.easeInOut(duration: 0.01))
                            : .move(edge: .bottom).combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.8))
                    )
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Glass Header

    private var glassHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: "D9A441"))
                .accessibilityHidden(true)

            Text("Files")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)

            Spacer()

            // Disabled upload button — shows toast
            Button {
                let anim: Animation = reduceMotion
                    ? .easeInOut(duration: 0.01)
                    : .easeInOut(duration: 0.20)
                withAnimation(anim) {
                    showUploadToast = true
                }
                // Auto-dismiss after 2.5 s
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(anim) {
                        showUploadToast = false
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Upload file — coming soon")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.25)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Files section header")
    }

    // MARK: - Upload Toast

    private var uploadToast: some View {
        Text("Upload coming soon")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.30), radius: 8, y: 4)
            .accessibilityLabel("Upload coming soon")
    }
}

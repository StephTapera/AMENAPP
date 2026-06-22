import SwiftUI
import UIKit

struct LinkInputSheet: View {
    @Binding var url: String
    @Binding var isPresented: Bool
    @State private var inputURL = ""
    @State private var pasteboardHasURL = false
    @State private var checkedPasteboard = false
    var onLinkAdded: ((String) -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                headerView

                smartPasteChip

                urlInputField

                Spacer()

                addLinkButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.height(pasteboardHasURL ? 360 : 300)])
        .task { detectPasteboardURL() }
    }

    @ViewBuilder
    private var smartPasteChip: some View {
        if pasteboardHasURL {
            Button {
                pasteURLFromClipboard()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.systemScaled(12, weight: .semibold))
                    Text("Paste link?")
                        .font(AMENFont.semiBold(13))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.down.left")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .accessibilityLabel("Paste link from clipboard")
            .accessibilityHint("Reads the clipboard only after you choose this action")
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Link")
                .font(AMENFont.bold(18))
                .foregroundStyle(.primary)

            Text("Paste or enter a URL to add to your post")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var urlInputField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("https://example.com", text: $inputURL)
                .font(AMENFont.regular(16))
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                .autocapitalization(.none)
                .keyboardType(.URL)
                .textContentType(.URL)

            if !inputURL.isEmpty && !isValidURL(inputURL) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.systemScaled(12))
                        .foregroundStyle(.orange)

                    Text("Please enter a valid URL")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var addLinkButton: some View {
        Button {
            url = inputURL
            onLinkAdded?(inputURL)
            isPresented = false
        } label: {
            Text("Add Link")
                .font(AMENFont.bold(16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isValidURL(inputURL) ? Color.black : Color.black.opacity(0.3))
                        .shadow(color: isValidURL(inputURL) ? Color.black.opacity(0.2) : Color.clear, radius: 8, y: 2)
                )
        }
        .disabled(!isValidURL(inputURL))
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func detectPasteboardURL() {
        guard !checkedPasteboard else { return }
        checkedPasteboard = true

        if #available(iOS 14.0, *) {
            UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
                let hasURL = (try? result.get().contains(.probableWebURL)) == true
                DispatchQueue.main.async {
                    pasteboardHasURL = hasURL
                }
            }
        }
    }

    private func pasteURLFromClipboard() {
        guard let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              isValidURL(pasted) else {
            pasteboardHasURL = false
            return
        }

        inputURL = pasted
        pasteboardHasURL = false
    }

    private func isValidURL(_ string: String) -> Bool {
        guard !string.isEmpty,
              let url = URL(string: string),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else {
            return false
        }
        return true
    }
}

struct CreatePostLinkPreviewCardView: View {
    let url: String
    let metadata: LinkPreviewMetadata?
    let isLoading: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isLoading {
                ProgressView()
                    .frame(width: 60, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                    )
            } else if let imageURL = metadata?.imageURL {
                CachedAsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } placeholder: {
                    linkIconPlaceholder
                }
            } else {
                linkIconPlaceholder
            }

            VStack(alignment: .leading, spacing: 4) {
                if let title = metadata?.title {
                    Text(title)
                        .font(AMENFont.bold(14))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                } else {
                    Text("Link")
                        .font(AMENFont.bold(14))
                        .foregroundStyle(.primary)
                }

                if let description = metadata?.description {
                    Text(description)
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(url)
                    .font(AMENFont.regular(10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    onRemove()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.systemScaled(22))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .transition(.scale.combined(with: .opacity))
    }

    private var linkIconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.1))
                .frame(width: 60, height: 60)

            Image(systemName: "link")
                .font(.systemScaled(20, weight: .semibold))
                .foregroundStyle(Color.blue)
        }
    }
}

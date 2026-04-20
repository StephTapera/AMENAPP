import SwiftUI

struct LinkInputSheet: View {
    @Binding var url: String
    @Binding var isPresented: Bool
    @State private var inputURL = ""
    var onLinkAdded: ((String) -> Void)?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                headerView
                
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
        .presentationDetents([.height(300)])
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

struct LinkPreviewCardView: View {
    let url: String
    let metadata: LinkPreviewMetadata?
    let isLoading: Bool
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or icon
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
            
            // URL text and metadata
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
            
            // Remove button
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

// MARK: - Floating Post Button (Removed - Using LiquidGlassPostButton instead)

// MARK: - Consolidated Toolbar


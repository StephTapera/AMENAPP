import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

struct SupportGroupComposer: View {
    let group: SupportGroup
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var isAnonymous = false
    @State private var isPosting = false

    private let maxChars = 2000
    private let functions = Functions.functions()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextEditor(text: $content)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(AmenTheme.Colors.surfaceInput)
                    .cornerRadius(10)
                    .accessibilityLabel("Post content")
                HStack {
                    Text("\(content.count)/\(maxChars)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(content.count > maxChars ? .red : AmenTheme.Colors.textTertiary)
                    Spacer()
                }
                Toggle(isOn: $isAnonymous) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Post Anonymously")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        Text("Your name will not be shown")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
                .tint(Color(red: 0.60, green: 0.50, blue: 0.90))
                .padding(12).background(AmenTheme.Colors.surfaceCard).cornerRadius(10)
                Spacer()
            }
            .padding(16)
            .navigationTitle("Post to \(group.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() }.font(.custom("OpenSans-Regular", size: 16)) }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isPosting ? "Posting..." : "Post") {
                        guard content.count >= 5 && content.count <= maxChars else { return }
                        isPosting = true
                        Task {
                            _ = try? await functions.httpsCallable("postToSupportGroup").call([
                                "groupId": group.id ?? "",
                                "content": content,
                                "isAnonymous": isAnonymous
                            ])
                            dismiss()
                        }
                    }
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(content.count >= 5 ? Color(red: 0.60, green: 0.50, blue: 0.90) : AmenTheme.Colors.textTertiary)
                    .disabled(content.count < 5 || content.count > maxChars || isPosting)
                }
            }
        }
    }
}

struct CreateSupportGroupSheet: View {
    let service: SupportGroupService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var category: SupportGroupCategory = .anxiety
    @State private var visibility: SupportGroupVisibility = .public
    @State private var guidelinesText = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Info") {
                    TextField("Group name", text: $name).font(.custom("OpenSans-Regular", size: 15))
                    TextField("Description", text: $description, axis: .vertical).font(.custom("OpenSans-Regular", size: 15)).lineLimit(3...6)
                }
                Section("Category & Visibility") {
                    Picker("Category", selection: $category) {
                        ForEach(SupportGroupCategory.allCases, id: \.self) { c in
                            Label(c.displayName, systemImage: c.icon).tag(c)
                        }
                    }
                    Picker("Visibility", selection: $visibility) {
                        ForEach([SupportGroupVisibility.public, .private, .churchOnly], id: \.self) { v in
                            Text(v.displayName).tag(v)
                        }
                    }
                }
                Section("Group Guidelines") {
                    TextField("Enter guidelines (one per line)", text: $guidelinesText, axis: .vertical).font(.custom("OpenSans-Regular", size: 14)).lineLimit(4...10)
                }
            }
            .navigationTitle("New Support Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() }.font(.custom("OpenSans-Regular", size: 16)) }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isCreating ? "Creating..." : "Create") {
                        guard !name.isEmpty else { return }
                        isCreating = true
                        Task {
                            let guidelines = guidelinesText.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                            _ = try? await service.createGroup(name: name, description: description, category: category, tags: [], guidelines: guidelines, visibility: visibility)
                            dismiss()
                        }
                    }
                    .font(.custom("OpenSans-Bold", size: 15)).disabled(name.isEmpty || isCreating)
                }
            }
        }
    }
}

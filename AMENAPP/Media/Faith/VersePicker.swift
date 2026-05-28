import SwiftUI
import FirebaseFunctions

struct CommonVerse: Identifiable {
    let id = UUID()
    let reference: String
    let text: String
}

private let commonVerses: [CommonVerse] = [
    CommonVerse(reference: "John 3:16", text: "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life."),
    CommonVerse(reference: "Psalm 23:1", text: "The LORD is my shepherd; I shall not want."),
    CommonVerse(reference: "Romans 8:28", text: "And we know that all things work together for good to them that love God, to them who are the called according to his purpose."),
    CommonVerse(reference: "Philippians 4:13", text: "I can do all things through Christ which strengtheneth me."),
    CommonVerse(reference: "Isaiah 40:31", text: "But they that wait upon the LORD shall renew their strength; they shall mount up with wings as eagles; they shall run, and not be weary; and they shall walk, and not faint."),
    CommonVerse(reference: "Jeremiah 29:11", text: "For I know the thoughts that I think toward you, saith the LORD, thoughts of peace, and not of evil, to give you an expected end."),
    CommonVerse(reference: "Proverbs 3:5", text: "Trust in the LORD with all thine heart; and lean not unto thine own understanding."),
    CommonVerse(reference: "Matthew 6:33", text: "But seek ye first the kingdom of God, and his righteousness; and all these things shall be added unto you."),
    CommonVerse(reference: "Romans 12:2", text: "And be not conformed to this world: but be ye transformed by the renewing of your mind."),
    CommonVerse(reference: "2 Timothy 1:7", text: "For God hath not given us the spirit of fear; but of power, and of love, and of a sound mind."),
    CommonVerse(reference: "Psalm 46:1", text: "God is our refuge and strength, a very present help in trouble."),
    CommonVerse(reference: "Galatians 5:22", text: "But the fruit of the Spirit is love, joy, peace, longsuffering, gentleness, goodness, faith."),
    CommonVerse(reference: "Ephesians 2:8", text: "For by grace are ye saved through faith; and that not of yourselves: it is the gift of God."),
    CommonVerse(reference: "1 Corinthians 13:4", text: "Charity suffereth long, and is kind; charity envieth not; charity vaunteth not itself, is not puffed up."),
    CommonVerse(reference: "Psalm 119:105", text: "Thy word is a lamp unto my feet, and a light unto my path."),
]

struct VersePicker: View {
    @Binding var isPresented: Bool
    var attachedToId: String
    var attachedToType: VerseAttachmentTarget
    var onAttached: (VerseAttachment) -> Void

    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filtered: [CommonVerse] {
        guard !searchText.isEmpty else { return commonVerses }
        return commonVerses.filter {
            $0.reference.localizedCaseInsensitiveContains(searchText) ||
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { verse in
                Button { attach(verse) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verse.reference)
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.amenGold)
                        Text(verse.text.prefix(80) + (verse.text.count > 80 ? "…" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search scripture")
            .navigationTitle("Attach a Verse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
    }

    private func attach(_ verse: CommonVerse) {
        isLoading = true
        let functions = Functions.functions()
        functions.httpsCallable("attachVerse").call([
            "reference": verse.reference,
            "attachedToId": attachedToId,
            "attachedToType": attachedToType.rawValue
        ]) { result, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error {
                    errorMessage = error.localizedDescription
                    return
                }
                let attachment = VerseAttachment(
                    reference: verse.reference,
                    text: verse.text,
                    attachedToId: attachedToId,
                    attachedToType: attachedToType
                )
                onAttached(attachment)
                isPresented = false
            }
        }
    }
}

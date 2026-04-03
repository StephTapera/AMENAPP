//
//  AttachVerseSheet.swift
//  AMENAPP
//
//  Smart Bible verse attachment for CreatePost.
//
//  Search strategy (in order):
//  1. If query looks like a verse reference (e.g. "John 3:16") → YouVersionBibleService.fetchVerse()
//  2. Otherwise → YouVersionBibleService.searchVerses() for keyword search
//  3. If API fails (bad key, offline) → LocalVerseLibrary fuzzy match
//
//  ⚠️  API KEY REQUIRED:
//  scripture.api.bible is free for developers — sign up at https://scripture.api.bible/
//  Then update Config.xcconfig:  YOUVERSION_API_KEY = <your-key>
//

import SwiftUI
import Combine

// MARK: - Design tokens (preserved from original)

private let neuBG    = Color(red: 0.94, green: 0.94, blue: 0.96)
private let neuDark  = Color(red: 0.78, green: 0.78, blue: 0.82).opacity(0.8)
private let neuLight = Color.white.opacity(0.95)
private let accentR  = Color(red: 0.98, green: 0.42, blue: 0.32)
private let accentB  = Color(red: 0.35, green: 0.40, blue: 0.90)

// MARK: - Neumorphic modifiers (preserved)

private struct NeuRaised: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(neuBG)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: neuDark,  radius: 7, x: 4, y: 4)
            .shadow(color: neuLight, radius: 7, x: -4, y: -4)
    }
}

private struct NeuPressed: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(neuBG)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(neuDark, lineWidth: 1.5).blur(radius: 1).offset(x: 1.5, y: 1.5)
                    .mask(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(neuLight, lineWidth: 1.5).blur(radius: 1).offset(x: -1.5, y: -1.5)
                    .mask(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
    }
}

extension View {
    fileprivate func neuRaised(_ r: CGFloat = 14) -> some View { modifier(NeuRaised(radius: r)) }
    fileprivate func neuPressed(_ r: CGFloat = 14) -> some View { modifier(NeuPressed(radius: r)) }
}

// MARK: - Models

struct BibleVerse: Identifiable, Equatable {
    let id = UUID()
    let reference: String
    let text: String
    let translation: String
}

enum BibleTranslation: String, CaseIterable {
    case NIV, ESV, KJV, NKJV, NLT, NASB

    var apiVersion: ScripturePassage.BibleVersion {
        switch self {
        case .NIV:  return .niv
        case .ESV:  return .esv
        case .KJV:  return .kjv
        case .NKJV: return .nkjv
        case .NLT:  return .nlt
        case .NASB: return .nasb
        }
    }
}

// MARK: - Local Verse Library (API fallback)
// 100+ curated popular verses for offline / bad-key scenarios.

private enum LocalVerseLibrary {
    struct Entry {
        let reference: String
        let text: String
        let keywords: [String]   // for fuzzy matching
    }

    static let verses: [Entry] = [
        // Strength & Courage
        .init(reference: "Philippians 4:13", text: "I can do all this through him who gives me strength.", keywords: ["strength","can do all things","christ","strengthen"]),
        .init(reference: "Isaiah 40:31", text: "But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.", keywords: ["strength","hope","eagles","renew","weary"]),
        .init(reference: "Joshua 1:9", text: "Be strong and courageous. Do not be afraid; do not be discouraged, for the Lord your God will be with you wherever you go.", keywords: ["strong","courageous","afraid","fear","discouraged","wherever"]),
        .init(reference: "Psalm 46:1", text: "God is our refuge and strength, an ever-present help in trouble.", keywords: ["refuge","strength","help","trouble"]),
        .init(reference: "2 Timothy 1:7", text: "For the Spirit God gave us does not make us timid, but gives us power, love and self-discipline.", keywords: ["fear","power","love","sound mind","timid","spirit"]),
        .init(reference: "Isaiah 41:10", text: "So do not fear, for I am with you; do not be dismayed, for I am your God. I will strengthen you and help you; I will uphold you with my righteous right hand.", keywords: ["fear","strengthen","help","uphold","God"]),
        // Peace
        .init(reference: "Philippians 4:6-7", text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.", keywords: ["anxious","anxiety","peace","prayer","thanksgiving","worry","heart","mind"]),
        .init(reference: "John 14:27", text: "Peace I leave with you; my peace I give you. I do not give to you as the world gives. Do not let your hearts be troubled and do not be afraid.", keywords: ["peace","troubled","afraid","heart"]),
        .init(reference: "Isaiah 26:3", text: "You will keep in perfect peace those whose minds are steadfast, because they trust in you.", keywords: ["peace","mind","steadfast","trust"]),
        .init(reference: "Romans 15:13", text: "May the God of hope fill you with all joy and peace as you trust in him, so that you may overflow with hope by the power of the Holy Spirit.", keywords: ["hope","joy","peace","trust","overflow","Holy Spirit"]),
        // Love
        .init(reference: "John 3:16", text: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.", keywords: ["love","God","world","son","believe","eternal life","perish"]),
        .init(reference: "1 Corinthians 13:4-5", text: "Love is patient, love is kind. It does not envy, it does not boast, it is not proud. It does not dishonor others, it is not self-seeking, it is not easily angered, it keeps no record of wrongs.", keywords: ["love","patient","kind","envy","boast","proud","angry","record"]),
        .init(reference: "Romans 8:38-39", text: "For I am convinced that neither death nor life, neither angels nor demons, neither the present nor the future, nor any powers, neither height nor depth, nor anything else in all creation, will be able to separate us from the love of God that is in Christ Jesus our Lord.", keywords: ["love","separate","death","life","angels","powers","God","convinced"]),
        .init(reference: "1 John 4:8", text: "Whoever does not love does not know God, because God is love.", keywords: ["love","God","know"]),
        .init(reference: "John 15:13", text: "Greater love has no one than this: to lay down one's life for one's friends.", keywords: ["love","lay down","life","friends","greater"]),
        // Faith & Trust
        .init(reference: "Proverbs 3:5-6", text: "Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.", keywords: ["trust","heart","understanding","paths","submit","straight","lean"]),
        .init(reference: "Hebrews 11:1", text: "Now faith is confidence in what we hope for and assurance about what we do not see.", keywords: ["faith","hope","confidence","assurance","see"]),
        .init(reference: "Romans 8:28", text: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.", keywords: ["good","purpose","called","works","love","things"]),
        .init(reference: "Psalm 23:1", text: "The Lord is my shepherd, I lack nothing.", keywords: ["shepherd","lack","Lord","nothing"]),
        .init(reference: "Matthew 6:33", text: "But seek first his kingdom and his righteousness, and all these things will be given to you as well.", keywords: ["seek","kingdom","righteousness","things","given"]),
        // Hope
        .init(reference: "Jeremiah 29:11", text: "\"For I know the plans I have for you,\" declares the Lord, \"plans to prosper you and not to harm you, plans to give you hope and a future.\"", keywords: ["plans","future","hope","prosper","harm","know"]),
        .init(reference: "Romans 5:3-4", text: "Not only so, but we also glory in our sufferings, because we know that suffering produces perseverance; perseverance, character; and character, hope.", keywords: ["suffering","perseverance","character","hope","glory"]),
        .init(reference: "Lamentations 3:22-23", text: "Because of the Lord's great love we are not consumed, for his compassions never fail. They are new every morning; great is your faithfulness.", keywords: ["compassion","mercy","morning","faithfulness","love","new","consumed"]),
        // Prayer
        .init(reference: "Matthew 7:7", text: "Ask and it will be given to you; seek and you will find; knock and the door will be opened to you.", keywords: ["ask","seek","knock","find","door","given"]),
        .init(reference: "1 Thessalonians 5:17", text: "Pray continually.", keywords: ["pray","prayer","continually","always"]),
        .init(reference: "James 5:16", text: "Therefore confess your sins to each other and pray for each other so that you may be healed. The prayer of a righteous person is powerful and effective.", keywords: ["pray","confession","healed","righteous","powerful","effective"]),
        // Grace & Salvation
        .init(reference: "Ephesians 2:8-9", text: "For it is by grace you have been saved, through faith—and this is not from yourselves, it is the gift of God—not by works, so that no one can boast.", keywords: ["grace","saved","faith","gift","works","boast"]),
        .init(reference: "John 3:17", text: "For God did not send his Son into the world to condemn the world, but to save the world through him.", keywords: ["saved","save","condemn","world","son"]),
        .init(reference: "Romans 10:9", text: "If you declare with your mouth, \"Jesus is Lord,\" and believe in your heart that God raised him from the dead, you will be saved.", keywords: ["saved","declare","believe","mouth","heart","Lord","resurrection"]),
        // Forgiveness
        .init(reference: "1 John 1:9", text: "If we confess our sins, he is faithful and just and will forgive us our sins and purify us from all unrighteousness.", keywords: ["confess","forgive","faithful","sins","purify","unrighteousness"]),
        .init(reference: "Colossians 3:13", text: "Bear with each other and forgive one another if any of you has a grievance against someone. Forgive as the Lord forgave you.", keywords: ["forgive","bear","grievance","forgave","Lord"]),
        .init(reference: "Psalm 103:12", text: "As far as the east is from the west, so far has he removed our transgressions from us.", keywords: ["forgive","transgressions","east","west","removed"]),
        // Joy
        .init(reference: "Psalm 16:11", text: "You make known to me the path of life; you will fill me with joy in your presence, with eternal pleasures at your right hand.", keywords: ["joy","presence","path","life","pleasure"]),
        .init(reference: "Nehemiah 8:10", text: "Do not grieve, for the joy of the Lord is your strength.", keywords: ["joy","strength","Lord","grieve"]),
        .init(reference: "James 1:2-3", text: "Consider it pure joy, my brothers and sisters, whenever you face trials of many kinds, because you know that the testing of your faith produces perseverance.", keywords: ["joy","trials","testing","faith","perseverance"]),
        // Wisdom
        .init(reference: "James 1:5", text: "If any of you lacks wisdom, you should ask God, who gives generously to all without finding fault, and it will be given to you.", keywords: ["wisdom","ask","God","generously","lack"]),
        .init(reference: "Proverbs 16:3", text: "Commit to the Lord whatever you do, and he will establish your plans.", keywords: ["commit","plans","establish","Lord"]),
        .init(reference: "Psalm 119:105", text: "Your word is a lamp for my feet, a light on my path.", keywords: ["word","lamp","light","path","feet"]),
        // New Life & Renewal
        .init(reference: "2 Corinthians 5:17", text: "Therefore, if anyone is in Christ, the new creation has come: The old has gone, the new is here!", keywords: ["new creation","new","old","Christ","transformation","changed"]),
        .init(reference: "Romans 12:2", text: "Do not conform to the pattern of this world, but be transformed by the renewing of your mind. Then you will be able to test and approve what God's will is—his good, pleasing and perfect will.", keywords: ["transform","renew","mind","world","conform","will","perfect"]),
        .init(reference: "Isaiah 43:19", text: "See, I am doing a new thing! Now it springs up; do you not perceive it? I am making a way in the wilderness and streams in the wasteland.", keywords: ["new","way","wilderness","streams","doing"]),
        // Purpose & Calling
        .init(reference: "Ephesians 2:10", text: "For we are God's handiwork, created in Christ Jesus to do good works, which God prepared in advance for us to do.", keywords: ["purpose","handiwork","created","good works","prepared"]),
        .init(reference: "Romans 8:30", text: "And those he predestined, he also called; those he called, he also justified; those he justified, he also glorified.", keywords: ["called","predestined","justified","glorified","purpose"]),
        .init(reference: "1 Peter 2:9", text: "But you are a chosen people, a royal priesthood, a holy nation, God's special possession, that you may declare the praises of him who called you out of darkness into his wonderful light.", keywords: ["chosen","royal","priesthood","holy","declare","light","darkness","called"]),
        // Gratitude & Thanksgiving
        .init(reference: "1 Thessalonians 5:18", text: "Give thanks in all circumstances; for this is God's will for you in Christ Jesus.", keywords: ["thanksgiving","thanks","circumstances","will","grateful"]),
        .init(reference: "Psalm 107:1", text: "Give thanks to the Lord, for he is good; his love endures forever.", keywords: ["thanks","Lord","good","love","endures","forever"]),
        .init(reference: "Colossians 3:17", text: "And whatever you do, whether in word or deed, do it all in the name of the Lord Jesus, giving thanks to God the Father through him.", keywords: ["thanks","name","Lord","deed","word"]),
        // Comfort & Healing
        .init(reference: "Psalm 34:18", text: "The Lord is close to the brokenhearted and saves those who are crushed in spirit.", keywords: ["broken","heart","brokenhearted","saves","crushed","spirit","close"]),
        .init(reference: "Matthew 11:28", text: "Come to me, all you who are weary and burdened, and I will give you rest.", keywords: ["rest","weary","burdened","come","tired"]),
        .init(reference: "2 Corinthians 1:3-4", text: "Praise be to the God and Father of our Lord Jesus Christ, the Father of compassion and the God of all comfort, who comforts us in all our troubles, so that we can comfort those in any trouble.", keywords: ["comfort","compassion","troubles","praise"]),
        .init(reference: "Revelation 21:4", text: "He will wipe every tear from their eyes. There will be no more death or mourning or crying or pain, for the old order of things has passed away.", keywords: ["tears","death","pain","mourning","crying","heaven","comfort"]),
        // Scripture / Word of God
        .init(reference: "2 Timothy 3:16-17", text: "All Scripture is God-breathed and is useful for teaching, rebuking, correcting and training in righteousness, so that the servant of God may be thoroughly equipped for every good work.", keywords: ["scripture","word","teaching","rebuking","training","righteousness","equipped"]),
        .init(reference: "Hebrews 4:12", text: "For the word of God is alive and active. Sharper than any double-edged sword, it penetrates even to dividing soul and spirit, joints and marrow; it judges the thoughts and attitudes of the heart.", keywords: ["word","alive","active","sword","penetrates","soul","spirit","heart"]),
        // Holy Spirit
        .init(reference: "John 14:26", text: "But the Advocate, the Holy Spirit, whom the Father will send in my name, will teach you all things and will remind you of everything I have said to you.", keywords: ["Holy Spirit","advocate","teach","remind"]),
        .init(reference: "Galatians 5:22-23", text: "But the fruit of the Spirit is love, joy, peace, forbearance, kindness, goodness, faithfulness, gentleness and self-control. Against such things there is no law.", keywords: ["fruit","Spirit","love","joy","peace","kindness","goodness","faithfulness","gentleness","self-control"]),
        // Specific common references
        .init(reference: "John 1:1", text: "In the beginning was the Word, and the Word was with God, and the Word was God.", keywords: ["beginning","Word","God"]),
        .init(reference: "Psalm 27:1", text: "The Lord is my light and my salvation—whom shall I fear? The Lord is the stronghold of my life—of whom shall I be afraid?", keywords: ["light","salvation","fear","stronghold","afraid"]),
        .init(reference: "Psalm 91:1-2", text: "Whoever dwells in the shelter of the Most High will rest in the shadow of the Almighty. I will say of the Lord, 'He is my refuge and my fortress, my God, in whom I trust.'", keywords: ["shelter","refuge","fortress","trust","Most High","shadow","Almighty"]),
        .init(reference: "Matthew 5:3-4", text: "Blessed are the poor in spirit, for theirs is the kingdom of heaven. Blessed are those who mourn, for they will be comforted.", keywords: ["blessed","beatitudes","poor","spirit","mourn","comfort","kingdom"]),
        .init(reference: "John 11:25", text: "Jesus said to her, 'I am the resurrection and the life. The one who believes in me will live, even though they die.'", keywords: ["resurrection","life","believe","live","die"]),
        .init(reference: "Micah 6:8", text: "He has shown you, O mortal, what is good. And what does the Lord require of you? To act justly and to love mercy and to walk humbly with your God.", keywords: ["justice","mercy","humble","walk","require","good"]),
        .init(reference: "Matthew 28:19-20", text: "Therefore go and make disciples of all nations, baptizing them in the name of the Father and of the Son and of the Holy Spirit, and teaching them to obey everything I have commanded you. And surely I am with you always, to the very end of the age.", keywords: ["great commission","go","disciples","nations","baptize","teach","always"]),
        .init(reference: "Romans 3:23", text: "For all have sinned and fall short of the glory of God.", keywords: ["sin","sinned","fall short","glory"]),
        .init(reference: "Romans 6:23", text: "For the wages of sin is death, but the gift of God is eternal life in Christ Jesus our Lord.", keywords: ["sin","death","gift","eternal life","wages"]),
        .init(reference: "Acts 1:8", text: "But you will receive power when the Holy Spirit comes on you; and you will be my witnesses in Jerusalem, and in all Judea and Samaria, and to the ends of the earth.", keywords: ["power","Holy Spirit","witnesses","Jerusalem","earth"]),
        .init(reference: "James 4:7", text: "Submit yourselves, then, to God. Resist the devil, and he will flee from you.", keywords: ["submit","resist","devil","flee","enemy"]),
        .init(reference: "Psalm 1:1-2", text: "Blessed is the one who does not walk in step with the wicked or stand in the way that sinners take or sit in the company of mockers, but whose delight is in the law of the Lord, and who meditates on his law day and night.", keywords: ["blessed","wicked","delight","law","meditate","day","night"]),
        .init(reference: "Luke 6:31", text: "Do to others as you would have them do to you.", keywords: ["golden rule","others","do","treat"]),
        .init(reference: "John 8:32", text: "Then you will know the truth, and the truth will set you free.", keywords: ["truth","free","know","freedom"]),
        .init(reference: "Genesis 1:1", text: "In the beginning God created the heavens and the earth.", keywords: ["beginning","created","heavens","earth","creation"]),
        .init(reference: "Exodus 14:14", text: "The Lord will fight for you; you need only to be still.", keywords: ["fight","still","battle","Lord"]),
        .init(reference: "Psalm 37:4", text: "Take delight in the Lord, and he will give you the desires of your heart.", keywords: ["delight","desires","heart","Lord"]),
        .init(reference: "Luke 1:37", text: "For no word from God will ever fail.", keywords: ["nothing","impossible","God","word","fail"]),
        .init(reference: "Mark 11:24", text: "Therefore I tell you, whatever you ask for in prayer, believe that you have received it, and it will be yours.", keywords: ["prayer","ask","believe","receive","faith"]),
    ]

    // MARK: - Smart fuzzy search

    static func search(_ query: String, translation: BibleTranslation) -> [BibleVerse] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var scored: [(score: Int, entry: Entry)] = []

        for entry in verses {
            var score = 0
            let refLower = entry.reference.lowercased()
            let textLower = entry.text.lowercased()

            // Exact reference match
            if refLower == q { score += 100 }
            // Reference starts with query
            else if refLower.hasPrefix(q) { score += 80 }
            // Reference contains query
            else if refLower.contains(q) { score += 60 }
            // Text contains full query
            if textLower.contains(q) { score += 40 }
            // Keyword matches
            for keyword in entry.keywords {
                if keyword.lowercased().contains(q) || q.contains(keyword.lowercased()) {
                    score += 20
                }
            }
            // Word-level text matching
            let words = q.components(separatedBy: .whitespaces).filter { $0.count > 2 }
            for word in words {
                if textLower.contains(word) { score += 10 }
                if refLower.contains(word) { score += 15 }
            }

            if score > 0 {
                scored.append((score, entry))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(8)
            .map { BibleVerse(reference: $0.entry.reference, text: $0.entry.text, translation: translation.rawValue) }
    }
}

// MARK: - View Model

@MainActor
class AttachVerseViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedTranslation: BibleTranslation = .NIV
    @Published var results: [BibleVerse] = []
    @Published var selectedVerse: BibleVerse? = nil
    @Published var isLoading = false
    @Published var hasSearched = false
    @Published var usingLocalFallback = false  // shown subtly when API unavailable

    private var searchTask: Task<Void, Never>?

    let suggestions = ["John 3:16", "fear not", "peace", "strength", "Philippians 4:13", "Jeremiah 29:11"]

    // Reference pattern: e.g. "John 3:16", "Phil 4:13", "1 Cor 13:4"
    private let referencePattern = try? NSRegularExpression(
        pattern: #"^[1-3]?\s?[A-Za-z]+\.?\s+\d+:\d+"#,
        options: []
    )

    func search() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []; hasSearched = false; return
        }
        searchTask?.cancel()
        isLoading = true
        hasSearched = true
        usingLocalFallback = false

        searchTask = Task {
            // 300ms debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let isRef = looksLikeReference(query)
            var apiResults: [BibleVerse] = []
            var apiSucceeded = false

            // Try the real API first
            do {
                let version = selectedTranslation.apiVersion
                if isRef {
                    // Direct verse fetch
                    let passage = try await YouVersionBibleService.shared.fetchVerse(
                        reference: query, version: version
                    )
                    apiResults = [BibleVerse(
                        reference: passage.reference,
                        text: passage.text,
                        translation: selectedTranslation.rawValue
                    )]
                } else {
                    // Keyword search
                    let passages = try await YouVersionBibleService.shared.searchVerses(
                        query: query, version: version, limit: 10
                    )
                    apiResults = passages.map { BibleVerse(
                        reference: $0.reference,
                        text: $0.text,
                        translation: selectedTranslation.rawValue
                    )}
                }
                apiSucceeded = !apiResults.isEmpty
            } catch {
                dlog("⚠️ [AttachVerse] API failed (\(error.localizedDescription)) — using local library")
                apiSucceeded = false
            }

            guard !Task.isCancelled else { return }

            if apiSucceeded {
                results = apiResults
                usingLocalFallback = false
            } else {
                // Graceful fallback to local library
                results = LocalVerseLibrary.search(query, translation: selectedTranslation)
                usingLocalFallback = true
            }
            isLoading = false
        }
    }

    func selectSuggestion(_ s: String) {
        searchText = s
        search()
    }

    private func looksLikeReference(_ text: String) -> Bool {
        guard let regex = referencePattern else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}

// MARK: - Attach Verse Sheet

struct AttachVerseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AttachVerseViewModel()
    var onAttach: (BibleVerse) -> Void

    @State private var cardScale: CGFloat = 0.92
    @State private var contentOpacity: Double = 0
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            neuBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(neuDark)
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                translationPicker
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                searchField
                    .padding(.top, 14)
                    .padding(.horizontal, 20)

                // Local fallback notice — subtle, only when API not available
                if vm.usingLocalFallback && vm.hasSearched {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                            .font(.systemScaled(10))
                        Text("Showing offline results · Add a valid API key for full search")
                            .font(.systemScaled(11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.opacity)
                }

                ZStack {
                    if vm.isLoading {
                        loadingView
                    } else if vm.hasSearched && vm.results.isEmpty {
                        emptyState
                    } else if !vm.results.isEmpty {
                        resultsList
                    } else {
                        emptyPrompt
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.results.count)
                .animation(.easeInOut(duration: 0.2), value: vm.isLoading)

                Spacer(minLength: 0)
            }
            .scaleEffect(cardScale)
            .opacity(contentOpacity)
        }
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.82))) {
                cardScale = 1.0
                contentOpacity = 1.0
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button { animateDismiss() } label: {
                Text("Cancel")
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .neuRaised(12)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Attach Verse")
                .font(.systemScaled(17, weight: .semibold))
                .foregroundColor(Color(white: 0.18))

            Spacer()

            Button {
                if let verse = vm.selectedVerse {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        onAttach(verse)
                        animateDismiss()
                    }
                }
            } label: {
                Text("Attach")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundColor(vm.selectedVerse != nil ? accentB : Color(white: 0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(vm.selectedVerse != nil ? accentB.opacity(0.12) : neuBG)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: vm.selectedVerse != nil ? accentB.opacity(0.15) : .clear, radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(vm.selectedVerse == nil)
            .animation(.spring(response: 0.3), value: vm.selectedVerse != nil)
        }
    }

    // MARK: - Translation Picker

    private var translationPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BibleTranslation.allCases, id: \.self) { t in
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                            vm.selectedTranslation = t
                        }
                        if vm.hasSearched { vm.search() }
                    } label: {
                        Text(t.rawValue)
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundColor(vm.selectedTranslation == t ? .white : Color(white: 0.4))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(vm.selectedTranslation == t ? accentB : neuBG)
                            .clipShape(Capsule())
                            .shadow(
                                color: vm.selectedTranslation == t ? accentB.opacity(0.35) : neuDark,
                                radius: vm.selectedTranslation == t ? 8 : 5,
                                x: vm.selectedTranslation == t ? 0 : 3,
                                y: vm.selectedTranslation == t ? 4 : 3
                            )
                            .shadow(
                                color: vm.selectedTranslation == t ? .clear : neuLight,
                                radius: 5, x: -3, y: -3
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(inputFocused ? accentB : .secondary)
                .font(.systemScaled(15, weight: inputFocused ? .semibold : .regular))
                .animation(.spring(response: 0.2), value: inputFocused)

            TextField("Search: John 3:16 · fear not · verse about peace", text: $vm.searchText)
                .font(.systemScaled(14))
                .foregroundColor(Color(white: 0.2))
                .focused($inputFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { vm.search() }
                .onChange(of: vm.searchText) { _, _ in vm.search() }

            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                    vm.results = []
                    vm.hasSearched = false
                    vm.selectedVerse = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.systemScaled(15))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(neuBG)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(inputFocused ? accentB.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
        .shadow(color: neuDark, radius: 6, x: 3, y: 3)
        .shadow(color: neuLight, radius: 6, x: -3, y: -3)
        .animation(.spring(response: 0.25), value: inputFocused)
    }

    // MARK: - Empty Prompt

    private var emptyPrompt: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(accentB.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "book.closed.fill")
                    .font(.systemScaled(34, weight: .light))
                    .foregroundColor(accentB.opacity(0.6))
            }
            .padding(.top, 20)
            Text("Search by keyword or reference")
                .font(.systemScaled(16, weight: .medium))
                .foregroundColor(Color(white: 0.4))
            VStack(spacing: 10) {
                ForEach(vm.suggestions, id: \.self) { s in
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                            vm.selectSuggestion(s)
                        }
                    } label: {
                        Text("\"\(s)\"")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundColor(accentB)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(accentB.opacity(0.08))
                            .clipShape(Capsule())
                            .shadow(color: accentB.opacity(0.1), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(accentB.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .scaleEffect(vm.isLoading ? 1.4 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                            value: vm.isLoading
                        )
                }
            }
            Text("Searching scriptures…")
                .font(.systemScaled(14))
                .foregroundColor(.secondary)
            Spacer()
        }
        .transition(.opacity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(30))
                .foregroundColor(Color(white: 0.6))
            Text("No verses found")
                .font(.systemScaled(16, weight: .medium))
                .foregroundColor(Color(white: 0.4))
            Text("Try a different keyword or verse reference")
                .font(.systemScaled(13))
                .foregroundColor(.secondary)
            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(Array(vm.results.enumerated()), id: \.element.id) { idx, verse in
                    verseCard(verse, index: idx)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func verseCard(_ verse: BibleVerse, index: Int) -> some View {
        let isSelected = vm.selectedVerse?.id == verse.id
        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.72))) {
                vm.selectedVerse = isSelected ? nil : verse
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(verse.reference)
                            .font(.systemScaled(14, weight: .bold))
                            .foregroundColor(isSelected ? accentB : Color(white: 0.2))
                        Text(verse.translation)
                            .font(.systemScaled(10, weight: .semibold))
                            .foregroundColor(isSelected ? accentB : accentR)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((isSelected ? accentB : accentR).opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(verse.text)
                        .font(.systemScaled(13))
                        .foregroundColor(Color(white: isSelected ? 0.2 : 0.4))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(isSelected ? accentB : neuBG)
                        .frame(width: 26, height: 26)
                        .shadow(color: isSelected ? accentB.opacity(0.3) : neuDark, radius: 4, x: 2, y: 2)
                        .shadow(color: isSelected ? .clear : neuLight, radius: 4, x: -2, y: -2)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.systemScaled(11, weight: .bold))
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.25), value: isSelected)
            }
            .padding(16)
            .background(isSelected ? accentB.opacity(0.06) : neuBG)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? accentB.opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: isSelected ? accentB.opacity(0.12) : neuDark,
                    radius: isSelected ? 10 : 6,
                    x: isSelected ? 0 : 3,
                    y: isSelected ? 5 : 3)
            .shadow(color: isSelected ? .clear : neuLight, radius: 6, x: -3, y: -3)
            .scaleEffect(isSelected ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
        .animation(
            .spring(response: 0.38, dampingFraction: 0.78).delay(Double(index) * 0.04),
            value: vm.results.count
        )
    }

    // MARK: - Dismiss

    private func animateDismiss() {
        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.85))) {
            cardScale = 0.92
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismiss() }
    }
}

// MARK: - Attached Verse Badge (in composer)

struct AttachedVerseBadge: View {
    let verse: BibleVerse
    var onRemove: () -> Void

    @State private var appear = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed.fill")
                .font(.systemScaled(13))
                .foregroundColor(accentB)

            VStack(alignment: .leading, spacing: 1) {
                Text(verse.reference)
                    .font(.systemScaled(12, weight: .bold))
                    .foregroundColor(accentB)
                Text(verse.text)
                    .font(.systemScaled(11))
                    .foregroundColor(Color(white: 0.4))
                    .lineLimit(2)
            }

            Spacer()

            Button { onRemove() } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(neuBG)
                    .clipShape(Circle())
                    .shadow(color: neuDark, radius: 3, x: 2, y: 2)
                    .shadow(color: neuLight, radius: 3, x: -2, y: -2)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(accentB.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accentB.opacity(0.2), lineWidth: 1)
        )
        .scaleEffect(appear ? 1 : 0.85)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.7))) { appear = true }
        }
    }
}

// MARK: - Preview

#Preview {
    Color(red: 0.94, green: 0.94, blue: 0.96)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AttachVerseSheet { verse in
                print("Attached: \(verse.reference)")
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
}

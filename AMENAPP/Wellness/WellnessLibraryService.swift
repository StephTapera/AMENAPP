import Foundation
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class WellnessLibraryService: ObservableObject {
    @Published var items: [WellnessContent] = WellnessLibraryService.seedContent
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var listener: ListenerRegistration?

    func fetchItems(category: WellnessCategory? = nil, type: WellnessContentType? = nil, difficulty: WellnessDifficulty? = nil) {
        isLoading = true
        var query: Query = db.collection("wellness")
            .whereField("guardianModerated", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
        if let cat = category {
            query = query.whereField("category", arrayContains: cat.rawValue)
        }
        if let t = type {
            query = query.whereField("type", isEqualTo: t.rawValue)
        }
        if let d = difficulty {
            query = query.whereField("difficulty", isEqualTo: d.rawValue)
        }
        listener?.remove()
        listener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            isLoading = false
            if let error {
                errorMessage = error.localizedDescription
                // Seed content already in items — nothing more to do
                return
            }
            let remoteItems = (snapshot?.documents ?? []).compactMap { doc in
                try? doc.data(as: WellnessContent.self)
            }
            let remoteIds = Set(remoteItems.compactMap(\.id))
            // Firestore results take priority; seed fills any gap
            let merged = remoteItems + Self.seedContent.filter { item in
                guard let id = item.id else { return false }
                return !remoteIds.contains(id)
            }
            // Apply local filters to the merged list
            items = merged.filter { item in
                let catMatch = category.map { item.category.contains($0) } ?? true
                let typeMatch = type.map { item.type == $0 } ?? true
                let diffMatch = difficulty.map { item.difficulty == $0 } ?? true
                return catMatch && typeMatch && diffMatch
            }
        }
    }

    func trackEngagement(wellnessId: String, action: String) {
        Task {
            _ = try? await functions.httpsCallable("trackWellnessEngagement").call([
                "wellnessId": wellnessId,
                "action": action
            ])
        }
    }

    func recommend(context: String) async -> [WellnessContent] {
        do {
            let result = try await functions.httpsCallable("recommendWellnessContent").call(["context": context])
            guard let data = result.data as? [[String: Any]] else { return [] }
            return data.compactMap { dict -> WellnessContent? in
                guard let id = dict["wellnessId"] as? String,
                      let title = dict["title"] as? String,
                      let typeRaw = dict["type"] as? String,
                      let type = WellnessContentType(rawValue: typeRaw),
                      let diffRaw = dict["difficulty"] as? String,
                      let difficulty = WellnessDifficulty(rawValue: diffRaw)
                else { return nil }
                return WellnessContent(id: id, type: type, title: title, description: "", difficulty: difficulty, category: [], tags: [], durationSeconds: nil, steps: nil, body: nil, audioUrl: nil, videoUrl: nil, linkedVerses: nil, engagementViewCount: 0, engagementSavedCount: 0, engagementHelpfulCount: 0, createdAt: nil, guardianModerated: true)
            }
        } catch { return [] }
    }

    deinit { listener?.remove() }

    // MARK: - Seed Content
    // 20+ faith-based wellness items covering all 7 types and all 8 categories.
    // Shown immediately on launch so the library is never empty while Firestore loads.
    // Firestore results take priority on id match; seed fills any remaining gaps.
    static let seedContent: [WellnessContent] = [

        // 1. groundingExercise / anxiety — 5-4-3-2-1 Grounding
        WellnessContent(
            id: "seed_001",
            type: .groundingExercise,
            title: "5-4-3-2-1 Grounding",
            description: "When anxious thoughts race, this simple sensory exercise anchors you in the present moment and gently reminds you that you are safe right here, right now.",
            difficulty: .beginner,
            category: [.anxiety],
            tags: ["grounding", "anxiety", "present-moment", "senses"],
            durationSeconds: 300,
            steps: [
                "Take one slow, deep breath in through your nose for four counts, then release for four counts.",
                "Notice 5 things you can see around you. Name them quietly — the color of the wall, the grain in wood, a patch of light.",
                "Notice 4 things you can physically feel right now — your feet on the floor, the fabric of your clothes, the air on your skin.",
                "Notice 3 things you can hear — distant traffic, a bird, your own breathing.",
                "Notice 2 things you can smell, or recall two scents that bring you comfort. Then notice 1 thing you can taste or appreciate. Close with a breath and Psalm 46:10: 'Be still, and know that I am God.'"
            ],
            body: nil,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 46, verse: 10, text: "Be still, and know that I am God.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 2. groundingExercise / stress — Box Breathing
        WellnessContent(
            id: "seed_002",
            type: .groundingExercise,
            title: "Box Breathing with Surrender",
            description: "Box breathing is used by first responders and athletes to reset the nervous system in minutes. Paired with a short prayer of surrender, it becomes an act of trust.",
            difficulty: .beginner,
            category: [.stress],
            tags: ["breathing", "stress", "calm", "surrender"],
            durationSeconds: 300,
            steps: [
                "Sit comfortably and close your eyes. Rest your hands open in your lap as a posture of receiving.",
                "Inhale slowly for 4 counts, filling your lungs completely.",
                "Hold your breath gently for 4 counts. Silently pray: 'Lord, I release this moment to You.'",
                "Exhale slowly for 4 counts, letting tension leave with the breath.",
                "Hold empty for 4 counts. Repeat the full box at least four times, or until your heart rate settles."
            ],
            body: nil,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Philippians", chapter: 4, verse: 7, text: "And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 3. groundingExercise / depression — Safe Place Visualization
        WellnessContent(
            id: "seed_003",
            type: .groundingExercise,
            title: "Safe Place Visualization",
            description: "Depression can make the world feel grey and unsafe. This guided visualization creates an internal refuge — a place you can return to whenever darkness feels heavy.",
            difficulty: .beginner,
            category: [.depression],
            tags: ["visualization", "depression", "safety", "peace"],
            durationSeconds: 600,
            steps: [
                "Find a quiet place to sit or lie down. Close your eyes and take three slow breaths.",
                "Imagine a place — real or imagined — where you feel completely safe and at peace. It might be a sunlit field, a quiet chapel, a childhood garden, or a shore at sunrise.",
                "Look around your safe place with your mind's eye. Notice the colors, the quality of light, the sounds and scents around you.",
                "Feel the ground beneath you in this place. You are held, supported, and completely welcome here.",
                "Hear a gentle voice say the words of Isaiah 43:1: 'Do not fear, for I have redeemed you; I have called you by name; you are Mine.' Rest here as long as you need."
            ],
            body: nil,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Isaiah", chapter: 43, verse: 1, text: "Do not fear, for I have redeemed you; I have called you by name; you are Mine.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 4. groundingExercise / sleep — Progressive Muscle Release
        WellnessContent(
            id: "seed_004",
            type: .groundingExercise,
            title: "Progressive Muscle Release",
            description: "Carry the day's tension into this gentle body-scan practice. By deliberately tensing and releasing each muscle group, you signal your nervous system that it is safe to rest.",
            difficulty: .beginner,
            category: [.sleep],
            tags: ["sleep", "muscle-release", "body-scan", "rest"],
            durationSeconds: 480,
            steps: [
                "Lie down comfortably and close your eyes. Take three deep, slow breaths and let your body settle into the surface beneath you.",
                "Begin at your feet. Curl your toes tightly for five counts, then release completely. Feel the warmth of relaxation spread upward.",
                "Move to your calves, then thighs, then abdomen — tensing each group for five counts and releasing with a breath.",
                "Tense your hands into fists, then your arms, then shrug your shoulders to your ears — hold, then release, letting your shoulders drop heavily.",
                "Finally, scrunch your face for five counts and release. Breathe slowly and repeat Psalm 4:8 as you drift toward sleep: 'In peace I will lie down and sleep, for you alone, Lord, make me dwell in safety.'"
            ],
            body: nil,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 4, verse: 8, text: "In peace I will lie down and sleep, for you alone, Lord, make me dwell in safety.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 5. article / grief — When God Feels Distant
        WellnessContent(
            id: "seed_005",
            type: .article,
            title: "When God Feels Distant",
            description: "Grief can make God feel impossibly far away. This article explores why that experience is both deeply human and deeply biblical — and how to navigate the silence.",
            difficulty: .beginner,
            category: [.grief],
            tags: ["grief", "loss", "lament", "presence-of-God"],
            durationSeconds: 480,
            steps: nil,
            body: """
            Grief has a strange way of distorting our sense of God's presence. One day He feels close — a warm hand at your back — and the next, the silence is vast and bewildering. If you have felt this, you are not alone, and you are not spiritually broken.

            The Psalms are the most honest book in scripture precisely because they name this experience without apology. "My God, my God, why have you forsaken me?" (Psalm 22:1) is not the cry of a faithless person — it is the cry of someone so deep in grief that distance from God felt like abandonment. Jesus himself spoke these words from the cross.

            Grief reshapes our interior landscape. The neural pathways we built around a person, a relationship, a version of our life — those pathways keep firing into absence. That ache is not a sign of weak faith. It is the cost of having loved.

            What faith offers in grief is not a quick exit from the pain. It offers company in it. Lament is a spiritual practice — a form of prayer that refuses to pretend. When you bring your raw grief to God, you are not being unfaithful. You are trusting Him enough to show up as you actually are.

            The ancient church had seasons of lament built into the calendar — Lent, vigils, days of fasting and mourning. They understood that grief must be given time, ritual, and witness. If your community has made space for your grief, lean into it. If it hasn't, you may need to name that need.

            A practical anchor: when God feels absent, return to what is true in the body — the bread and cup of communion, the cool water of baptism remembered, the feel of scripture pages beneath your thumb. These are sacramental anchors that hold when emotion cannot. He has not moved. You are simply in the dark part of the valley. Keep walking.
            """,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 22, verse: 1, text: "My God, my God, why have you forsaken me?"),
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 23, verse: 4, text: "Even though I walk through the darkest valley, I will fear no evil, for you are with me.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 6. article / sleep — Rest as Spiritual Discipline
        WellnessContent(
            id: "seed_006",
            type: .article,
            title: "Rest as Spiritual Discipline",
            description: "Our culture treats exhaustion as a badge of honor. Scripture treats rest as a command. This article reclaims sleep not as weakness but as an act of faith.",
            difficulty: .beginner,
            category: [.sleep],
            tags: ["sleep", "Sabbath", "rest", "spiritual-discipline"],
            durationSeconds: 360,
            steps: nil,
            body: """
            Somewhere along the way, rest became something we earn rather than something we receive. We sleep when we collapse, not when we choose to trust. But the biblical vision of rest is radically different.

            The Sabbath was not an afterthought in the creation account — it was the crown of it. God did not rest because He was tired. He rested to model something: the rhythm of work and ceasing is built into the fabric of reality. When we refuse that rhythm, we are not being productive. We are being defiant.

            Psalm 127:2 makes this startlingly direct: "In vain you rise early and stay up late, toiling for food to eat — for He grants sleep to those He loves." Sleep, in this framing, is a gift from a Father who wants to provide for you while you rest. It requires trust to receive it — trust that the world will keep turning while you are unconscious, that God is not waiting for you to wake up to stay in control.

            Practically: the state of your sleep environment is a spiritual matter. The light from your phone tells your brain to stay alert. The scroll of social media stirs anxiety and comparison at the exact moment your nervous system needs to downshift. Creating a wind-down ritual is not self-indulgence — it is stewardship of the body God gave you.

            Consider a simple night office: ten minutes before bed, put the phone in another room. Sit quietly. Read a short psalm. Pray a brief prayer of release — give the unfinished tasks, the unresolved tensions, the worries about tomorrow back to the One who holds them all night long. Then sleep. It is an act of worship.
            """,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 127, verse: 2, text: "He grants sleep to those He loves."),
                WellnessContent.LinkedVerse(book: "Genesis", chapter: 2, verse: 3, text: "Then God blessed the seventh day and made it holy, because on it he rested.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 7. article / relationship — Forgiveness as a Practice
        WellnessContent(
            id: "seed_007",
            type: .article,
            title: "Forgiveness as a Practice",
            description: "Forgiveness is not a single decision — it is a practice you return to, sometimes daily. This article explores the difference between forgiving and forgetting, and why both matter.",
            difficulty: .intermediate,
            category: [.relationship],
            tags: ["forgiveness", "relationships", "healing", "grace"],
            durationSeconds: 480,
            steps: nil,
            body: """
            We have been taught to think of forgiveness as a switch — you flick it on, the hurt disappears, and you are done. But almost everyone who has tried to forgive a genuine wound knows it doesn't work that way. Forgiveness is not a transaction. It is a practice.

            C.S. Lewis wrote that he had to forgive the same person for the same injury dozens of times before it finally took. This is not spiritual failure — it is how forgiveness works in a finite, feeling human being. Every time the memory surfaces and the old anger rises, you are given another opportunity to choose again.

            The Greek word for forgiveness in the New Testament — aphiemi — literally means "to release" or "to let go." It is not the same as pretending the injury did not happen, or reconciling with someone who is still harmful, or excusing behavior that deserves accountability. Forgiveness is a decision about what you carry. It is choosing not to let what was done to you define the rest of your story.

            Forgiving does not mean forgetting. The brain does not have a delete key. But with time and intentional practice, the memory loses its power to ambush you. The wound becomes a scar — still visible, but no longer bleeding.

            A practical approach: when the hurt resurfaces, try this. Acknowledge it fully — "I am still in pain about this." Then name the choice deliberately — "I am choosing not to carry this today." Then ask God to do the part you cannot: "Lord, change my heart where I cannot change it myself." You are not expected to manufacture feelings of warmth. You are asked to release the claim — the right to repayment, the right to hold it over them — and trust that justice and healing are in better hands than yours.
            """,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Ephesians", chapter: 4, verse: 32, text: "Be kind and compassionate to one another, forgiving each other, just as in Christ God forgave you."),
                WellnessContent.LinkedVerse(book: "Colossians", chapter: 3, verse: 13, text: "Bear with each other and forgive one another if any of you has a grievance against someone.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 8. article / addiction — The Science of Habit and Grace
        WellnessContent(
            id: "seed_008",
            type: .article,
            title: "The Science of Habit and Grace",
            description: "Neuroscience confirms what Paul wrote in Romans 7 — the pull of old patterns is real and powerful. This article explores how brain science and grace work together toward freedom.",
            difficulty: .intermediate,
            category: [.addiction],
            tags: ["addiction", "habit", "neuroscience", "freedom", "grace"],
            durationSeconds: 600,
            steps: nil,
            body: """
            "I do not do the good I want to do, but the evil I do not want to do — this I keep on doing." (Romans 7:19)

            Paul wrote those words two thousand years before neuroscience, but modern brain research confirms exactly what he described. The pathways of our old habits — the neural grooves worn deep by repetition — do not disappear when we decide to change. They remain, latent but alive, triggered by the same cues that activated them before. This is why willpower alone rarely wins. The brain is not changed by resolve; it is changed by repetition of a new pattern.

            This is not discouraging news — it is clarifying news. It means that struggling with an old pattern is not a sign that your faith is insufficient. It is a sign that you are human, in a body, in a process of transformation that takes time.

            Grace enters here not as permission to keep sinning but as the power to keep returning. Every time you fall and choose to get back up, every time you confess and receive forgiveness and begin again, you are literally practicing the new neural pathway. The stumble does not erase the progress. Recovery is not linear, and neither is sanctification.

            Community is the most powerful external force for rewiring habit. James 5:16 — "confess your sins to one another" — is not incidental spiritual advice. It is neurologically sound. Shame thrives in secrecy, and secrecy protects old patterns. Honest, safe confession breaks the cycle at its root.

            If you are in a season of fighting a stubborn habit or addiction: get support, be patient with the process, and trust that the same Spirit who raised Christ from the dead is alive in you (Romans 8:11). The work is real. The grace is more real.
            """,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Romans", chapter: 7, verse: 19, text: "For I do not do the good I want to do, but the evil I do not want to do — this I keep on doing."),
                WellnessContent.LinkedVerse(book: "Romans", chapter: 8, verse: 11, text: "The Spirit of him who raised Jesus from the dead is living in you.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 9. prayer / anxiety — Peace in the Storm
        WellnessContent(
            id: "seed_009",
            type: .prayer,
            title: "Peace in the Storm",
            description: "A short prayer for moments when anxiety feels overwhelming — grounded in Jesus calming the sea and His promise that He is present in every storm.",
            difficulty: .beginner,
            category: [.anxiety],
            tags: ["prayer", "anxiety", "peace", "Jesus"],
            durationSeconds: 180,
            steps: nil,
            body: """
            Lord Jesus,

            You spoke to the storm and it obeyed. You looked at waves that terrified experienced sailors and said, "Peace. Be still." And the sea listened.

            Right now my mind feels like that sea — the waves loud, the wind relentless, the horizon lost in the spray. I cannot calm this by my own will. I have tried.

            So I come to You the way the disciples did — not with perfect faith, but with nowhere else to go. I ask You to stand in the bow of this moment and speak to what frightens me.

            Still the racing thoughts.
            Still the imagined catastrophes.
            Still the voice that says everything is falling apart.

            Remind me of what is true: that You are in this boat with me. That You have not fallen asleep to my situation. That the same authority that rules wind and wave is on my side.

            I receive Your peace — not as the world gives, contingent on circumstances being resolved — but as You give, deep and settled beneath the surface of whatever storm is howling.

            Guard my heart. Guard my mind. You are enough.

            Amen.
            """,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Mark", chapter: 4, verse: 39, text: "He got up, rebuked the wind and said to the waves, 'Quiet! Be still!' Then the wind died down and it was completely calm."),
                WellnessContent.LinkedVerse(book: "John", chapter: 14, verse: 27, text: "Peace I leave with you; my peace I give you. I do not give to you as the world gives.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 10. prayer / depression — Psalm 34 Lectio
        WellnessContent(
            id: "seed_010",
            type: .prayer,
            title: "Psalm 34 Lectio Divina",
            description: "Lectio Divina is an ancient practice of slow, prayerful scripture reading. This practice leads you through Psalm 34 — a psalm written from the pit — in four movements.",
            difficulty: .beginner,
            category: [.depression],
            tags: ["prayer", "depression", "lectio-divina", "psalm", "scripture"],
            durationSeconds: 600,
            steps: nil,
            body: """
            Find a quiet space and a still posture. This practice has four movements — take your time in each.

            LECTIO — Read Psalm 34:1-8 slowly, aloud if possible. Let the words land without analysis.
            "I will extol the Lord at all times; his praise will always be on my lips. I will glory in the Lord; let the afflicted hear and rejoice. Glorify the Lord with me; let us exalt his name together. I sought the Lord, and he answered me; he delivered me from all my fears. Those who look to him are radiant; their faces are never covered with shame. This poor man called, and the Lord heard him; he saved him out of all his troubles. The angel of the Lord encamps around those who fear him, and he delivers them. Taste and see that the Lord is good; blessed is the one who takes refuge in him."

            MEDITATIO — Read it again, more slowly. Notice which word or phrase presses against your heart. Don't analyze it. Simply hold it, the way you'd hold something precious and fragile. Sit with it for two minutes.

            ORATIO — Now speak to God from that word or phrase. It might sound like: "Lord, I want to believe You hear me, but I feel very far from that right now." Be honest. This psalm was written from a cave, by a man on the run. God is not startled by honesty.

            CONTEMPLATIO — Let the words go. Rest in silence with God for a few minutes. You don't need to produce anything. Simply be present to the One who is always present to you. He sees you in this valley. He has not turned away.
            """,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 34, verse: 18, text: "The Lord is close to the brokenhearted and saves those who are crushed in spirit."),
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 34, verse: 8, text: "Taste and see that the Lord is good; blessed is the one who takes refuge in him.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 11. prayer / stress — Morning Surrender Prayer
        WellnessContent(
            id: "seed_011",
            type: .prayer,
            title: "Morning Surrender Prayer",
            description: "A prayer to begin each day by releasing control — especially useful in seasons of high stress when the weight of responsibility feels crushing.",
            difficulty: .beginner,
            category: [.stress],
            tags: ["prayer", "stress", "morning", "surrender", "daily"],
            durationSeconds: 240,
            steps: nil,
            body: """
            Father,

            Before this day begins — before the notifications arrive and the calendar opens and the weight of everything settles on my shoulders — I bring it all to You.

            I name what I am carrying:
            The deadlines. The decisions I don't feel equipped to make.
            The relationships that feel strained. The fear that I am not enough for what's being asked of me.
            The things I cannot control, no matter how hard I try.

            I release them. Not because I am indifferent, but because I am trusting You with what is too heavy for me to carry well.

            You are the God who fed Israel in the desert — who provided what was needed, one day at a time. You said "do not worry about tomorrow" not to dismiss my concerns but because You have already seen tomorrow and it is held in Your hands.

            Give me what I need for today: clarity to think, strength to act, grace for the moments I stumble, and wisdom to know the difference between what is mine to carry and what is Yours.

            I am Yours today. Use me well. Keep me grounded. Let me be a source of peace, not pressure, to the people around me.

            Amen.
            """,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Matthew", chapter: 6, verse: 34, text: "Therefore do not worry about tomorrow, for tomorrow will worry about itself."),
                WellnessContent.LinkedVerse(book: "1 Peter", chapter: 5, verse: 7, text: "Cast all your anxiety on him because he cares for you.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 12. prayer / identity — Identity in Christ Affirmations
        WellnessContent(
            id: "seed_012",
            type: .prayer,
            title: "Identity in Christ Affirmations",
            description: "A prayerful recitation of who you are in Christ — a powerful practice for seasons when lies about your worth feel louder than truth.",
            difficulty: .beginner,
            category: [.identity],
            tags: ["prayer", "identity", "affirmations", "worth", "truth"],
            durationSeconds: 240,
            steps: nil,
            body: """
            Read these aloud if you can. Let each one land before you move to the next.

            I am loved — not because of what I have accomplished, but because I am God's child. (John 1:12)

            I am known — fully, completely, without any part of me hidden or disguised. He knows me and still chooses me. (Psalm 139:1-2)

            I am forgiven — the record of my failures has been cancelled, nailed to the cross, taken out of the way. (Colossians 2:14)

            I am not condemned — there is no sentence hanging over me, no debt still owed. I walk free. (Romans 8:1)

            I am being made new — not repaired or patched, but genuinely new. This is not wishful thinking; it is transformation in progress. (2 Corinthians 5:17)

            I am enough — not because of performance, but because the One who made me called His creation good, and calls me His. (Genesis 1:31)

            I am held — in weakness, in confusion, in the moments I cannot hold myself together. His strength is made perfect in my weakness. (2 Corinthians 12:9)

            Lord, where I hear these words as distant or untrue, I ask You to do what I cannot do for myself: make them real to me. Ground my identity in what You say, not in what fear or shame or comparison says. I am Yours.

            Amen.
            """,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Romans", chapter: 8, verse: 1, text: "Therefore, there is now no condemnation for those who are in Christ Jesus."),
                WellnessContent.LinkedVerse(book: "2 Corinthians", chapter: 5, verse: 17, text: "Therefore, if anyone is in Christ, the new creation has come: The old has gone, the new is here!")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 13. meditation / stress — Breath & Psalm 46
        WellnessContent(
            id: "seed_013",
            type: .meditation,
            title: "Breath & Psalm 46",
            description: "A ten-minute breath-synchronized meditation through Psalm 46 — one of scripture's most powerful anchors for seasons of chaos, upheaval, and uncertainty.",
            difficulty: .beginner,
            category: [.stress],
            tags: ["meditation", "stress", "breathing", "psalm", "peace"],
            durationSeconds: 600,
            steps: nil,
            body: nil,
            audioUrl: "https://storage.googleapis.com/amen-wellness-audio/seed_013_breath_psalm46.mp3",
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 46, verse: 1, text: "God is our refuge and strength, an ever-present help in trouble."),
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 46, verse: 10, text: "Be still, and know that I am God.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 14. meditation / sleep — Night Office Meditation
        WellnessContent(
            id: "seed_014",
            type: .meditation,
            title: "Night Office Meditation",
            description: "Drawn from the ancient practice of Compline — the last prayer of the day — this guided meditation helps you release the day and enter rest with trust.",
            difficulty: .beginner,
            category: [.sleep],
            tags: ["meditation", "sleep", "night-prayer", "Compline", "rest"],
            durationSeconds: 720,
            steps: nil,
            body: nil,
            audioUrl: "https://storage.googleapis.com/amen-wellness-audio/seed_014_night_office.mp3",
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 4, verse: 8, text: "In peace I will lie down and sleep, for you alone, Lord, make me dwell in safety."),
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 91, verse: 4, text: "He will cover you with his feathers, and under his wings you will find refuge.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 15. journalPrompt / identity — Who Am I in Christ?
        WellnessContent(
            id: "seed_015",
            type: .journalPrompt,
            title: "Who Am I in Christ?",
            description: "A reflective writing prompt to help you move beyond performance-based identity and anchor yourself in what God says is permanently true about you.",
            difficulty: .beginner,
            category: [.identity],
            tags: ["journal", "identity", "self-worth", "Christ", "truth"],
            durationSeconds: 300,
            steps: nil,
            body: """
            Take a few slow breaths before you write. Ask the Holy Spirit to guide your pen toward honesty.

            PROMPT: The world tells me I am what I achieve, what I own, what people think of me, or how I appear. But when I quiet those voices, who does God say I am?

            Write freely for ten minutes. You might start with:
            — "I know God says I am _______, but I find it hard to believe because..."
            — "The identity I most want to be free from carrying is..."
            — "If I actually believed I was unconditionally loved, I would..."

            After writing, read back what you wrote and underline one true thing about yourself that you want to carry with you today. Speak it aloud. Let it land.

            Closing reflection: "Lord, where the truth of who I am in You feels distant, I ask You to make it near. I am Your child. That is enough."
            """,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Galatians", chapter: 3, verse: 26, text: "So in Christ Jesus you are all children of God through faith."),
                WellnessContent.LinkedVerse(book: "1 John", chapter: 3, verse: 1, text: "See what great love the Father has lavished on us, that we should be called children of God!")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 16. journalPrompt / grief — Letters to Grief
        WellnessContent(
            id: "seed_016",
            type: .journalPrompt,
            title: "Letters to Grief",
            description: "A powerful writing practice used in trauma therapy — writing a letter directly to your grief, then receiving one back. Helps externalize and befriend what you are carrying.",
            difficulty: .intermediate,
            category: [.grief],
            tags: ["journal", "grief", "loss", "writing", "processing"],
            durationSeconds: 600,
            steps: nil,
            body: """
            This practice has two parts. Set aside at least twenty minutes and find a place where you won't be interrupted.

            PART ONE — Write a letter to your grief.
            Begin: "Dear Grief," and write whatever is true. You might be angry at it, exhausted by it, afraid it will never lift, or strangely reluctant to let it go because it is the last connection to what you lost. There are no wrong answers. Write until the page feels lighter than your chest.

            PART TWO — Write a letter from your grief back to you.
            This is harder. Shift your perspective and allow grief to speak. What does it need you to know? What is it protecting? What does it want you to remember about what you loved and lost?

            Many people find that grief, when given a voice, sounds less like an enemy and more like a witness — a testament to love. "I am here because you loved deeply. Do not rush me. But do not let me become your whole story."

            After both letters: place them somewhere you can return to, or burn them as a ritual release. Bring what surfaced to God in prayer. He is not afraid of your grief. He wept at the tomb of His friend (John 11:35). He weeps with you too.
            """,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "John", chapter: 11, verse: 35, text: "Jesus wept."),
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 56, verse: 8, text: "You keep track of all my sorrows. You have collected all my tears in your bottle.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 17. journalPrompt / relationship — What Love Does
        WellnessContent(
            id: "seed_017",
            type: .journalPrompt,
            title: "What Love Does",
            description: "A reflective prompt based on 1 Corinthians 13 — the most precise description of love in scripture. Use it to examine your closest relationships with honesty and grace.",
            difficulty: .beginner,
            category: [.relationship],
            tags: ["journal", "relationships", "love", "1-Corinthians-13", "honesty"],
            durationSeconds: 300,
            steps: nil,
            body: """
            Read 1 Corinthians 13:4-7 slowly before you write:
            "Love is patient, love is kind. It does not envy, it does not boast, it is not proud. It does not dishonor others, it is not self-seeking, it is not easily angered, it keeps no record of wrongs. Love does not delight in evil but rejoices with the truth. It always protects, always trusts, always hopes, always perseveres."

            PROMPT: Pick one relationship — a spouse, a parent, a friend, a sibling — and work through this list honestly.

            Where am I patient in this relationship? Where am I not?
            Where am I kind? Where do I withhold kindness?
            Am I keeping a record of wrongs in this relationship — a running tally of grievances? What would it mean to close that account?
            Where do I struggle to hope for this person, or trust them?

            Write without self-condemnation. The goal is not guilt — it is clarity. Close by asking: "Lord, grow in me the kind of love that this person needs from me. Where I am depleted, fill me. Where I am hardened, soften me."
            """,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "1 Corinthians", chapter: 13, verse: 4, text: "Love is patient, love is kind. It does not envy, it does not boast, it is not proud.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 18. tool / anxiety — Worry Jar Practice
        WellnessContent(
            id: "seed_018",
            type: .tool,
            title: "Worry Jar Practice",
            description: "A tangible tool for anxiety: write worries down, place them in a jar, and give them to God. Physical ritual makes the abstract act of surrendering feel real.",
            difficulty: .beginner,
            category: [.anxiety],
            tags: ["tool", "anxiety", "worry", "surrender", "ritual"],
            durationSeconds: 300,
            steps: [
                "Find a jar or container — any size — and some small slips of paper. Label it: 'God's Jar.'",
                "When a worry surfaces that you cannot resolve right now, write it on a slip of paper. Be specific: 'Will I have enough money this month?' or 'What if she doesn't forgive me?'",
                "Hold the slip for a moment. Acknowledge the worry is real. Then say aloud or silently: 'This is too big for me to carry alone. I give it to You, Lord.'",
                "Fold the slip and place it in the jar. The physical act of releasing it mirrors the internal act of surrender.",
                "Once a week, open the jar. Some worries will have resolved — notice that. Some won't have — pray over those again. This practice builds evidence over time that most of what we fear never comes to pass, and what does come, God meets."
            ],
            body: nil,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "1 Peter", chapter: 5, verse: 7, text: "Cast all your anxiety on him because he cares for you.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 19. tool / addiction — Urge Surfing
        WellnessContent(
            id: "seed_019",
            type: .tool,
            title: "Urge Surfing",
            description: "A mindfulness-based technique for riding the wave of a craving without acting on it. Paired with prayer, it becomes a practice in trusting that urges pass and that you are not helpless.",
            difficulty: .intermediate,
            category: [.addiction],
            tags: ["tool", "addiction", "craving", "mindfulness", "urge-surfing"],
            durationSeconds: 600,
            steps: [
                "When an urge or craving hits, stop and acknowledge it: 'I notice I want _______ right now.' Name it without shame — naming reduces its power.",
                "Rate the urge's intensity from 1-10. Notice: it has a number. It is not infinite.",
                "Breathe slowly and observe the urge as if from a slight distance — a wave approaching the shore. You don't have to fight it. You are going to surf it.",
                "Notice where you feel the urge in your body: tension, heat, restlessness. Keep breathing. Watch as the intensity builds toward a peak — usually between 3-7 minutes — and then begins to subside.",
                "Pray through the ride: 'Lord, I feel this pull. I am not surrendering to it. I am trusting that it will pass, and that Your Spirit in me is stronger than this. Stay with me.' Most urges peak and subside within ten minutes if you don't feed them. Repeat as needed."
            ],
            body: nil,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "1 Corinthians", chapter: 10, verse: 13, text: "No temptation has overtaken you except what is common to mankind. And God is faithful; he will not let you be tempted beyond what you can bear."),
                WellnessContent.LinkedVerse(book: "Romans", chapter: 8, verse: 11, text: "The Spirit of him who raised Jesus from the dead is living in you.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 20. tool / identity — Strengths in Scripture
        WellnessContent(
            id: "seed_020",
            type: .tool,
            title: "Strengths in Scripture",
            description: "An interactive exercise to discover your God-given strengths by mapping your natural gifts to their scriptural affirmation — countering the lie that you have nothing to offer.",
            difficulty: .beginner,
            category: [.identity],
            tags: ["tool", "identity", "strengths", "gifts", "calling"],
            durationSeconds: 480,
            steps: [
                "List three things people have thanked you for, or times when something came naturally to you that seemed hard for others. These are clues to your God-given strengths.",
                "For each strength, ask: 'How might this be a gift, not just a trait?' For example: a gift for listening → 'I carry people's burdens with them' (Galatians 6:2). A gift for seeing problems → 'I am wired for discernment' (1 Kings 3:9).",
                "Search scripture for your strength. Use the concordance in a Bible app. If you are an encourager, look up 'encourage.' If you love mercy, look up 'mercy.' Find one verse that feels like it was written for you.",
                "Write the verse on an index card or lock screen. Read it once each morning this week. You are not just coping with who you are — you are being equipped for something.",
                "Finally, ask: 'Lord, how do You want to use this strength this week?' Look for one small opportunity to offer it. This is the beginning of calling."
            ],
            body: nil,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "1 Corinthians", chapter: 12, verse: 7, text: "Now to each one the manifestation of the Spirit is given for the common good."),
                WellnessContent.LinkedVerse(book: "Ephesians", chapter: 2, verse: 10, text: "For we are God's handiwork, created in Christ Jesus to do good works, which God prepared in advance for us to do.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 21. meditation / grief — Lament and Release
        WellnessContent(
            id: "seed_021",
            type: .meditation,
            title: "Lament and Release",
            description: "A guided meditation for grief that holds space for sorrow without rushing toward resolution — drawn from the psalms of lament and the theology of Holy Saturday.",
            difficulty: .intermediate,
            category: [.grief],
            tags: ["meditation", "grief", "lament", "loss", "sacred-pause"],
            durationSeconds: 600,
            steps: nil,
            body: nil,
            audioUrl: "https://storage.googleapis.com/amen-wellness-audio/seed_021_lament_release.mp3",
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Lamentations", chapter: 3, verse: 22, text: "Because of the Lord's great love we are not consumed, for his compassions never fail."),
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 30, verse: 5, text: "Weeping may stay for the night, but rejoicing comes in the morning.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 22. tool / depression — Behavioral Activation Micro-Steps
        WellnessContent(
            id: "seed_022",
            type: .tool,
            title: "Behavioral Activation Micro-Steps",
            description: "One of the most evidence-based tools for depression: small acts of engagement that rebuild momentum when everything feels impossible. Anchored in the truth that God works through ordinary moments.",
            difficulty: .beginner,
            category: [.depression],
            tags: ["tool", "depression", "behavioral-activation", "momentum", "small-steps"],
            durationSeconds: 300,
            steps: [
                "Choose one micro-action you can do in the next ten minutes — not a goal, just an action. Walk to the window. Drink a glass of water. Step outside for two minutes. The smaller, the better.",
                "Before you do it, say: 'Lord, I am doing this one small thing. Meet me in it.' Faith does not require a dramatic breakthrough — it can start in a glass of water.",
                "Do the action. Notice what you feel — even if it's nothing. Notice that you did it. That matters.",
                "Add one more micro-action to your day. Write it down. Then do it. You are not trying to fix everything — you are practicing being in your life, one moment at a time.",
                "At the end of the day, name two things — however small — that happened. Depression lies and says nothing happened, nothing mattered. The list is evidence against the lie."
            ],
            body: nil,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Zechariah", chapter: 4, verse: 10, text: "Do not despise these small beginnings, for the Lord rejoices to see the work begin."),
                WellnessContent.LinkedVerse(book: "1 Kings", chapter: 19, verse: 5, text: "Then he lay down under the bush and fell asleep. All at once an angel touched him and said, 'Get up and eat.'")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 23. journalPrompt / addiction — What Am I Truly Hungry For?
        WellnessContent(
            id: "seed_023",
            type: .journalPrompt,
            title: "What Am I Truly Hungry For?",
            description: "Addiction is often misplaced hunger — a search for something real met by something that can't satisfy. This prompt helps you trace the craving back to its roots.",
            difficulty: .intermediate,
            category: [.addiction],
            tags: ["journal", "addiction", "hunger", "root-cause", "desire"],
            durationSeconds: 480,
            steps: nil,
            body: """
            Augustine wrote: "Our heart is restless, until it repose in Thee." Every addiction begins somewhere — usually in a legitimate need that was never met, or a pain that never found a voice.

            This prompt asks you to go deeper than the behavior.

            PROMPT: Think about the last time the craving or compulsion was strong. Before you write about the behavior, write about what was happening in you.

            — What were you feeling in the hour before the urge hit? (lonely? overwhelmed? bored? ashamed? invisible?)
            — What did the behavior promise to give you? (comfort? escape? connection? relief? a sense of control?)
            — What would it mean if that underlying need were actually met — by God, by community, by something real and lasting?

            Write freely. Then read back what you wrote and ask: "Lord, this is what I am truly hungry for. I cannot meet this need through _______ . Can You meet it?" 

            You don't need to have an answer immediately. The asking is the beginning.
            """,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "John", chapter: 4, verse: 14, text: "Whoever drinks the water I give them will never thirst. Indeed, the water I give them will become in them a spring of water welling up to eternal life."),
                WellnessContent.LinkedVerse(book: "Psalms", chapter: 42, verse: 1, text: "As the deer pants for streams of water, so my soul pants for you, my God.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        ),

        // 24. prayer / relationship — A Prayer for a Fractured Relationship
        WellnessContent(
            id: "seed_024",
            type: .prayer,
            title: "Prayer for a Fractured Relationship",
            description: "When a relationship is broken and reconciliation feels impossible, this prayer invites God into the gap — making space for healing without forcing premature resolution.",
            difficulty: .beginner,
            category: [.relationship],
            tags: ["prayer", "relationships", "reconciliation", "healing", "conflict"],
            durationSeconds: 300,
            steps: nil,
            body: """
            Lord,

            There is a fracture between me and ____________.
            I do not know if it can be repaired. I am not sure I am ready for it to be.
            But I bring this broken thing to You because I cannot carry it well on my own.

            Protect me from bitterness — it is a poison that takes root quietly and grows where grief and anger have no outlet. Help me grieve this honestly rather than harden.

            Protect me from false peace — the kind that pretends nothing happened and leaves the wound unaddressed beneath a polished surface.

            Where reconciliation is possible and right, prepare both of us for it. Soften what needs to be softened. Give courage for the hard conversation. Give grace for the awkward repair.

            Where reconciliation is not yet possible — or where it would not be safe — help me forgive anyway, from a distance if necessary. Forgiveness for my sake, and for Yours. Not because what happened was acceptable, but because I refuse to let it own me.

            Hold ____________ too, Lord. Whatever is broken in them that contributed to this — I release that to You. You see them more clearly than I do.

            Heal what I cannot heal. Move in both of us in ways I can't manufacture.

            I trust You with this.

            Amen.
            """,
            audioUrl: nil,
            videoUrl: nil,
            linkedVerses: [
                WellnessContent.LinkedVerse(book: "Romans", chapter: 12, verse: 18, text: "If it is possible, as far as it depends on you, live at peace with everyone."),
                WellnessContent.LinkedVerse(book: "Matthew", chapter: 5, verse: 9, text: "Blessed are the peacemakers, for they will be called children of God.")
            ],
            engagementViewCount: 0,
            engagementSavedCount: 0,
            engagementHelpfulCount: 0,
            createdAt: nil,
            guardianModerated: true
        )
    ]
}

///
/// FruitOfSpiritBannerView.swift
/// AMENAPP
///
/// Dark-card banner (consistent with app design) with a rich interactive full-screen
/// Fruit of the Spirit experience: scroll exploration, teachings, and a biblical quiz.
///

import SwiftUI

// MARK: - Data Model

struct FruitOfSpirit: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let greekWord: String
    let greekPronunciation: String
    let accentColor: Color
    let scripture: String
    let scriptureRef: String
    let secondaryScripture: String
    let secondaryScriptureRef: String
    let shortDefinition: String
    let fullTeaching: String
    let historicalContext: String
    let dailyPractice: String
    let reflectionQuestion: String
    let prayerPrompt: String
    let opposites: [String]   // What this fruit overcomes
    let relatedFruits: [String]
}

private let allFruits: [FruitOfSpirit] = [
    FruitOfSpirit(
        name: "Love",
        emoji: "❤️",
        greekWord: "Agápē",
        greekPronunciation: "ah-GAH-pay",
        accentColor: Color(red: 0.95, green: 0.32, blue: 0.42),
        scripture: "Love is patient, love is kind. It does not envy, it does not boast, it is not proud. It does not dishonor others, it is not self-seeking.",
        scriptureRef: "1 Corinthians 13:4–5",
        secondaryScripture: "We love because he first loved us.",
        secondaryScriptureRef: "1 John 4:19",
        shortDefinition: "Unconditional, self-giving love rooted in God's own nature.",
        fullTeaching: "Agápē is the highest form of love in the Greek language — the love that God Himself embodies. Unlike eros (romantic love) or philia (friendship), agápē is a decision of the will, not a feeling. It loves the unlovable, forgives the unforgivable, and gives without expectation of return.\n\nPaul's famous passage in 1 Corinthians 13 lists 15 attributes of agápē — each one a behavior, not an emotion. This tells us something profound: love is something you do, not just something you feel. When Jesus commanded us to \"love one another as I have loved you\" (John 13:34), He was calling us to action.\n\nThis fruit grows as we remain connected to the Vine. The more we understand and receive God's love for us, the more naturally we love others with that same quality of love.",
        historicalContext: "In the first-century Roman world, agápē was a rare word — almost never used in classical Greek literature. The New Testament writers chose it precisely because it had no worldly connotation, making it the perfect word for a kind of love that the world had never seen before. Early Christians were so known for their love that the philosopher Tertullian recorded pagans saying: \"See how they love one another.\"",
        dailyPractice: "Choose one person today who is difficult to love. Do one specific, concrete act of kindness for them — not because they deserve it, but because you are practicing agápē.",
        reflectionQuestion: "When was the last time your love for someone cost you something? What did it cost you, and what did you learn about God through it?",
        prayerPrompt: "Lord, Your love for me is the foundation of everything. Help me today to love not with my own limited capacity but as a channel of Your endless agápē. Show me one person who needs to feel that love through me today.",
        opposites: ["Hatred", "Envy", "Pride", "Self-seeking"],
        relatedFruits: ["Kindness", "Goodness", "Gentleness"]
    ),
    FruitOfSpirit(
        name: "Joy",
        emoji: "✨",
        greekWord: "Chará",
        greekPronunciation: "kha-RAH",
        accentColor: Color(red: 0.98, green: 0.78, blue: 0.18),
        scripture: "You make known to me the path of life; in your presence there is fullness of joy; at your right hand are pleasures forevermore.",
        scriptureRef: "Psalm 16:11",
        secondaryScripture: "Rejoice in the Lord always; again I will say, rejoice.",
        secondaryScriptureRef: "Philippians 4:4",
        shortDefinition: "Deep, settled delight rooted in God's presence — independent of circumstances.",
        fullTeaching: "Chará (joy) is fundamentally different from happiness. Happiness is circumstantial — it rises and falls with what happens to us. Joy is a deep, bedrock confidence that God is good and in control, regardless of what life looks like on the surface.\n\nNotice that Paul commands the Philippians to \"rejoice always\" — and he wrote those words from prison. This tells us that joy is not a spontaneous emotion but a practiced discipline. It is choosing to fix your eyes on what is eternal when everything temporal is falling apart.\n\nJesus told His disciples these things so that \"my joy may be in you and that your joy may be complete\" (John 15:11). Joy is not something we manufacture — it is something Christ deposits in us as we abide in Him. The fruit grows on the vine, not apart from it.",
        historicalContext: "The early church was marked by extraordinary joy despite severe persecution. Acts records the apostles leaving floggings \"rejoicing that they had been counted worthy of suffering\" (Acts 5:41). This paradox of suffering and joy was so alien to the Roman world that it served as a powerful witness. The Greek concept of eudaimonia (happiness) depended on favorable circumstances; chará declared that the Christian had a happiness that no emperor could take away.",
        dailyPractice: "Start a 'Joy Journal.' Each morning, write three specific things you're grateful to God for — not generic blessings, but specific moments from the past 24 hours where you saw God's hand. Review it when circumstances are hard.",
        reflectionQuestion: "What is currently threatening your joy? Now ask: is that thing bigger than God's goodness? What would it look like to have joy in the middle of it?",
        prayerPrompt: "Father, I confess I have looked for joy in the wrong places. Today I choose to anchor my joy in who You are, not in what I have. Fill me with the joy that only Your presence can give — a joy no circumstance can steal.",
        opposites: ["Despair", "Anxiety", "Complaining", "Cynicism"],
        relatedFruits: ["Peace", "Faithfulness"]
    ),
    FruitOfSpirit(
        name: "Peace",
        emoji: "🕊️",
        greekWord: "Eirḗnē",
        greekPronunciation: "ay-RAY-nay",
        accentColor: Color(red: 0.38, green: 0.72, blue: 0.92),
        scripture: "And the peace of God, which surpasses all understanding, will guard your hearts and your minds in Christ Jesus.",
        scriptureRef: "Philippians 4:7",
        secondaryScripture: "Peace I leave with you; my peace I give to you. Not as the world gives do I give to you. Let not your hearts be troubled, neither let them be afraid.",
        secondaryScriptureRef: "John 14:27",
        shortDefinition: "Wholeness and harmony — an internal quietness that guards the heart.",
        fullTeaching: "Eirḗnē is the Greek equivalent of the Hebrew shalom — a word that means far more than the absence of conflict. Shalom/eirḗnē means wholeness, completeness, everything in its right place, the way things were meant to be.\n\nPaul says this peace \"surpasses all understanding\" — meaning it doesn't make logical sense. How can you be at peace when your diagnosis is bad, your finances are failing, your relationship is broken? Because this peace is not based on your assessment of the situation; it is based on the character of God.\n\nThe key to accessing this peace is found in Philippians 4:6: bring every anxiety to God in prayer. The exchange is: your worry for His peace. This is not passive fatalism but active trust — naming your fears before God and choosing to leave them in His hands.",
        historicalContext: "In the Roman world, 'pax' (peace) was enforced by military power — the Pax Romana. It was the peace of domination. The Christian eirḗnē was radically different: not enforced from outside by threat, but given from within by the Holy Spirit. This internal peace was a direct counter-cultural statement that true shalom could not be given or taken by Caesar.",
        dailyPractice: "Practice the 'exchange prayer': When anxiety rises, stop and literally say out loud: \"Lord, I give You [name the specific worry]. I receive Your peace in exchange.\" Do this each time the worry returns.",
        reflectionQuestion: "What is one thing you are carrying today that God has never asked you to carry alone? What would it feel like to genuinely hand it to Him?",
        prayerPrompt: "Prince of Peace, I bring You every anxious thought pressing on my mind right now. I name them before You. I choose to trust that You hold each one. Stand guard over my mind today. Let Your eirḗnē, which I cannot manufacture, fill the space where my worry was.",
        opposites: ["Anxiety", "Fear", "Conflict", "Turmoil"],
        relatedFruits: ["Joy", "Patience", "Self-Control"]
    ),
    FruitOfSpirit(
        name: "Patience",
        emoji: "⏳",
        greekWord: "Makrothymía",
        greekPronunciation: "mah-kroh-thoo-MEE-ah",
        accentColor: Color(red: 0.62, green: 0.48, blue: 0.88),
        scripture: "Be completely humble and gentle; be patient, bearing with one another in love.",
        scriptureRef: "Ephesians 4:2",
        secondaryScripture: "But if we hope for what we do not yet have, we wait for it patiently.",
        secondaryScriptureRef: "Romans 8:25",
        shortDefinition: "Long-suffering endurance — the ability to bear difficulty and provocation without giving up.",
        fullTeaching: "Makrothymía literally means 'long-tempered' — the opposite of short-tempered. It is composed of makros (long) and thymos (passion/anger). This fruit is the capacity to take a long time before your passion rises into reaction.\n\nThere are two dimensions of biblical patience: patience with people and patience with circumstances. The first is bearing with difficult, frustrating, or hurtful people without retaliating. The second is enduring painful, delayed, or disappointing circumstances without despairing.\n\nGod Himself is described as 'makrothymos' — He is patient with us (2 Peter 3:9), not wanting anyone to perish. Our patience toward others is a reflection of God's patience toward us. When we are tempted to give up on someone, we remember how long God has been patient with us.",
        historicalContext: "The word makrothymía appears frequently in the Septuagint (Greek Old Testament) to describe God's response to Israel's repeated unfaithfulness. This is the God who waited centuries for His people to return, who sent prophet after prophet before sending His Son. Understanding God's own makrothymía toward Israel and toward us puts human impatience in stark perspective.",
        dailyPractice: "Identify one person or situation that has been testing your patience. Write one specific way God has been patient with you in a similar area. Use that as fuel for extending the same patience you've received.",
        reflectionQuestion: "Is there a person or situation where you have been setting your own timeline rather than trusting God's? What would it look like to surrender that timeline today?",
        prayerPrompt: "Lord, I confess that I want things on my schedule. Grow in me the long-temperedness that You have shown me. Help me to bear with [name the person or situation] the way You have borne with me.",
        opposites: ["Anger", "Impatience", "Retaliation", "Despair"],
        relatedFruits: ["Peace", "Gentleness", "Faithfulness"]
    ),
    FruitOfSpirit(
        name: "Kindness",
        emoji: "🌿",
        greekWord: "Chrēstótēs",
        greekPronunciation: "kray-STOH-tays",
        accentColor: Color(red: 0.28, green: 0.78, blue: 0.52),
        scripture: "Be kind and compassionate to one another, forgiving each other, just as in Christ God forgave you.",
        scriptureRef: "Ephesians 4:32",
        secondaryScripture: "Or do you show contempt for the riches of his kindness, forbearance and patience, not realizing that God's kindness is intended to lead you to repentance?",
        secondaryScriptureRef: "Romans 2:4",
        shortDefinition: "Practical goodness that makes others feel safe — kindness that acts and costs something.",
        fullTeaching: "Chrēstótēs is best understood as 'usefulness' — a kindness that is practically helpful, not merely warm in feeling. It is the quality that makes someone pleasant, gentle, and serviceable to others.\n\nNotice Paul's argument in Romans 2:4: God's kindness leads us to repentance — not His wrath, not His judgment, but His kindness. This gives us a profound theological model: kindness is evangelistic. The way we treat people — especially people who don't deserve it — is a proclamation of the gospel.\n\nChrēstótēs is often paired in the New Testament with goodness (agathōsýnē). If goodness is the inner quality of being good, chrēstótēs is the outward expression of it toward people. It has hands and feet. It shows up in small moments: the tone of voice, the generous interpretation, the practical help offered without being asked.",
        historicalContext: "In the Greco-Roman world, chrēstótēs was considered a civic virtue — the quality of a good citizen who served their community. The Christians took this concept and supercharged it: kindness was no longer just civic duty but a reflection of the divine character. The church became known for radical kindness — caring for orphans, widows, and plague victims when the pagan world abandoned them.",
        dailyPractice: "Perform one 'invisible act of kindness' today — something helpful for someone where you won't receive any credit or even a thank-you. Notice how it feels to do good for its own sake.",
        reflectionQuestion: "Is there someone in your life you have been cold, indifferent, or harsh toward? What specific act of chrēstótēs could you offer them this week?",
        prayerPrompt: "Father, make me a person whose presence makes others feel safe and valued. Open my eyes to the small opportunities for kindness I walk past every day. Let my kindness be a signpost pointing to Yours.",
        opposites: ["Harshness", "Indifference", "Cruelty", "Contempt"],
        relatedFruits: ["Love", "Goodness", "Gentleness"]
    ),
    FruitOfSpirit(
        name: "Goodness",
        emoji: "🌟",
        greekWord: "Agathōsýnē",
        greekPronunciation: "ah-gah-tho-SOO-nay",
        accentColor: Color(red: 0.98, green: 0.62, blue: 0.18),
        scripture: "For we are God's handiwork, created in Christ Jesus to do good works, which God prepared in advance for us to do.",
        scriptureRef: "Ephesians 2:10",
        secondaryScripture: "And do not forget to do good and to share with others, for with such sacrifices God is pleased.",
        secondaryScriptureRef: "Hebrews 13:16",
        shortDefinition: "Moral uprightness and virtue expressed through tangible good deeds.",
        fullTeaching: "Agathōsýnē is the quality of being genuinely, thoroughly good — not in a soft or passive sense, but with a certain moral energy and forcefulness. Unlike chrēstótēs (kindness), which is gentle and winsome, agathōsýnē has a backbone. It will confront sin, correct error, and sometimes say the hard thing.\n\nJesus \"went around doing good\" (Acts 10:38) — and His goodness was not always comfortable. It overturned tables in the temple. It challenged religious hypocrisy. It healed on the Sabbath when the law said not to. True goodness is not people-pleasing; it is God-pleasing.\n\nWe are told in Ephesians that we were \"created in Christ Jesus to do good works, which God prepared in advance.\" This is striking: your good works were ordained before you were born. The fruit of goodness is not improvised — it grows as you walk in step with the Spirit who already knows the path.",
        historicalContext: "The Stoic philosophers placed goodness as the highest virtue — but their goodness was cold, self-sufficient, and detached from relationship. The Christian agathōsýnē was entirely different: it flowed from a relationship with a good God, was energized by the Holy Spirit, and was directed toward others. It was warm, active, and relational. This contrast made Christian virtue distinctly compelling to the ancient world.",
        dailyPractice: "Ask God this morning: 'What good work have You prepared for me today?' Then stay alert throughout your day for the answer. Write it down when you find it.",
        reflectionQuestion: "Is there a good work you know God has called you to but you have been postponing? What is standing between you and doing it?",
        prayerPrompt: "Father, You created me for good works. Don't let me waste the works You prepared before I was born. Give me the moral courage of Your goodness — the kind that sometimes disrupts, challenges, and costs, but always honors You.",
        opposites: ["Wickedness", "Moral cowardice", "Passivity", "People-pleasing"],
        relatedFruits: ["Love", "Kindness", "Faithfulness"]
    ),
    FruitOfSpirit(
        name: "Faithfulness",
        emoji: "🔑",
        greekWord: "Pístis",
        greekPronunciation: "PEE-stis",
        accentColor: Color(red: 0.28, green: 0.48, blue: 0.92),
        scripture: "His master replied, 'Well done, good and faithful servant! You have been faithful with a few things; I will put you in charge of many things.'",
        scriptureRef: "Matthew 25:21",
        secondaryScripture: "Now it is required that those who have been given a trust must prove faithful.",
        secondaryScriptureRef: "1 Corinthians 4:2",
        shortDefinition: "Trustworthy reliability — being someone others can count on completely.",
        fullTeaching: "Pístis (faith/faithfulness) carries a double meaning: it is both the faith we place in God and the faithfulness God produces in us. As a fruit of the Spirit, it refers primarily to the latter — the quality of being utterly reliable, trustworthy, and consistent.\n\nThe parable of the talents reveals God's economy of faithfulness: those who are faithful in small things are entrusted with more. This turns mundane faithfulness into something profound. The meeting you keep, the promise you honor, the job you do when no one is watching — these are not small things to God.\n\nJesus is called 'pistos' (faithful) throughout Revelation — the faithful and true witness (3:14). Our faithfulness is a participation in His character. Every time we follow through, keep our word, or show up consistently, we are reflecting something true about God to the world.",
        historicalContext: "In the ancient world, pístis was the foundation of commercial and civic life — without reliable people, trade and government collapsed. Christians took this everyday virtue and gave it a vertical dimension: we are faithful to people because God is faithful to us, and because our faithfulness is ultimately an act of worship. The early church deacons and elders were required above all else to be 'pistos' — faithful, trustworthy people.",
        dailyPractice: "List three commitments you have made (to God, to people, to yourself) that have been slipping. Choose one and take a concrete step to honor it today. Faithfulness is rebuilt one kept promise at a time.",
        reflectionQuestion: "Where in your life has God given you a small trust that you have been treating casually? What would change if you treated it as preparation for something greater?",
        prayerPrompt: "Lord, You are eternally faithful — Your mercies are new every morning. Form that same faithful character in me. Help me be the kind of person whose yes means yes and whose word can be trusted. Let my faithfulness in the hidden things be an act of worship.",
        opposites: ["Unreliability", "Inconsistency", "Broken promises", "Distrust"],
        relatedFruits: ["Goodness", "Self-Control", "Patience"]
    ),
    FruitOfSpirit(
        name: "Gentleness",
        emoji: "🌸",
        greekWord: "Praýtēs",
        greekPronunciation: "prah-OO-tays",
        accentColor: Color(red: 0.92, green: 0.48, blue: 0.72),
        scripture: "Take my yoke upon you, and learn from me, for I am gentle and lowly in heart, and you will find rest for your souls.",
        scriptureRef: "Matthew 11:29",
        secondaryScripture: "Let your gentleness be evident to all. The Lord is near.",
        secondaryScriptureRef: "Philippians 4:5",
        shortDefinition: "Meekness — power fully submitted to God and exercised with wisdom and restraint.",
        fullTeaching: "Praýtēs is one of the most misunderstood words in the New Testament. It is commonly translated 'meekness' and assumed to mean weakness or timidity. Nothing could be further from the truth.\n\nIn classical Greek, praýtēs was used to describe a wild horse that had been tamed. The horse lost none of its strength — it simply came under the control of its rider. Meekness is therefore strength under control: having full power available but choosing to deploy it with wisdom, restraint, and submission to God.\n\nJesus called Himself 'praus' (gentle/meek) — and yet He was not weak. He cleared the temple, confronted Pharisees, and faced crucifixion without flinching. His gentleness was the opposite of weakness: it was perfect power perfectly controlled. When we develop praýtēs, we stop reacting and start responding — we hold our strength in open hands before God.",
        historicalContext: "The beatitude 'Blessed are the meek, for they will inherit the earth' (Matthew 5:5) would have shocked Jesus's Jewish audience, who expected the Messiah to violently overthrow Rome. Jesus was redefining power entirely: the ones who would inherit the earth were not the militarily strong but those whose strength was submitted to God. This was a revolutionary inversion of the world's power structure.",
        dailyPractice: "Before you respond to a difficult situation or person today, pause for 10 seconds and ask: 'What would a gentle, Spirit-led response look like here?' Practice responding rather than reacting.",
        reflectionQuestion: "Is there an area of your life where you tend to respond with force, harshness, or defensiveness? What do you think is underneath that response? What would praýtēs look like there?",
        prayerPrompt: "Jesus, You described Yourself as gentle and humble in heart — and You invited tired, burdened people to learn from You. I want to learn. Soften the hard places in me. Help me hold my strength in open hands before You today.",
        opposites: ["Harshness", "Aggressiveness", "Defensiveness", "Pride"],
        relatedFruits: ["Patience", "Kindness", "Love"]
    ),
    FruitOfSpirit(
        name: "Self-Control",
        emoji: "⚔️",
        greekWord: "Egkráteia",
        greekPronunciation: "eng-KRAH-tay-ah",
        accentColor: Color(red: 0.22, green: 0.22, blue: 0.28),
        scripture: "For the Spirit God gave us does not make us timid, but gives us power, love and self-discipline.",
        scriptureRef: "2 Timothy 1:7",
        secondaryScripture: "Everyone who competes in the games goes into strict training. They do it to get a crown that will not last, but we do it to get a crown that will last forever.",
        secondaryScriptureRef: "1 Corinthians 9:25",
        shortDefinition: "Mastery over one's appetites and impulses through the Spirit's power.",
        fullTeaching: "Egkráteia comes from kratos (strength, dominion) — it means having dominion over yourself. It is the last fruit listed in Galatians 5:22-23, and perhaps the most necessary for all the others to flourish. Without self-control, patience collapses under pressure, gentleness gives way to outbursts, and faithfulness is abandoned when it becomes costly.\n\nCrucially, self-control in the New Testament is not achieved through human willpower alone. Paul frames it as a gift of the Spirit in 2 Timothy 1:7. The Greek athletes trained with strict discipline — but their crown was perishable. We pursue egkráteia for an eternal crown, fueled by a power that is not our own.\n\nPaul's athletic metaphor in 1 Corinthians 9 is instructive: self-control requires training, practice, and intentional effort. The Spirit gives the power; we provide the cooperation. This is the dance of sanctification — not striving alone, not passive waiting, but active, Spirit-dependent discipline.",
        historicalContext: "Greek philosophy prized egkráteia highly — Socrates, Plato, and the Stoics all saw it as the foundational virtue. But for them, self-control was achieved through reason conquering desire — a purely human achievement of great effort. Paul's radical reframing was that egkráteia is a gift of the Holy Spirit. It is not what we achieve but what God produces in us as we cooperate with Him. This completely changed the basis and the character of the virtue.",
        dailyPractice: "Identify one area where your flesh consistently pulls against the Spirit (phone use, eating habits, anger, etc.). Create one small, specific structure to support self-control in that area this week. Structures support disciplines.",
        reflectionQuestion: "Where do you most need the Spirit's power for self-control right now? Have you been trying to manage this area in your own strength? What would it look like to bring the Holy Spirit into it explicitly?",
        prayerPrompt: "Holy Spirit, I cannot do this in my own strength — and I stop trying to. I need Your power for [name the area]. Fill me with the egkráteia that comes from You. Train me in the disciplines that help me cooperate with Your work in me.",
        opposites: ["Impulsiveness", "Addiction", "Excess", "Undisciplined living"],
        relatedFruits: ["Faithfulness", "Peace", "Patience"]
    )
]

// MARK: - Quiz Data

struct FruitQuizQuestion: Identifiable {
    let id = UUID()
    let question: String
    let options: [String]
    let correctIndex: Int
    let explanation: String
    let fruitName: String
}

private let quizQuestions: [FruitQuizQuestion] = [
    // MARK: Love (3 questions)
    FruitQuizQuestion(
        question: "Which Greek word for love describes God's unconditional, self-giving love?",
        options: ["Eros", "Philia", "Agápē", "Storge"],
        correctIndex: 2,
        explanation: "Agápē is the highest form of love — unconditional and self-giving. It's the love God has for us and calls us to have for one another.",
        fruitName: "Love"
    ),
    FruitQuizQuestion(
        question: "In 1 Corinthians 13, Paul lists how many attributes of agápē?",
        options: ["7", "10", "15", "12"],
        correctIndex: 2,
        explanation: "Paul lists 15 specific behaviors of agápē in 1 Corinthians 13. Each is an action, not a feeling — showing that love is something you choose to do.",
        fruitName: "Love"
    ),
    FruitQuizQuestion(
        question: "What did the pagan philosopher Tertullian record outsiders saying about early Christians?",
        options: ["'See how they pray'", "'See how they love one another'", "'See how they give'", "'See how they suffer'"],
        correctIndex: 1,
        explanation: "'See how they love one another' — the agápē of the early church was so unusual in the Roman world that it served as a powerful witness to the truth of the Gospel.",
        fruitName: "Love"
    ),

    // MARK: Joy (3 questions)
    FruitQuizQuestion(
        question: "Paul wrote \"Rejoice in the Lord always\" from where?",
        options: ["A palace", "A prison", "A synagogue", "A mountain"],
        correctIndex: 1,
        explanation: "Paul wrote Philippians from prison. His joy was not based on his circumstances — it was rooted in God's presence. True chará transcends situations.",
        fruitName: "Joy"
    ),
    FruitQuizQuestion(
        question: "According to Psalm 16:11, fullness of joy is found where?",
        options: ["In answered prayer", "In God's presence", "In community", "In obedience"],
        correctIndex: 1,
        explanation: "Psalm 16:11 says 'in your presence there is fullness of joy.' Joy is not a program or discipline first — it flows from dwelling in God's presence.",
        fruitName: "Joy"
    ),
    FruitQuizQuestion(
        question: "In Acts 5, after being flogged by the Sanhedrin, what did the apostles do?",
        options: ["Wept and prayed", "Left rejoicing", "Hid in fear", "Appealed to Caesar"],
        correctIndex: 1,
        explanation: "Acts 5:41 records they left 'rejoicing that they had been counted worthy of suffering.' This paradox of suffering and joy was a powerful witness to the Roman world.",
        fruitName: "Joy"
    ),

    // MARK: Peace (3 questions)
    FruitQuizQuestion(
        question: "The Greek word eirḗnē (peace) corresponds to which Hebrew concept?",
        options: ["Torah", "Shalom", "Hesed", "Kabod"],
        correctIndex: 1,
        explanation: "Eirḗnē is the Greek equivalent of shalom — meaning wholeness, completeness, and everything in its right place. It is far more than the absence of conflict.",
        fruitName: "Peace"
    ),
    FruitQuizQuestion(
        question: "In Philippians 4:6, what does Paul command believers to do with their anxieties?",
        options: ["Ignore them", "Share them with friends", "Bring them to God in prayer", "Fight them with Scripture"],
        correctIndex: 2,
        explanation: "Paul says to 'present your requests to God' with thanksgiving. The exchange is: your anxiety for God's peace, which 'surpasses all understanding' (v. 7).",
        fruitName: "Peace"
    ),
    FruitQuizQuestion(
        question: "How did the 'Pax Romana' (Roman peace) differ from the Christian eirḗnē?",
        options: ["Pax Romana was spiritual", "Pax Romana was enforced by military power from outside", "Eirḗnē required sacrifice", "They were the same concept"],
        correctIndex: 1,
        explanation: "Pax Romana was enforced by military threat from outside. Christian eirḗnē was given by the Holy Spirit from within — a peace that no emperor could give or take away.",
        fruitName: "Peace"
    ),

    // MARK: Patience (3 questions)
    FruitQuizQuestion(
        question: "Makrothymía (patience) literally means...",
        options: ["Strong faith", "Long-tempered", "Deep peace", "Inner strength"],
        correctIndex: 1,
        explanation: "Makros means 'long' and thymos means 'passion/anger.' Being makrothymos means taking a long time before your passion rises into reaction — the opposite of being short-tempered.",
        fruitName: "Patience"
    ),
    FruitQuizQuestion(
        question: "In Romans 8:25, what does Paul say we do while hoping for what we don't yet have?",
        options: ["We pray without ceasing", "We wait for it patiently", "We trust God's timing", "We study the Scriptures"],
        correctIndex: 1,
        explanation: "Romans 8:25: 'if we hope for what we do not yet have, we wait for it patiently.' Patience is the posture of hope — it expects the promise while enduring the delay.",
        fruitName: "Patience"
    ),
    FruitQuizQuestion(
        question: "Which patriarch is held up in James 5:11 as an example of patient endurance?",
        options: ["Abraham", "Moses", "Job", "David"],
        correctIndex: 2,
        explanation: "James 5:11 says 'you have heard of Job's perseverance.' Job endured extreme suffering without abandoning God — he is the biblical icon of patient endurance through trial.",
        fruitName: "Patience"
    ),

    // MARK: Kindness (3 questions)
    FruitQuizQuestion(
        question: "According to Romans 2:4, what is intended to lead us to repentance?",
        options: ["God's wrath", "God's judgment", "God's kindness", "God's commands"],
        correctIndex: 2,
        explanation: "Paul says it's God's kindness (chrēstótēs) that leads to repentance — not His wrath. This tells us that kindness has incredible power to soften hearts.",
        fruitName: "Kindness"
    ),
    FruitQuizQuestion(
        question: "The Greek word chrēstótēs shares its root with which name?",
        options: ["Christos (Christ)", "Chronos (time)", "Chaos", "Charis (grace)"],
        correctIndex: 0,
        explanation: "Chrēstótēs and Christos share the same Greek root. Early pagans often confused 'Christian' with 'kind one' — a happy mix-up that pointed to what the church should be known for.",
        fruitName: "Kindness"
    ),
    FruitQuizQuestion(
        question: "In Luke 10, the Good Samaritan exemplifies kindness by...",
        options: ["Giving money to the temple", "Crossing cultural barriers to help a stranger", "Preaching to the injured man", "Reporting the attack to authorities"],
        correctIndex: 1,
        explanation: "The Samaritan crossed deeply hostile ethnic and religious lines to help a Jewish stranger. Jesus uses this story to define 'neighbor' — and to show that kindness has no natural boundary.",
        fruitName: "Kindness"
    ),

    // MARK: Goodness (3 questions)
    FruitQuizQuestion(
        question: "Goodness (agathōsýnē) differs from kindness in that it...",
        options: ["Is softer and gentler", "Has moral backbone and can confront", "Is only internal", "Requires no action"],
        correctIndex: 1,
        explanation: "While kindness is gentle and winsome, goodness has moral energy and will confront sin and error. Jesus 'went around doing good' — and that included overturning tables.",
        fruitName: "Goodness"
    ),
    FruitQuizQuestion(
        question: "In Acts 10:38, how is Jesus' ministry summarized?",
        options: ["He taught in the synagogues", "He healed the sick only", "He went around doing good", "He preached the kingdom"],
        correctIndex: 2,
        explanation: "Acts 10:38: 'he went around doing good and healing all who were under the power of the devil.' Goodness (agathōsýnē) is active — it moves toward need and opposes evil.",
        fruitName: "Goodness"
    ),
    FruitQuizQuestion(
        question: "The prophet Micah summarizes what God requires in three things. One of them is...",
        options: ["To sacrifice daily", "To love goodness", "To follow the Law perfectly", "To build the temple"],
        correctIndex: 1,
        explanation: "Micah 6:8: 'to act justly and to love mercy and to walk humbly with your God.' The word for 'mercy' (hesed) carries the same active quality as agathōsýnē — goodness in motion.",
        fruitName: "Goodness"
    ),

    // MARK: Faithfulness (3 questions)
    FruitQuizQuestion(
        question: "In the Parable of the Talents, what happens to the faithful servant?",
        options: ["Given rest", "Given more responsibility", "Given wealth", "Given freedom"],
        correctIndex: 1,
        explanation: "The master says 'I will put you in charge of many things' (Matthew 25:21). Faithfulness in small things is preparation for greater trust.",
        fruitName: "Faithfulness"
    ),
    FruitQuizQuestion(
        question: "In Lamentations 3:23, Jeremiah says God's mercies are new every morning because...",
        options: ["God forgets our sins", "Great is His faithfulness", "We deserve second chances", "The law demands it"],
        correctIndex: 1,
        explanation: "Lamentations 3:23: 'great is your faithfulness.' Jeremiah writes this in the middle of Jerusalem's destruction — affirming that God's pístis (faithfulness) holds even in ruins.",
        fruitName: "Faithfulness"
    ),
    FruitQuizQuestion(
        question: "The Greek pístis (faithfulness) in Galatians 5:22 can also be translated as...",
        options: ["Hope", "Trust or fidelity", "Courage", "Endurance"],
        correctIndex: 1,
        explanation: "Pístis means both 'faith' and 'faithfulness/fidelity.' As a fruit of the Spirit, it describes reliable, trustworthy character — being someone others can count on because God can be counted on.",
        fruitName: "Faithfulness"
    ),

    // MARK: Gentleness (3 questions)
    FruitQuizQuestion(
        question: "The classical Greek used praýtēs (meekness/gentleness) to describe...",
        options: ["A timid servant", "A wise scholar", "A tamed wild horse", "A humble king"],
        correctIndex: 2,
        explanation: "Praýtēs described a wild horse that had been tamed — all its strength brought under the rider's control. Meekness is not weakness; it is power under submission.",
        fruitName: "Gentleness"
    ),
    FruitQuizQuestion(
        question: "In Matthew 11:29, Jesus describes himself as...",
        options: ["Mighty and powerful", "Gentle and humble in heart", "Holy and righteous", "Sovereign and just"],
        correctIndex: 1,
        explanation: "Jesus says 'I am gentle (praýs) and humble in heart, and you will find rest for your souls.' The Son of God modeled praýtēs — infinite power held in perfect submission to the Father.",
        fruitName: "Gentleness"
    ),
    FruitQuizQuestion(
        question: "In Numbers 12:3, Moses is described as the most meek/humble man on earth. What was he doing when God affirmed this?",
        options: ["Leading the Exodus", "Defending himself against family criticism", "Receiving the Ten Commandments", "Writing the Torah"],
        correctIndex: 1,
        explanation: "Numbers 12:3 records that Moses did not retaliate when his own siblings criticized him. Gentleness does not mean silence — Moses spoke boldly to Pharaoh — it means power surrendered to God's timing.",
        fruitName: "Gentleness"
    ),

    // MARK: Self-Control (3 questions)
    FruitQuizQuestion(
        question: "What makes Christian self-control different from the Greek philosophers' version?",
        options: ["Christians are stricter", "It's a gift of the Spirit, not a human achievement", "It focuses on diet", "It was invented by Paul"],
        correctIndex: 1,
        explanation: "Greek philosophy saw egkráteia as reason conquering desire through human effort. Paul reframes it as a gift of the Holy Spirit — not achieved but received as we cooperate with God.",
        fruitName: "Self-Control"
    ),
    FruitQuizQuestion(
        question: "In 1 Corinthians 9:27, Paul describes his approach to self-discipline using what metaphor?",
        options: ["A farmer tending crops", "An athlete training his body", "A soldier in armor", "A builder laying a foundation"],
        correctIndex: 1,
        explanation: "Paul says 'I discipline my body and keep it under control' using an athletic training metaphor. Like an Olympic athlete, spiritual self-control requires intentional, structured practice — not mere willpower.",
        fruitName: "Self-Control"
    ),
    FruitQuizQuestion(
        question: "Proverbs 25:28 compares a man without self-control to...",
        options: ["A ship without a rudder", "A city with broken-down walls", "A lamp without oil", "A tree without roots"],
        correctIndex: 1,
        explanation: "Proverbs 25:28: 'Like a city whose walls are broken through is a person who lacks self-control.' Without egkráteia, every part of life becomes vulnerable to attack — the entire city is exposed.",
        fruitName: "Self-Control"
    )
]

// MARK: - Daily Rotation

private var todaysFruit: FruitOfSpirit {
    let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
    return allFruits[(dayOfYear - 1) % allFruits.count]
}

// MARK: - Banner Design Tokens

private enum BannerTokens {
    // Surface: off-white in light, near-black in dark — the MAKA cream/ink palette
    static let surfaceLight = Color(red: 0.965, green: 0.960, blue: 0.950)  // warm cream
    static let surfaceDark  = Color(red: 0.08,  green: 0.08,  blue: 0.085) // near-black

    // Typography
    static let eyebrowSize: CGFloat   = 9
    static let titleSize: CGFloat     = 32   // large editorial serif
    static let verseSize: CGFloat     = 13
    static let refSize: CGFloat       = 11

    // Spacing
    static let hPad: CGFloat    = 20
    static let cornerRadius: CGFloat = 16

    // Motion
    static let expandSpring = Animation.spring(response: 0.40, dampingFraction: 0.82)
    static let fadeIn       = Animation.easeOut(duration: 0.28)
}

// MARK: - Banner View

struct FruitOfSpiritBannerView: View {
    @State private var isExpanded = false
    @State private var appeared   = false
    @State private var isPressed  = false
    @State private var showSheet  = false

    @Environment(\.colorScheme) private var colorScheme

    // Reuse the generator — don't instantiate on every tap
    private let tapHaptic = UIImpactFeedbackGenerator(style: .light)

    private let fruit = todaysFruit

    // Short verse: first sentence of scripture, capped at 90 chars.
    // Stored as a constant — computed once at init, never on body re-evaluation.
    private let shortVerse: String = {
        let raw = todaysFruit.scripture
        let sentences = raw.components(separatedBy: CharacterSet(charactersIn: ".!"))
        let first = sentences.first?.trimmingCharacters(in: .whitespaces) ?? raw
        if first.count <= 90 { return first }
        let words = first.split(separator: " ")
        var result = ""
        for word in words {
            let candidate = result.isEmpty ? String(word) : result + " " + word
            if candidate.count > 88 { break }
            result = candidate
        }
        return result + "\u{2026}"
    }()

    var body: some View {
        bannerCard
            .padding(.horizontal, 16)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.97)
            .onAppear {
                tapHaptic.prepare()
                withAnimation(BannerTokens.fadeIn.delay(0.06)) { appeared = true }
            }
            .sheet(isPresented: $showSheet) {
                FruitOfSpiritDetailSheet(initialFruit: fruit)
            }
    }

    // MARK: - Card shell

    private var bannerCard: some View {
        ZStack(alignment: .topTrailing) {
            // ── Tap anywhere to toggle (except chevron handles its own tap) ──
            VStack(spacing: 0) {
                headerArea
                if isExpanded {
                    expandedVerseArea
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal:   .opacity.combined(with: .move(edge: .top))
                            )
                        )
                }
            }
            .background(bannerBackground)
            .clipShape(RoundedRectangle(cornerRadius: BannerTokens.cornerRadius))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.07),
                    radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.04),
                    radius: 2, x: 0, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: BannerTokens.cornerRadius))
            // Instant press response on finger-down: scale + opacity together
            .scaleEffect(isPressed ? 0.975 : 1.0)
            .opacity(isPressed ? 0.90 : 1.0)
            .animation(.easeOut(duration: 0.10), value: isPressed)
            ._onButtonGesture(
                pressing: { pressing in
                    isPressed = pressing
                },
                perform: {
                    let t0 = Date()
                    tapHaptic.impactOccurred()
                    withAnimation(BannerTokens.expandSpring) { isExpanded.toggle() }
                    DispatchQueue.main.async {
                        let ms = Date().timeIntervalSince(t0) * 1000
                        dlog("🌿 [FruitBanner] Tap → expand=\(isExpanded) settled in \(String(format: "%.1f", ms))ms")
                    }
                }
            )

            // ── Chevron pill — integrated top-right ──────────────────────────
            chevronPill
                .padding(.top, 14)
                .padding(.trailing, BannerTokens.hPad)
                .allowsHitTesting(false) // card tap handles it; chevron is visual only
        }
    }

    // MARK: - Header (always visible)

    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow label
            HStack(spacing: 0) {
                Text("TODAY'S FRUIT")
                    .font(.system(size: BannerTokens.eyebrowSize, weight: .semibold, design: .default))
                    .kerning(2.0)
                    .foregroundStyle(primaryText.opacity(0.38))
                Spacer()
            }
            .padding(.top, 18)
            .padding(.horizontal, BannerTokens.hPad)

            // Large editorial fruit name
            Text(fruit.name)
                .font(.system(size: BannerTokens.titleSize, weight: .heavy, design: .serif))
                .foregroundStyle(primaryText)
                .tracking(-0.5)
                .padding(.top, 4)
                .padding(.horizontal, BannerTokens.hPad)
                .accessibilityLabel("Today's Fruit of the Spirit: \(fruit.name)")

            // Thin accent underline beneath title
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accentUnderlineColor)
                    .frame(width: underlineWidth, height: 1.5)
                    .cornerRadius(1)
                Spacer()
            }
            .padding(.horizontal, BannerTokens.hPad)
            .padding(.top, 6)

            // Collapsed verse teaser (1 line, fades when expanded)
            if !isExpanded {
                Text(shortVerse)
                    .font(.system(size: BannerTokens.verseSize - 1, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(primaryText.opacity(0.50))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, BannerTokens.hPad)
                    .padding(.top, 8)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
                .frame(height: isExpanded ? 4 : 16)
        }
    }

    // MARK: - Expanded verse area

    private var expandedVerseArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hairline separator
            Rectangle()
                .fill(primaryText.opacity(0.10))
                .frame(height: 0.5)
                .padding(.horizontal, BannerTokens.hPad)

            // Full short verse (2 lines max)
            Text("\u{201C}\(shortVerse)\u{201D}")
                .font(.system(size: BannerTokens.verseSize, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(primaryText.opacity(0.72))
                .lineSpacing(4)
                .lineLimit(2)
                .padding(.horizontal, BannerTokens.hPad)
                .padding(.top, 14)
                .accessibilityLabel("Scripture: \(shortVerse)")

            // Reference
            HStack(spacing: 0) {
                Text(fruit.scriptureRef)
                    .font(.system(size: BannerTokens.refSize, weight: .semibold, design: .default))
                    .kerning(0.6)
                    .foregroundStyle(primaryText.opacity(0.38))
                Spacer()
                // "Open" label — tapping card opens detail sheet
                Button {
                    let t0 = Date()
                    tapHaptic.impactOccurred()
                    showSheet = true
                    DispatchQueue.main.async {
                        let ms = Date().timeIntervalSince(t0) * 1000
                        dlog("🌿 [FruitBanner] EXPLORE tapped → sheet presenting in \(String(format: "%.1f", ms))ms")
                    }
                } label: {
                    Text("EXPLORE")
                        .font(.system(size: 8.5, weight: .semibold))
                        .kerning(1.4)
                        .foregroundStyle(primaryText.opacity(0.38))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(primaryText.opacity(0.18), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BannerTokens.hPad)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
    }

    // MARK: - Chevron pill

    private var chevronPill: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(primaryText.opacity(0.30))
            .rotationEffect(.degrees(isExpanded ? -180 : 0))
            .animation(BannerTokens.expandSpring, value: isExpanded)
    }

    // MARK: - Computed styling helpers

    private var primaryText: Color {
        colorScheme == .dark ? .white : Color(red: 0.10, green: 0.10, blue: 0.11)
    }

    // Per-fruit accent underline — restrained, not loud
    private var accentUnderlineColor: Color {
        fruit.accentColor.opacity(colorScheme == .dark ? 0.70 : 0.60)
    }

    // Underline width scales with fruit name length, capped at 80 pt
    private var underlineWidth: CGFloat {
        let approxCharWidth: CGFloat = 16.5
        let raw = CGFloat(fruit.name.count) * approxCharWidth
        return min(raw, 80)
    }

    // MARK: - Background

    @ViewBuilder
    private var bannerBackground: some View {
        if colorScheme == .dark {
            RoundedRectangle(cornerRadius: BannerTokens.cornerRadius)
                .fill(BannerTokens.surfaceDark)
                .overlay(
                    // Very faint top edge highlight for depth in dark mode
                    RoundedRectangle(cornerRadius: BannerTokens.cornerRadius)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                )
        } else {
            RoundedRectangle(cornerRadius: BannerTokens.cornerRadius)
                .fill(BannerTokens.surfaceLight)
                .overlay(
                    // Hairline border in light mode
                    RoundedRectangle(cornerRadius: BannerTokens.cornerRadius)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Design Tokens (Swiss editorial dark theme)

private enum FT {
    // Background layers
    static let bg       = Color(red: 0.05, green: 0.05, blue: 0.06)        // near-black
    static let surface  = Color(red: 0.09, green: 0.09, blue: 0.10)        // lifted surface
    static let divider  = Color.white.opacity(0.10)                         // hairline rule
    static let dividerStrong = Color.white.opacity(0.18)

    // Text
    static let primary  = Color.white
    static let secondary = Color.white.opacity(0.55)
    static let tertiary  = Color.white.opacity(0.30)
    static let label     = Color.white.opacity(0.38)                        // eyebrow labels

    // Motion
    static let tabAnim   = Animation.easeInOut(duration: 0.20)
    static let expandAnim = Animation.spring(response: 0.38, dampingFraction: 0.82)
    static let fruitAnim  = Animation.easeInOut(duration: 0.25)
}

// MARK: - Full Detail Sheet (Swiss editorial redesign)

struct FruitOfSpiritDetailSheet: View {
    let initialFruit: FruitOfSpirit

    @State private var selectedFruitIndex: Int
    @State private var activeTab: DetailTab = .learn
    @State private var expandedSection: String? = nil
    @State private var quizState: QuizState = .idle
    @State private var currentQuestionIndex = 0
    @State private var selectedAnswerIndex: Int? = nil
    @State private var answeredCorrectly: Bool? = nil
    @State private var score = 0
    @State private var showBereanSheet = false
    @State private var bereanInitialQuery = ""
    @Environment(\.dismiss) private var dismiss
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)

    enum DetailTab: String, CaseIterable {
        case learn = "Learn"
        case explore = "All Fruits"
        case quiz = "Quiz"
    }

    enum QuizState { case idle, active, finished }

    init(initialFruit: FruitOfSpirit) {
        self.initialFruit = initialFruit
        let idx = allFruits.firstIndex(where: { $0.name == initialFruit.name }) ?? 0
        _selectedFruitIndex = State(initialValue: idx)
    }

    private var fruit: FruitOfSpirit { allFruits[selectedFruitIndex] }

    var body: some View {
        FT.bg.ignoresSafeArea()
            .overlay(alignment: .top) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // ── Hero header ──────────────────────────────────────────
                        heroHeader
                            .animation(FT.fruitAnim, value: selectedFruitIndex)

                        // ── Tab bar ──────────────────────────────────────────────
                        editorialTabBar
                            .padding(.top, 28)

                        // Hairline under tab bar
                        FT.divider
                            .frame(height: 0.5)
                            .padding(.top, 12)

                        // ── Tab content ──────────────────────────────────────────
                        Group {
                            switch activeTab {
                            case .learn:   learnContent
                            case .explore: exploreContent
                            case .quiz:    quizContent
                            }
                        }
                        .transition(.opacity)
                        .animation(FT.tabAnim, value: activeTab)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                // ── Minimal close button — always above scroll content ──
                Button {
                    haptic.impactOccurred()
                    dismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(FT.bg.opacity(0.85))
                        Circle()
                            .strokeBorder(FT.dividerStrong, lineWidth: 1)
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FT.secondary)
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .padding(.top, 56)
                .padding(.trailing, 20)
                .zIndex(999)
            }
            .ignoresSafeArea()
            .sheet(isPresented: $showBereanSheet) {
                BereanAIAssistantView(initialQuery: bereanInitialQuery)
            }
            .onAppear {
                haptic.prepare()
                hapticMedium.prepare()
            }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            // Accent wash gradient — controlled, not loud
            LinearGradient(
                colors: [
                    fruit.accentColor.opacity(0.22),
                    FT.bg
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
            .ignoresSafeArea(edges: .top)

            // Faint emoji watermark — decorative, editorial
            Text(fruit.emoji)
                .font(.system(size: 140))
                .opacity(0.08)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
                .padding(.bottom, 24)

            // Text block
            VStack(alignment: .leading, spacing: 6) {
                // Eyebrow
                Text("GALATIANS 5:22–23")
                    .font(.system(size: 9, weight: .semibold, design: .default))
                    .tracking(2.5)
                    .foregroundStyle(FT.label)

                // Accent rule under eyebrow
                fruit.accentColor
                    .frame(width: 24, height: 1.5)
                    .cornerRadius(1)
                    .padding(.bottom, 2)

                // Large editorial title
                Text(fruit.name)
                    .font(.system(size: 48, weight: .light, design: .default))
                    .foregroundStyle(FT.primary)
                    .tracking(-0.5)

                // Greek transliteration
                HStack(spacing: 6) {
                    Text(fruit.greekWord)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .italic()
                        .foregroundStyle(fruit.accentColor.opacity(0.85))
                    Text("·")
                        .foregroundStyle(FT.tertiary)
                    Text(fruit.greekPronunciation)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(FT.tertiary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Tab Bar (editorial underline style)

    private var editorialTabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    haptic.impactOccurred()
                    withAnimation(FT.tabAnim) { activeTab = tab }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.rawValue.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.8)
                            .foregroundStyle(activeTab == tab ? FT.primary : FT.secondary)

                        // Accent underline indicator
                        Group {
                            if activeTab == tab {
                                fruit.accentColor.frame(height: 1.5).cornerRadius(1)
                            } else {
                                Color.clear.frame(height: 1.5)
                            }
                        }
                        .animation(FT.tabAnim, value: activeTab)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Learn Tab

    private var learnContent: some View {
        VStack(spacing: 0) {
            // Definition block — large, editorial
            VStack(alignment: .leading, spacing: 12) {
                Text(fruit.shortDefinition)
                    .font(.system(size: 17, weight: .light, design: .default))
                    .foregroundStyle(FT.primary)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 28)

            hairline

            // Scripture blocks
            editorialVerse(
                text: fruit.scripture,
                reference: fruit.scriptureRef,
                accent: fruit.accentColor
            )

            hairline

            editorialVerse(
                text: fruit.secondaryScripture,
                reference: fruit.secondaryScriptureRef,
                accent: fruit.accentColor
            )

            hairline

            // Expandable sections
            editorialExpandable("FULL TEACHING",     key: "teaching", content: fruit.fullTeaching)
            hairline
            editorialExpandable("HISTORICAL CONTEXT", key: "history",  content: fruit.historicalContext)
            hairline
            editorialExpandable("DAILY PRACTICE",    key: "practice", content: fruit.dailyPractice)
            hairline
            editorialExpandable("REFLECTION",        key: "reflect",  content: fruit.reflectionQuestion)
            hairline

            // Overcomes / related tags
            overcomesSection
            hairline

            // Prayer block
            prayerBlock

            hairline

            // Ask Berean button — lets user go deeper with the AI assistant
            askBereanButton

            Spacer(minLength: 48)
        }
        .animation(FT.expandAnim, value: expandedSection)
        .animation(FT.fruitAnim, value: selectedFruitIndex)
    }

    // ── Ask Berean button ──

    private var askBereanButton: some View {
        Button {
            hapticMedium.impactOccurred()
            bereanInitialQuery = "Can you explain the fruit of \(fruit.name) (\(fruit.greekWord)) from Galatians 5:22-23? How do I practically grow in \(fruit.name) as a Christian?"
            showBereanSheet = true
        } label: {
            HStack(spacing: 12) {
                Image("amen-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .blendMode(.multiply)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ASK BEREAN")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(FT.primary)
                    Text("Go deeper with scripture-grounded AI")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(FT.secondary)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(FT.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ── Hairline helper ──

    private var hairline: some View {
        FT.divider.frame(height: 0.5).padding(.horizontal, 24)
    }

    // ── Editorial verse quote ──

    private func editorialVerse(text: String, reference: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Thin vertical accent rule
            accent
                .frame(width: 1.5)
                .cornerRadius(1)
                .padding(.top, 2)
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text("\u{201C}\(text)\u{201D}")
                    .font(.system(size: 15, weight: .light, design: .default))
                    .foregroundStyle(FT.primary.opacity(0.88))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .italic()

                Text(reference.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(accent.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    // ── Expandable section row ──

    private func editorialExpandable(_ title: String, key: String, content: String) -> some View {
        let isOpen = expandedSection == key
        return VStack(spacing: 0) {
            Button {
                haptic.impactOccurred()
                withAnimation(FT.expandAnim) {
                    expandedSection = isOpen ? nil : key
                }
            } label: {
                HStack(spacing: 0) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(isOpen ? FT.primary : FT.secondary)

                    Spacer()

                    // +/– indicator
                    Text(isOpen ? "–" : "+")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(isOpen ? fruit.accentColor : FT.tertiary)
                        .frame(width: 20, height: 20)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(content)
                    .font(.system(size: 14, weight: .light, design: .default))
                    .foregroundStyle(FT.secondary)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // ── Overcomes / grows alongside ──

    private var overcomesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Overcomes
            VStack(alignment: .leading, spacing: 10) {
                Text("OVERCOMES")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(FT.label)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(fruit.opposites, id: \.self) { opp in
                            Text(opp)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(FT.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(FT.dividerStrong, lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }

            // Grows alongside
            VStack(alignment: .leading, spacing: 10) {
                Text("GROWS ALONGSIDE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(FT.label)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(fruit.relatedFruits, id: \.self) { rel in
                            if let match = allFruits.first(where: { $0.name == rel }),
                               let matchIndex = allFruits.firstIndex(where: { $0.name == rel }) {
                                Button {
                                    haptic.impactOccurred()
                                    withAnimation(FT.fruitAnim) {
                                        selectedFruitIndex = matchIndex
                                        expandedSection = nil
                                        activeTab = .learn
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(match.emoji).font(.system(size: 11))
                                        Text(rel)
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundStyle(match.accentColor)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(match.accentColor.opacity(0.35), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    // ── Prayer block ──

    private var prayerBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("PRAYER")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(FT.label)

                fruit.accentColor
                    .frame(width: 16, height: 1)
                    .cornerRadius(1)
            }

            Text(fruit.prayerPrompt)
                .font(.system(size: 15, weight: .light, design: .default))
                .foregroundStyle(FT.secondary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .italic()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    // MARK: - Explore Tab

    private var exploreContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(allFruits.enumerated()), id: \.element.id) { index, f in
                editorialFruitRow(f, index: index)
                FT.divider.frame(height: 0.5).padding(.horizontal, 24)
            }
            Spacer(minLength: 48)
        }
        .padding(.top, 8)
    }

    private func editorialFruitRow(_ f: FruitOfSpirit, index: Int) -> some View {
        let isSelected = index == selectedFruitIndex
        return Button {
            haptic.impactOccurred()
            withAnimation(FT.fruitAnim) {
                selectedFruitIndex = index
                expandedSection = nil
                activeTab = .learn
            }
        } label: {
            HStack(spacing: 16) {
                // Index number
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(FT.tertiary)
                    .frame(width: 22, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(f.name)
                            .font(.system(size: 19, weight: isSelected ? .regular : .light))
                            .foregroundStyle(isSelected ? f.accentColor : FT.primary)

                        if isSelected {
                            // Accent dash
                            f.accentColor
                                .frame(width: 12, height: 1)
                                .cornerRadius(1)
                        }
                    }

                    Text(f.shortDefinition)
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(FT.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Text(f.emoji)
                    .font(.system(size: 22))
                    .opacity(isSelected ? 1 : 0.35)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quiz Tab

    private var quizContent: some View {
        VStack(spacing: 0) {
            switch quizState {
            case .idle:    quizIntroPanel
            case .active:  quizActivePanel
            case .finished: quizResultsPanel
            }
            Spacer(minLength: 48)
        }
        .padding(.top, 8)
    }

    // Quiz intro
    private var quizIntroPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("SCRIPTURE QUIZ")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(FT.label)

                Text("Fruit of\nthe Spirit")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(FT.primary)
                    .lineSpacing(4)

                fruit.accentColor.frame(height: 1).cornerRadius(1)

                Text("Test your knowledge of the nine fruits from Galatians 5 — Greek meaning, biblical context, and application.")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(FT.secondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)

            hairline

            // Stats row
            HStack(spacing: 0) {
                quizStatItem(value: "\(quizQuestions.count)", label: "QUESTIONS")
                Divider().frame(height: 32).background(FT.divider)
                quizStatItem(value: "9", label: "FRUITS")
                Divider().frame(height: 32).background(FT.divider)
                quizStatItem(value: "GK", label: "GREEK FOCUS")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)

            hairline

            // Start button — minimal outlined style
            Button {
                hapticMedium.impactOccurred()
                currentQuestionIndex = 0
                selectedAnswerIndex = nil
                answeredCorrectly = nil
                score = 0
                withAnimation(FT.expandAnim) { quizState = .active }
            } label: {
                HStack(spacing: 10) {
                    Text("BEGIN")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(FT.bg)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FT.bg)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(FT.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
    }

    private func quizStatItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(FT.primary)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(FT.label)
        }
        .frame(maxWidth: .infinity)
    }

    // Quiz active
    private var quizActivePanel: some View {
        let question = quizQuestions[currentQuestionIndex]
        return VStack(alignment: .leading, spacing: 0) {
            // Progress line
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    FT.divider.frame(height: 1)
                    fruit.accentColor
                        .frame(
                            width: geo.size.width * CGFloat(currentQuestionIndex + 1) / CGFloat(quizQuestions.count),
                            height: 1
                        )
                        .animation(.easeInOut(duration: 0.35), value: currentQuestionIndex)
                }
            }
            .frame(height: 1)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            // Question counter
            HStack {
                Text("\(currentQuestionIndex + 1) / \(quizQuestions.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(FT.tertiary)
                    .tracking(1)
                Spacer()
                HStack(spacing: 5) {
                    Text("\(score)")
                        .font(.system(size: 13, weight: .light, design: .monospaced))
                        .foregroundStyle(fruit.accentColor)
                    Text("pts")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(FT.label)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            // Fruit tag
            if let match = allFruits.first(where: { $0.name == question.fruitName }) {
                HStack(spacing: 6) {
                    Text(match.emoji).font(.system(size: 12))
                    Text(question.fruitName.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(match.accentColor)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }

            // Question text
            Text(question.question)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(FT.primary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 24)

            hairline

            // Answer rows
            VStack(spacing: 0) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { idx, option in
                    quizAnswerRow(text: option, index: idx, correctIndex: question.correctIndex)
                    if idx < question.options.count - 1 {
                        FT.divider.frame(height: 0.5).padding(.horizontal, 24)
                    }
                }
            }

            // Explanation
            if let correct = answeredCorrectly {
                hairline
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(correct ? Color(red: 0.18, green: 0.78, blue: 0.42) : Color(red: 0.9, green: 0.28, blue: 0.28))
                            .frame(width: 6, height: 6)
                        Text(correct ? "CORRECT" : "INCORRECT")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(correct ? Color(red: 0.18, green: 0.78, blue: 0.42) : Color(red: 0.9, green: 0.28, blue: 0.28))
                    }
                    Text(question.explanation)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(FT.secondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                hairline

                Button {
                    haptic.impactOccurred()
                    withAnimation(FT.expandAnim) {
                        if currentQuestionIndex + 1 < quizQuestions.count {
                            currentQuestionIndex += 1
                            selectedAnswerIndex = nil
                            answeredCorrectly = nil
                        } else {
                            quizState = .finished
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(currentQuestionIndex + 1 < quizQuestions.count ? "NEXT" : "RESULTS")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(FT.bg)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(FT.bg)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(FT.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .transition(.opacity)
            }
        }
        .animation(FT.expandAnim, value: answeredCorrectly != nil)
    }

    private func quizAnswerRow(text: String, index: Int, correctIndex: Int) -> some View {
        let isSelected   = selectedAnswerIndex == index
        let hasAnswered  = selectedAnswerIndex != nil
        let isCorrect    = index == correctIndex
        let correct      = hasAnswered && isCorrect
        let wrong        = hasAnswered && isSelected && !isCorrect

        let textColor: Color = {
            if !hasAnswered { return FT.primary }
            if correct      { return Color(red: 0.18, green: 0.78, blue: 0.42) }
            if wrong        { return Color(red: 0.9, green: 0.28, blue: 0.28) }
            return FT.tertiary
        }()

        return Button {
            guard selectedAnswerIndex == nil else { return }
            hapticMedium.impactOccurred()
            withAnimation(FT.expandAnim) {
                selectedAnswerIndex = index
                answeredCorrectly = (index == correctIndex)
                if index == correctIndex { score += 1 }
            }
        } label: {
            HStack(spacing: 14) {
                // Letter
                Text(["A", "B", "C", "D"][index])
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(textColor.opacity(0.6))
                    .frame(width: 16)

                Text(text)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                if correct {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.78, blue: 0.42))
                } else if wrong {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.9, green: 0.28, blue: 0.28))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(hasAnswered)
        .animation(FT.expandAnim, value: selectedAnswerIndex)
    }

    // Quiz results
    private var quizResultsPanel: some View {
        let perfect = score == quizQuestions.count
        let great   = score >= Int(Double(quizQuestions.count) * 0.7)

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("RESULTS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(FT.label)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(score)")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(fruit.accentColor)
                    Text("/ \(quizQuestions.count)")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(FT.tertiary)
                }

                fruit.accentColor.frame(height: 1).cornerRadius(1)

                Text(perfect ? "Incredible. A deep knowledge of the fruits."
                     : great  ? "Well done. Keep exploring the teachings."
                              : "The fruits take a lifetime to grow.")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(FT.secondary)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)

            hairline

            // Score progress line
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    FT.divider.frame(height: 1)
                    fruit.accentColor
                        .frame(width: geo.size.width * CGFloat(score) / CGFloat(quizQuestions.count), height: 1)
                        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.15), value: score)
                }
            }
            .frame(height: 1)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)

            hairline

            // Actions
            VStack(spacing: 0) {
                resultActionRow(label: "TRY AGAIN", icon: "arrow.counterclockwise") {
                    withAnimation(FT.expandAnim) {
                        currentQuestionIndex = 0; selectedAnswerIndex = nil
                        answeredCorrectly = nil; score = 0; quizState = .active
                    }
                }
                FT.divider.frame(height: 0.5).padding(.horizontal, 24)
                resultActionRow(label: "BACK TO LEARNING", icon: "book") {
                    withAnimation(FT.tabAnim) { activeTab = .learn; quizState = .idle }
                }
            }
        }
    }

    private func resultActionRow(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            haptic.impactOccurred()
            action()
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(FT.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(FT.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fruit Row Card (kept for any legacy callers, now unused internally)

private struct FruitRowCard: View {
    let fruit: FruitOfSpirit
    let isSelected: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Text(fruit.emoji).font(.system(size: 24))
                VStack(alignment: .leading, spacing: 3) {
                    Text(fruit.name)
                        .font(.system(size: 17, weight: isSelected ? .regular : .light))
                        .foregroundStyle(isSelected ? fruit.accentColor : FT.primary)
                    Text(fruit.shortDefinition)
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(FT.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(FT.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout (wrapping HStack)

private struct FruitFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth + size.width + (rowWidth > 0 ? spacing : 0) > width {
                height += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += size.width + (rowWidth > 0 ? spacing : 0)
                rowHeight = max(rowHeight, size.height)
            }
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Flexible Wrapping Extension

private extension View {
    func flexibleWrapping() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview("Banner") {
    ScrollView {
        VStack(spacing: 16) {
            Text("Filter tabs above").padding()
            FruitOfSpiritBannerView()
            Text("Feed below").padding()
        }
    }
}

#Preview("Sheet") {
    FruitOfSpiritDetailSheet(initialFruit: allFruits[0])
}

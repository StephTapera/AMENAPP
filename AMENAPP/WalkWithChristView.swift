// WalkWithChristView.swift
// AMENAPP
//
// "Walk With Christ" — personalized discipleship companion.
// Internal module name: WalkWithChristFlow
//
// Architecture:
//   WalkWithChristView          — entry / hero detail page (editorial, image-led)
//   WalkWithChristOnboarding    — multi-step placement flow
//   WalkWithChristPathView      — the user's active discipleship path
//   WalkWithChristCheckIn       — weekly check-in sheet
//   WalkWithChristData          — all models, content packs, placement logic

import SwiftUI
import Combine
import UserNotifications

// MARK: - Models

enum WalkStage: String, Codable, CaseIterable {
    case newToFaith       = "New to Faith"
    case curious          = "Curious / Exploring"
    case returning        = "Returning to Faith"
    case growing          = "Growing Deeper"
    case leading          = "Ready to Lead"
}

enum WalkGoal: String, Codable, CaseIterable {
    case gospel           = "Understanding the gospel"
    case prayer           = "Learning to pray"
    case bible            = "Reading the Bible"
    case consistency      = "Building consistency"
    case healing          = "Healing and peace"
    case church           = "Finding a church"
    case doubt            = "Overcoming doubt"
    case disciplines      = "Spiritual disciplines"
    case purpose          = "Purpose and calling"
    case serving          = "Serving others"
    case leading          = "Leading others"
}

enum WalkFrequency: String, Codable, CaseIterable {
    case rarely           = "Rarely"
    case monthly          = "A few times a month"
    case weekly           = "A few times a week"
    case mostDays         = "Most days"
    case daily            = "Daily"
}

enum WalkChurchStatus: String, Codable, CaseIterable {
    case yes              = "Yes"
    case no               = "No"
    case looking          = "Looking for one"
    case unsure           = "Not sure yet"
}

enum WalkNeed: String, Codable, CaseIterable {
    case start            = "A place to start"
    case structure        = "Structure and consistency"
    case encouragement    = "Encouragement"
    case healing          = "Healing"
    case deeper           = "Deeper understanding"
    case accountability   = "Accountability"
    case leadership       = "Leadership growth"
}

struct WalkProfile: Codable {
    var stage: WalkStage = .newToFaith
    var goals: [WalkGoal] = []
    var frequency: WalkFrequency = .rarely
    var churchStatus: WalkChurchStatus = .unsure
    var currentNeed: WalkNeed = .start
    var pathAssigned: WalkPath = .newBeliever
    var onboardingComplete: Bool = false
    var completedModuleIDs: [String] = []
    var checkInCount: Int = 0
    var lastCheckIn: Date?
    var reminderEnabled: Bool = false
    var reminderHour: Int = 8     // 8 AM default
    var reminderMorning: Bool = true
}

enum WalkPath: String, Codable, CaseIterable {
    case newBeliever      = "New Believer"
    case returning        = "Returning to Faith"
    case growing          = "Growing in Faith"
    case deep             = "Deep Discipleship"
    case leading          = "Leadership & Discipleship"
    case heroes           = "Faith Heroes"

    var subtitle: String {
        switch self {
        case .newBeliever:  return "Start your walk with Christ"
        case .returning:    return "Come back to grace"
        case .growing:      return "Go deeper in your faith"
        case .deep:         return "Spiritual disciplines and maturity"
        case .leading:      return "Disciple and lead others"
        case .heroes:       return "Learn from those who waited and trusted"
        }
    }

    var icon: String {
        switch self {
        case .newBeliever:  return "star.fill"
        case .returning:    return "arrow.uturn.left.circle.fill"
        case .growing:      return "leaf.fill"
        case .deep:         return "mountain.2.fill"
        case .leading:      return "person.2.fill"
        case .heroes:       return "crown.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .newBeliever:  return Color(red: 0.95, green: 0.70, blue: 0.25)
        case .returning:    return Color(red: 0.42, green: 0.72, blue: 0.58)
        case .growing:      return Color(red: 0.28, green: 0.62, blue: 0.92)
        case .deep:         return Color(red: 0.55, green: 0.38, blue: 0.82)
        case .leading:      return Color(red: 0.85, green: 0.32, blue: 0.32)
        case .heroes:       return Color(red: 0.80, green: 0.58, blue: 0.12)
        }
    }
}

struct WalkModule: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let scripture: String
    let scriptureRef: String
    let icon: String
    let estimatedMinutes: Int
    let reflection: String
    let bereanPrompt: String
}

// MARK: - Content Library

enum WalkWithChristData {

    // MARK: Path Assignment Logic

    static func assignPath(from profile: WalkProfile) -> WalkPath {
        // Faith Heroes path: surfaced for users focused on purpose/calling
        // or those in a waiting / character-formation season
        if profile.goals.contains(.purpose) || profile.currentNeed == .encouragement {
            if profile.stage == .growing || profile.stage == .leading || profile.stage == .returning {
                return .heroes
            }
        }
        switch profile.stage {
        case .newToFaith, .curious:
            return .newBeliever
        case .returning:
            return .returning
        case .growing:
            if profile.frequency == .daily || profile.frequency == .mostDays {
                return .deep
            }
            return .growing
        case .leading:
            return .leading
        }
    }

    // MARK: Modules per Path

    static func modules(for path: WalkPath) -> [WalkModule] {
        switch path {
        case .newBeliever:  return newBelieverModules
        case .returning:    return returningModules
        case .growing:      return growingModules
        case .deep:         return deepModules
        case .leading:      return leadingModules
        case .heroes:       return heroesModules
        }
    }

    static let newBelieverModules: [WalkModule] = [
        WalkModule(
            id: "nb_01", title: "Who Jesus Is",
            subtitle: "The foundation of everything",
            scripture: "Jesus said to him, 'I am the way, and the truth, and the life.'",
            scriptureRef: "John 14:6",
            icon: "cross.fill",
            estimatedMinutes: 5,
            reflection: "What do you already believe about Jesus? What questions do you have?",
            bereanPrompt: "Who is Jesus, simply explained?"
        ),
        WalkModule(
            id: "nb_02", title: "What Salvation Means",
            subtitle: "Grace, faith, and the gospel",
            scripture: "For by grace you have been saved through faith.",
            scriptureRef: "Ephesians 2:8",
            icon: "heart.fill",
            estimatedMinutes: 6,
            reflection: "Have you ever accepted Jesus as your Savior? What does that mean to you?",
            bereanPrompt: "Explain the gospel in simple words."
        ),
        WalkModule(
            id: "nb_03", title: "How to Pray",
            subtitle: "Talking honestly with God",
            scripture: "Do not be anxious about anything, but in everything by prayer… let your requests be made known to God.",
            scriptureRef: "Philippians 4:6",
            icon: "hands.sparkles.fill",
            estimatedMinutes: 5,
            reflection: "What would you say to God if you could say anything?",
            bereanPrompt: "How do I start praying as a new believer?"
        ),
        WalkModule(
            id: "nb_04", title: "How to Read the Bible",
            subtitle: "Where to start and why it matters",
            scripture: "Your word is a lamp to my feet and a light to my path.",
            scriptureRef: "Psalm 119:105",
            icon: "book.fill",
            estimatedMinutes: 6,
            reflection: "Which part of the Bible interests you most? Where have you tried to start?",
            bereanPrompt: "What should I read first in the Bible as a new believer?"
        ),
        WalkModule(
            id: "nb_05", title: "What Baptism Is",
            subtitle: "A public step of faith",
            scripture: "Go therefore and make disciples… baptizing them in the name of the Father and of the Son and of the Holy Spirit.",
            scriptureRef: "Matthew 28:19",
            icon: "drop.fill",
            estimatedMinutes: 5,
            reflection: "Have you been baptized? What do you want to understand about it?",
            bereanPrompt: "What is baptism and why does it matter?"
        ),
        WalkModule(
            id: "nb_06", title: "What Church Community Is",
            subtitle: "Why you don't walk alone",
            scripture: "And let us consider how to stir up one another to love and good works, not neglecting to meet together.",
            scriptureRef: "Hebrews 10:24–25",
            icon: "person.3.fill",
            estimatedMinutes: 5,
            reflection: "What has kept you from church in the past? What do you hope to find?",
            bereanPrompt: "Why is church community important for a new believer?"
        ),
        WalkModule(
            id: "nb_07", title: "Building a Daily Rhythm",
            subtitle: "Small consistency over big bursts",
            scripture: "Seek the LORD while he may be found; call upon him while he is near.",
            scriptureRef: "Isaiah 55:6",
            icon: "sun.horizon.fill",
            estimatedMinutes: 5,
            reflection: "What would a 5-minute morning with God look like for you?",
            bereanPrompt: "Give me a simple daily routine for someone new to faith."
        ),
    ]

    static let returningModules: [WalkModule] = [
        WalkModule(
            id: "rt_01", title: "Coming Back to God",
            subtitle: "Grace has no expiration date",
            scripture: "But while he was still a long way off, his father saw him and felt compassion, and ran and embraced him.",
            scriptureRef: "Luke 15:20",
            icon: "arrow.uturn.left.circle.fill",
            estimatedMinutes: 5,
            reflection: "What brought you back? What do you hope God knows?",
            bereanPrompt: "What does the Bible say about returning to God after wandering?"
        ),
        WalkModule(
            id: "rt_02", title: "Grace After Wandering",
            subtitle: "There is no shame in returning",
            scripture: "The steadfast love of the LORD never ceases; his mercies never come to an end.",
            scriptureRef: "Lamentations 3:22",
            icon: "heart.fill",
            estimatedMinutes: 5,
            reflection: "Where do you carry shame? What would it feel like to let it go?",
            bereanPrompt: "What does the Bible say about shame and God's forgiveness?"
        ),
        WalkModule(
            id: "rt_03", title: "Rebuilding Trust in God",
            subtitle: "Honesty is the start",
            scripture: "Trust in the LORD with all your heart, and do not lean on your own understanding.",
            scriptureRef: "Proverbs 3:5",
            icon: "shield.fill",
            estimatedMinutes: 6,
            reflection: "Has something made it hard to trust God? What happened?",
            bereanPrompt: "How do I trust God again after hard times?"
        ),
        WalkModule(
            id: "rt_04", title: "Healing, Shame, and Hope",
            subtitle: "God meets you where you are",
            scripture: "He heals the brokenhearted and binds up their wounds.",
            scriptureRef: "Psalm 147:3",
            icon: "bandage.fill",
            estimatedMinutes: 5,
            reflection: "What part of you needs healing most right now?",
            bereanPrompt: "How does God bring healing to broken places?"
        ),
        WalkModule(
            id: "rt_05", title: "Starting Again Without Fear",
            subtitle: "One small step is enough",
            scripture: "For God gave us a spirit not of fear but of power and love and self-control.",
            scriptureRef: "2 Timothy 1:7",
            icon: "figure.walk",
            estimatedMinutes: 5,
            reflection: "What is one small step you can take with God this week?",
            bereanPrompt: "How do I rebuild a faith routine after a long break?"
        ),
    ]

    static let growingModules: [WalkModule] = [
        WalkModule(
            id: "gw_01", title: "Deeper Bible Reading",
            subtitle: "From reading to understanding",
            scripture: "All Scripture is breathed out by God and profitable for teaching, for reproof, for correction, and for training in righteousness.",
            scriptureRef: "2 Timothy 3:16",
            icon: "book.closed.fill",
            estimatedMinutes: 7,
            reflection: "What book of the Bible do you want to understand more deeply?",
            bereanPrompt: "How do I go deeper in Bible study?"
        ),
        WalkModule(
            id: "gw_02", title: "Prayer Rhythms",
            subtitle: "Building a consistent prayer life",
            scripture: "Pray without ceasing.",
            scriptureRef: "1 Thessalonians 5:17",
            icon: "hands.sparkles.fill",
            estimatedMinutes: 6,
            reflection: "What does your prayer life look like right now? What do you want it to look like?",
            bereanPrompt: "What are good prayer rhythms for a growing believer?"
        ),
        WalkModule(
            id: "gw_03", title: "Identity in Christ",
            subtitle: "Who you are because of whose you are",
            scripture: "See what kind of love the Father has given to us, that we should be called children of God.",
            scriptureRef: "1 John 3:1",
            icon: "person.fill.checkmark",
            estimatedMinutes: 6,
            reflection: "How does your identity in Christ change how you see yourself?",
            bereanPrompt: "What does the Bible say about my identity in Christ?"
        ),
        WalkModule(
            id: "gw_04", title: "Spiritual Disciplines",
            subtitle: "Ancient practices for modern life",
            scripture: "Train yourself for godliness; for while bodily training is of some value, godliness is of value in every way.",
            scriptureRef: "1 Timothy 4:7–8",
            icon: "figure.mind.and.body",
            estimatedMinutes: 7,
            reflection: "Which discipline — prayer, fasting, Scripture, silence — do you want to grow in?",
            bereanPrompt: "Explain spiritual disciplines simply."
        ),
        WalkModule(
            id: "gw_05", title: "Hearing God Wisely",
            subtitle: "Discernment and listening prayer",
            scripture: "My sheep hear my voice, and I know them, and they follow me.",
            scriptureRef: "John 10:27",
            icon: "waveform",
            estimatedMinutes: 7,
            reflection: "When have you sensed God speaking to you? What did that feel like?",
            bereanPrompt: "How do I know if God is speaking to me?"
        ),
        WalkModule(
            id: "gw_06", title: "Handling Doubt and Dryness",
            subtitle: "Dry seasons are not abandoned seasons",
            scripture: "Blessed is the man who trusts in the LORD, whose trust is the LORD.",
            scriptureRef: "Jeremiah 17:7",
            icon: "cloud.drizzle.fill",
            estimatedMinutes: 6,
            reflection: "What doubts or questions do you carry? Are you comfortable bringing them to God?",
            bereanPrompt: "What does the Bible say about seasons of doubt?"
        ),
    ]

    static let deepModules: [WalkModule] = [
        WalkModule(
            id: "dp_01", title: "Fasting",
            subtitle: "What it is and why it matters",
            scripture: "But when you fast, anoint your head and wash your face, that your fasting may not be seen by others but by your Father.",
            scriptureRef: "Matthew 6:17–18",
            icon: "leaf.arrow.circlepath",
            estimatedMinutes: 8,
            reflection: "Have you ever fasted? What held you back or drew you toward it?",
            bereanPrompt: "What is fasting and how do I start?"
        ),
        WalkModule(
            id: "dp_02", title: "Perseverance in Suffering",
            subtitle: "Faith that holds through hardship",
            scripture: "Count it all joy, my brothers, when you meet trials of various kinds, for you know that the testing of your faith produces steadfastness.",
            scriptureRef: "James 1:2–3",
            icon: "mountain.2.fill",
            estimatedMinutes: 7,
            reflection: "What suffering in your life has shaped your faith the most?",
            bereanPrompt: "What does the Bible say about suffering and faith?"
        ),
        WalkModule(
            id: "dp_03", title: "Generosity as Spiritual Practice",
            subtitle: "Giving as an act of trust",
            scripture: "Each one must give as he has decided in his heart, not reluctantly or under compulsion, for God loves a cheerful giver.",
            scriptureRef: "2 Corinthians 9:7",
            icon: "gift.fill",
            estimatedMinutes: 6,
            reflection: "How does your relationship with money reflect your trust in God?",
            bereanPrompt: "What does the Bible say about generosity and stewardship?"
        ),
        WalkModule(
            id: "dp_04", title: "Solitude and Silence",
            subtitle: "Being still before God",
            scripture: "Be still, and know that I am God.",
            scriptureRef: "Psalm 46:10",
            icon: "moon.stars.fill",
            estimatedMinutes: 6,
            reflection: "What happens inside you when everything goes quiet?",
            bereanPrompt: "How do I practice solitude and silence with God?"
        ),
        WalkModule(
            id: "dp_05", title: "Calling and Purpose",
            subtitle: "Serving in the shape God made you",
            scripture: "For we are his workmanship, created in Christ Jesus for good works, which God prepared beforehand.",
            scriptureRef: "Ephesians 2:10",
            icon: "lightbulb.fill",
            estimatedMinutes: 7,
            reflection: "Where do you feel most alive when serving God?",
            bereanPrompt: "How do I discover my calling and purpose?"
        ),
    ]

    static let leadingModules: [WalkModule] = [
        WalkModule(
            id: "ld_01", title: "Discipling Others",
            subtitle: "Passing on what you've received",
            scripture: "What you have heard from me in the presence of many witnesses entrust to faithful men, who will be able to teach others also.",
            scriptureRef: "2 Timothy 2:2",
            icon: "person.2.fill",
            estimatedMinutes: 8,
            reflection: "Who in your life are you investing in spiritually?",
            bereanPrompt: "How do I disciple someone?"
        ),
        WalkModule(
            id: "ld_02", title: "Servant Leadership",
            subtitle: "The upside-down kingdom",
            scripture: "Whoever would be great among you must be your servant.",
            scriptureRef: "Matthew 20:26",
            icon: "figure.wave",
            estimatedMinutes: 7,
            reflection: "What does servant leadership look like in your context right now?",
            bereanPrompt: "What does servant leadership mean biblically?"
        ),
        WalkModule(
            id: "ld_03", title: "Walking With People Through Doubt",
            subtitle: "Staying present without easy answers",
            scripture: "And have mercy on those who doubt.",
            scriptureRef: "Jude 1:22",
            icon: "person.fill.questionmark",
            estimatedMinutes: 7,
            reflection: "How do you respond when someone you're mentoring expresses doubt?",
            bereanPrompt: "How do I help someone who is doubting their faith?"
        ),
        WalkModule(
            id: "ld_04", title: "Leading with Humility",
            subtitle: "Strength from a surrendered posture",
            scripture: "Do nothing from selfish ambition or conceit, but in humility count others more significant than yourselves.",
            scriptureRef: "Philippians 2:3",
            icon: "hands.and.sparkles.fill",
            estimatedMinutes: 6,
            reflection: "Where do you struggle most with pride in your leadership?",
            bereanPrompt: "What does humility look like in a leader?"
        ),
        WalkModule(
            id: "ld_05", title: "Biblical Wisdom in Leadership",
            subtitle: "Asking the right questions first",
            scripture: "If any of you lacks wisdom, let him ask God, who gives generously to all without reproach.",
            scriptureRef: "James 1:5",
            icon: "text.book.closed.fill",
            estimatedMinutes: 7,
            reflection: "What decision are you facing right now that needs God's wisdom?",
            bereanPrompt: "How do I lead with biblical wisdom?"
        ),
    ]

    // MARK: Faith Heroes Path

    static let heroesModules: [WalkModule] = [
        WalkModule(
            id: "fh_01", title: "Joseph — Dreams, Pits, and Providence",
            subtitle: "Anointed as a teenager. Betrayed. Enslaved. Then elevated by God.",
            scripture: "You intended to harm me, but God intended it for good.",
            scriptureRef: "Genesis 50:20",
            icon: "star.fill",
            estimatedMinutes: 8,
            reflection: "Where in your life does something painful look like it could still become provision? What would it mean to trust God's hand in it?",
            bereanPrompt: "What can I learn from Joseph's life about trusting God in suffering and waiting?"
        ),
        WalkModule(
            id: "fh_02", title: "Moses — Wilderness Before the Call",
            subtitle: "Raised in a palace. Forty years in the wilderness. Then sent back.",
            scripture: "I have surely seen the affliction of my people… I know their sufferings.",
            scriptureRef: "Exodus 3:7",
            icon: "flame.fill",
            estimatedMinutes: 8,
            reflection: "Has God ever used a long, quiet, or seemingly wasted season to prepare you for something? What did you learn about yourself there?",
            bereanPrompt: "What does Moses' 40 years in the wilderness teach us about how God prepares his people?"
        ),
        WalkModule(
            id: "fh_03", title: "Abraham — Promise Without Proof",
            subtitle: "A promise with no visible path forward. Decades of waiting. Then Isaac.",
            scripture: "He did not waver in unbelief regarding the promise of God, but was strengthened in his faith.",
            scriptureRef: "Romans 4:20",
            icon: "moon.stars.fill",
            estimatedMinutes: 7,
            reflection: "What promise from God are you still waiting on? What makes it hard to keep believing?",
            bereanPrompt: "How did Abraham's faith grow through waiting, and how do I apply that to my own life?"
        ),
        WalkModule(
            id: "fh_04", title: "David — Anointed and Hidden",
            subtitle: "Chosen by God. Years of caves, enemies, and waiting before the throne.",
            scripture: "I have found in David son of Jesse a man after my own heart.",
            scriptureRef: "Acts 13:22",
            icon: "shield.fill",
            estimatedMinutes: 8,
            reflection: "Are you in a 'hidden season' right now — doing the right things without recognition? How does David's story speak to that?",
            bereanPrompt: "What does David's journey from shepherd to king teach about character, waiting, and God's timing?"
        ),
        WalkModule(
            id: "fh_05", title: "Joshua — Faithful in Someone Else's Shadow",
            subtitle: "Decades serving beside Moses. Then the mantle was passed.",
            scripture: "Be strong and courageous. Do not be frightened or dismayed, for the LORD your God is with you wherever you go.",
            scriptureRef: "Joshua 1:9",
            icon: "figure.walk",
            estimatedMinutes: 7,
            reflection: "Have you ever had to be faithful and unseen while someone else led? What did you learn about your own character there?",
            bereanPrompt: "How did Joshua prepare in Moses' shadow, and what does the Bible say about faithful service before promotion?"
        ),
        WalkModule(
            id: "fh_06", title: "Caleb — Wholehearted When Others Weren't",
            subtitle: "He trusted God alone at the border of the Promised Land. Then waited 45 years to inherit it.",
            scripture: "Because my servant Caleb has a different spirit and follows me wholeheartedly, I will bring him into the land.",
            scriptureRef: "Numbers 14:24",
            icon: "mountain.2.fill",
            estimatedMinutes: 7,
            reflection: "Has your faithfulness ever stood out in contrast to fear or doubt around you? What did it cost? What came of it?",
            bereanPrompt: "What does Caleb's story teach about wholeheartedness, long obedience, and the faithfulness of God?"
        ),
        WalkModule(
            id: "fh_07", title: "Esther — Positioned for a Moment You Didn't Choose",
            subtitle: "Quietly placed. Then asked to risk everything. 'For such a time as this.'",
            scripture: "Who knows whether you have not come to the kingdom for such a time as this?",
            scriptureRef: "Esther 4:14",
            icon: "crown.fill",
            estimatedMinutes: 7,
            reflection: "Where are you positioned right now that you didn't plan for? Could it be intentional? What's being asked of you?",
            bereanPrompt: "What does Esther's courage and placement teach about purpose, risk, and God's sovereignty?"
        ),
        WalkModule(
            id: "fh_08", title: "Your Own Waiting Season",
            subtitle: "Every faith hero had one. What is yours teaching you?",
            scripture: "But they who wait for the LORD shall renew their strength; they shall mount up with wings like eagles.",
            scriptureRef: "Isaiah 40:31",
            icon: "hourglass",
            estimatedMinutes: 6,
            reflection: "Looking at these 7 lives — which story resonates most with where you are right now? What do you believe God is forming in your waiting?",
            bereanPrompt: "What does the Bible say about waiting on God, and how do these heroes model that for us?"
        ),
    ]

    // MARK: Quiz Questions

    struct QuizQuestion: Identifiable {
        let id = UUID()
        let question: String
        let options: [String]
        let reflection: String
    }

    static let placementQuiz: [QuizQuestion] = [
        QuizQuestion(
            question: "What stage of faith growth feels most like you right now?",
            options: ["Just beginning — I have a lot of questions",
                      "Growing steadily but want more",
                      "Deep in my walk, ready for more",
                      "I want to help others grow"],
            reflection: "There is no wrong answer. This helps us guide you well."
        ),
        QuizQuestion(
            question: "How consistent is your prayer life?",
            options: ["I don't really pray yet",
                      "I try but it's scattered",
                      "A few times a week",
                      "Daily — it's a real rhythm"],
            reflection: "Consistency grows over time. We'll meet you where you are."
        ),
        QuizQuestion(
            question: "What area do you need most right now?",
            options: ["Understanding what Christianity is",
                      "Building consistency",
                      "Going deeper spiritually",
                      "Learning to lead/disciple"],
            reflection: "Your answer shapes your personalized path."
        ),
    ]

    // MARK: Gentle Reminders

    static let reminderMessages: [String] = [
        "Take a few quiet minutes with God today.",
        "A small step with Christ still matters.",
        "Pause, pray, and stay rooted today.",
        "God meets you in consistency, not perfection.",
        "Even a single verse read is time well spent.",
        "You are loved. That hasn't changed.",
        "Come as you are. God is ready to listen.",
        "Your walk with Christ is worth tending.",
        "What would five minutes with God look like right now?",
        "You are not walking this road alone.",
    ]

    // MARK: Weekly Check-In Questions

    static let checkInQuestions: [String] = [
        "How has your week with God felt?",
        "Were you able to pray at all this week?",
        "Did you spend time in Scripture?",
        "How are you feeling right now — encouraged, dry, uncertain, peaceful?",
        "What would help you most this coming week?",
    ]

    // MARK: Next Steps

    static func nextSteps(for profile: WalkProfile) -> [String] {
        switch profile.pathAssigned {
        case .newBeliever:
            return [
                "Start your 7-day New Believer path",
                "Learn how to pray today",
                "Read the Gospel of John first",
                "Ask Berean a faith question",
                "Find a church near you",
            ]
        case .returning:
            return [
                "Read Coming Back to God today",
                "Write a short honest prayer",
                "Let grace land — revisit the prodigal story",
                "Find a church you can try this week",
                "Ask Berean: what does God think of me returning?",
            ]
        case .growing:
            return [
                "Start the Growing in Faith track",
                "Build a morning prayer rhythm",
                "Take the consistency check-in",
                "Ask Berean about a scripture you've wondered about",
                "Explore one spiritual discipline this week",
            ]
        case .deep:
            return [
                "Begin Deep Discipleship track",
                "Try one fasting practice this week",
                "Journal on your calling and purpose",
                "Ask Berean a hard theological question",
                "Read one wisdom passage slowly this week",
            ]
        case .leading:
            return [
                "Start the Leadership & Discipleship track",
                "Think of one person you can pour into this week",
                "Ask Berean how to encourage someone in doubt",
                "Reflect on where servant leadership is hardest",
                "Set a reminder to pray for those you lead",
            ]
        case .heroes:
            return [
                "Start with Joseph — dreams and providence",
                "Journal what your current 'waiting season' feels like",
                "Ask Berean: which biblical hero's story matches mine?",
                "Read Isaiah 40:28–31 slowly this week",
                "Write down one way God has already used your 'wilderness'",
            ]
        }
    }
}

// MARK: - UserDefaults Persistence

private let kWalkProfileKey = "amen_walk_with_christ_profile"

final class WalkWithChristStore: ObservableObject {
    static let shared = WalkWithChristStore()

    @Published var profile: WalkProfile {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: kWalkProfileKey),
           let decoded = try? JSONDecoder().decode(WalkProfile.self, from: data) {
            profile = decoded
        } else {
            profile = WalkProfile()
        }
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: kWalkProfileKey)
        }
    }

    func reset() {
        profile = WalkProfile()
    }

    func markModuleComplete(_ id: String) {
        if !profile.completedModuleIDs.contains(id) {
            profile.completedModuleIDs.append(id)
        }
    }

    func isComplete(_ id: String) -> Bool {
        profile.completedModuleIDs.contains(id)
    }

    func recordCheckIn() {
        profile.checkInCount += 1
        profile.lastCheckIn = Date()
    }
}

// MARK: - Entry Hero View (editorial, image-led, AMEN-original)

struct WalkWithChristView: View {
    @StateObject private var store = WalkWithChristStore.shared
    @State private var showOnboarding = false
    @State private var showPath = false
    @State private var showCheckIn = false
    @State private var showBerean = false
    @State private var bereanQuery: String? = nil
    @State private var showPathPicker = false
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    // Design tokens — warm cream/slate editorial palette
    private let cream  = Color(red: 0.97, green: 0.95, blue: 0.90)
    private let ink    = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let warm   = Color(red: 0.62, green: 0.48, blue: 0.30)
    private let slate  = Color(red: 0.38, green: 0.38, blue: 0.40)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroHeader
                contentBody
                // Bottom padding so content clears the action tray
                Color.clear.frame(height: 8)
            }
        }
        .ignoresSafeArea(edges: .top)
        // Action tray anchored above the tab bar via safeAreaInset so it
        // never sits behind the system tab bar and is always tappable.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionTray
        }
        .background(cream.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showOnboarding) {
            WalkWithChristOnboarding(store: store)
        }
        .sheet(isPresented: $showPath) {
            WalkWithChristPathView(store: store)
        }
        .sheet(isPresented: $showCheckIn) {
            WalkWithChristCheckIn(store: store)
        }
        .sheet(isPresented: $showBerean) {
            BereanAIAssistantView(initialQuery: bereanQuery)
        }
        .sheet(isPresented: $showPathPicker) {
            PathPickerSheet(store: store)
        }
    }

    // MARK: - Hero Header (immersive, editorial)

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            // Background — warm gradient stand-in (cinematic, not stock photo)
            heroGradientBackground

            // Bottom-to-top fade so text stays readable — visual only
            LinearGradient(
                colors: [ink.opacity(0.72), ink.opacity(0.30), .clear],
                startPoint: .bottom, endPoint: .center
            )
            .allowsHitTesting(false)

            // Editorial title block
            VStack(alignment: .leading, spacing: 6) {
                // Eyebrow
                Text("DISCIPLESHIP")
                    .font(.system(size: 10, weight: .semibold, design: .default))
                    .kerning(3.0)
                    .foregroundStyle(Color.white.opacity(0.60))

                // Large editorial title
                Text("Walk With Christ")
                    .font(.system(size: 36, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .tracking(-0.5)

                // Subtitle
                Text("Personalized guidance for every stage of your faith journey")
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Path badge if assigned
                if store.profile.onboardingComplete {
                    pathBadge
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            // Back button — top left
            // Sits at the top; no Spacer below so scroll events pass through to the ScrollView
            HStack {
                Button { dismiss() } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 36, height: 36)
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 58)
                Spacer()
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 360)
    }

    @ViewBuilder
    private var heroGradientBackground: some View {
        ZStack {
            // Deep warm dusk gradient — cinematic, original to AMEN
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.11, blue: 0.08),
                    Color(red: 0.28, green: 0.18, blue: 0.10),
                    Color(red: 0.48, green: 0.32, blue: 0.18),
                    Color(red: 0.62, green: 0.44, blue: 0.26),
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            // Subtle cross silhouette — centered, very faint
            Image(systemName: "cross")
                .font(.system(size: 180, weight: .ultraLight))
                .foregroundStyle(Color.white.opacity(0.05))
                .offset(x: 60, y: -20)
        }
    }

    private var pathBadge: some View {
        let path = store.profile.pathAssigned
        return HStack(spacing: 6) {
            Image(systemName: path.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(path.accentColor)
            Text(path.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.90))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.14))
                .overlay(Capsule().strokeBorder(path.accentColor.opacity(0.60), lineWidth: 0.8))
        )
    }

    // MARK: - Content Body

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 32) {

            // ── Status / intro block ───────────────────────────────────────
            statusBlock

            // ── Next Steps ────────────────────────────────────────────────
            if store.profile.onboardingComplete {
                nextStepsSection
            }

            // ── Modules preview ───────────────────────────────────────────
            if store.profile.onboardingComplete {
                modulesPreviewSection
            }

            // ── Quiz / Check-In ───────────────────────────────────────────
            quizSection

            // ── Reflection prompts ────────────────────────────────────────
            reflectionSection

            // ── Reminders ─────────────────────────────────────────────────
            reminderSection

            // ── Progress milestones ───────────────────────────────────────
            if store.profile.onboardingComplete && !store.profile.completedModuleIDs.isEmpty {
                progressSection
            }

            // Bottom breathing room
            Color.clear.frame(height: 32)
        }
        .padding(.top, 28)
    }

    // MARK: - Status Block

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.profile.onboardingComplete {
                // Returning user — show path summary
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your path")
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(1.5)
                        .foregroundStyle(slate)
                        .textCase(.uppercase)

                    Text(store.profile.pathAssigned.rawValue)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(ink)

                    Text(store.profile.pathAssigned.subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(slate)
                }
            } else {
                // First-time — invitation block
                VStack(alignment: .leading, spacing: 8) {
                    Text("Walk With Christ")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(ink)

                    Text("Tell us where you are in your faith, and we'll guide you into the right path — whether you're just starting, returning, or ready to go deeper.")
                        .font(.system(size: 14))
                        .foregroundStyle(slate)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    // Scripture callout
                    scriptureCallout(
                        text: "\"Whoever comes to me I will never cast out.\"",
                        reference: "John 6:37"
                    )
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Next Steps

    private var nextStepsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Next Steps")

            VStack(spacing: 8) {
                ForEach(Array(WalkWithChristData.nextSteps(for: store.profile).prefix(4).enumerated()), id: \.offset) { index, step in
                    nextStepRow(index: index + 1, text: step, action: actionForNextStep(step))
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func actionForNextStep(_ step: String) -> () -> Void {
        let lc = step.lowercased()
        if lc.contains("berean") || lc.contains("ask") {
            return {
                bereanQuery = step
                showBerean = true
            }
        } else if lc.contains("check-in") || lc.contains("check in") {
            return { showCheckIn = true }
        } else if lc.contains("path") || lc.contains("track") || lc.contains("start") || lc.contains("read") {
            return { showPath = true }
        } else {
            return { showPath = true }
        }
    }

    private func nextStepRow(index: Int, text: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
        HStack(spacing: 14) {
            // Step number
            ZStack {
                Circle()
                    .fill(store.profile.pathAssigned.accentColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Text("\(index)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(store.profile.pathAssigned.accentColor)
            }

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(ink)
                .lineLimit(2)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(slate.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .shadow(color: ink.opacity(0.06), radius: 6, y: 2)
        )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Modules Preview

    private var modulesPreviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("Your Path")
                Spacer()
                Button { showPath = true } label: {
                    Text("See all")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(warm)
                }
            }
            .padding(.horizontal, 24)

            // Horizontal scroll of module cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    let modules = WalkWithChristData.modules(for: store.profile.pathAssigned)
                    ForEach(modules.prefix(5)) { module in
                        moduleCard(module: module)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func moduleCard(module: WalkModule) -> some View {
        let done = store.isComplete(module.id)
        let accent = store.profile.pathAssigned.accentColor

        return Button { showPath = true } label: {
        VStack(alignment: .leading, spacing: 10) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(done ? accent.opacity(0.14) : Color(red: 0.94, green: 0.92, blue: 0.87))
                    .frame(width: 40, height: 40)
                Image(systemName: done ? "checkmark" : module.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(done ? accent : warm)
            }

            Text(module.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(module.estimatedMinutes) min")
                .font(.system(size: 11))
                .foregroundStyle(slate)

            Spacer()
        }
        .padding(14)
        .frame(width: 140, height: 140)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: ink.opacity(0.07), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(done ? accent.opacity(0.30) : Color.clear, lineWidth: 1)
        )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quiz Section

    private var quizSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Quizzes & Check-Ins")

            HStack(spacing: 12) {
                quizCard(
                    icon: "questionmark.circle.fill",
                    title: "Where are you in your faith?",
                    color: Color(red: 0.28, green: 0.62, blue: 0.92)
                ) {
                    showOnboarding = true
                }
                quizCard(
                    icon: "calendar.badge.checkmark",
                    title: "Weekly check-in",
                    color: Color(red: 0.42, green: 0.72, blue: 0.58)
                ) {
                    showCheckIn = true
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func quizCard(icon: String, title: String, color: Color, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: ink.opacity(0.07), radius: 8, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Reflection Section

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Reflection Prompts")

            let prompts = [
                "What has God been teaching you recently?",
                "Where do you need grace this week?",
                "What spiritual habit do you want to build?",
            ]

            VStack(spacing: 10) {
                ForEach(prompts, id: \.self) { prompt in
                    reflectionRow(prompt)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func reflectionRow(_ prompt: String) -> some View {
        Button {
            bereanQuery = prompt
            showBerean = true
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(warm.opacity(0.50))
                    .frame(width: 3, height: 36)

                Text(prompt)
                    .font(.system(size: 13, design: .serif))
                    .italic()
                    .foregroundStyle(ink.opacity(0.75))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(warm.opacity(0.6))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reminder Section

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Daily Reminders")

            HStack(spacing: 14) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(warm)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(warm.opacity(0.10))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.profile.reminderEnabled ? "Reminders on" : "Turn on reminders")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ink)
                    Text(store.profile.reminderEnabled
                         ? "Daily at \(reminderTimeLabel)"
                         : "Gentle daily nudges for prayer and reading")
                        .font(.system(size: 12))
                        .foregroundStyle(slate)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { store.profile.reminderEnabled },
                    set: { newValue in
                        store.profile.reminderEnabled = newValue
                        if newValue {
                            WalkReminderScheduler.requestAndSchedule(
                                hour: store.profile.reminderHour,
                                messages: WalkWithChristData.reminderMessages
                            )
                        } else {
                            WalkReminderScheduler.cancelAll()
                        }
                    }
                ))
                .labelsHidden()
                .tint(warm)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: ink.opacity(0.06), radius: 6, y: 2)
            )

            // Time picker — only shown when enabled
            if store.profile.reminderEnabled {
                HStack(spacing: 10) {
                    Text("Reminder time")
                        .font(.system(size: 13))
                        .foregroundStyle(slate)
                    Spacer()
                    Picker("Hour", selection: Binding(
                        get: { store.profile.reminderHour },
                        set: { newHour in
                            store.profile.reminderHour = newHour
                            WalkReminderScheduler.requestAndSchedule(
                                hour: newHour,
                                messages: WalkWithChristData.reminderMessages
                            )
                        }
                    )) {
                        ForEach([6, 7, 8, 9, 10, 12, 18, 20, 21], id: \.self) { h in
                            Text(hourLabel(h)).tag(h)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(warm)
                }
                .padding(.horizontal, 4)
            }

            // Today's reminder quote
            let quote = WalkWithChristData.reminderMessages[
                Calendar.current.component(.weekday, from: Date()) % WalkWithChristData.reminderMessages.count
            ]
            Text("\u{201C}\(quote)\u{201D}")
                .font(.system(size: 12, design: .serif))
                .italic()
                .foregroundStyle(slate)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 24)
    }

    private var reminderTimeLabel: String { hourLabel(store.profile.reminderHour) }

    private func hourLabel(_ h: Int) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h a"
        var comps = DateComponents()
        comps.hour = h
        comps.minute = 0
        guard let date = Calendar.current.date(from: comps) else { return "\(h):00" }
        return fmt.string(from: date)
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("My Progress")

            let total = WalkWithChristData.modules(for: store.profile.pathAssigned).count
            let done  = store.profile.completedModuleIDs.count
            let pct   = total > 0 ? CGFloat(done) / CGFloat(total) : 0

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(done) of \(total) completed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ink)
                    Spacer()
                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(store.profile.pathAssigned.accentColor)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(red: 0.90, green: 0.88, blue: 0.84))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(store.profile.pathAssigned.accentColor)
                            .frame(width: geo.size.width * pct, height: 6)
                            .animation(.easeOut(duration: 0.5), value: pct)
                    }
                }
                .frame(height: 6)

                if store.profile.checkInCount > 0 {
                    Text("Check-ins completed: \(store.profile.checkInCount)")
                        .font(.system(size: 12))
                        .foregroundStyle(slate)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: ink.opacity(0.06), radius: 6, y: 2)
            )
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Floating Action Tray (premium, AMEN-original)

    private var actionTray: some View {
        VStack(spacing: 0) {
            // Thin top separator line
            Rectangle()
                .fill(Color(.separator).opacity(0.25))
                .frame(height: 0.5)

            HStack(spacing: 12) {
                if store.profile.onboardingComplete {
                    // Primary — continue path
                    Button { showPath = true } label: {
                        Label("Continue", systemImage: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(ink)
                            )
                    }
                    .buttonStyle(.plain)

                    // Secondary — check-in
                    Button { showCheckIn = true } label: {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 18))
                            .foregroundStyle(ink)
                            .frame(width: 52, height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white)
                                    .shadow(color: ink.opacity(0.10), radius: 6, y: 2)
                            )
                    }
                    .buttonStyle(.plain)

                    // Tertiary — switch path
                    Button { showPathPicker = true } label: {
                        Image(systemName: "map.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(warm)
                            .frame(width: 52, height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white)
                                    .shadow(color: ink.opacity(0.10), radius: 6, y: 2)
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    // First-time — start onboarding
                    Button { showOnboarding = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Start Your Path")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(ink)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        // Extend cream background into the bottom safe area (home indicator zone)
        .background(cream.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .kerning(1.5)
            .foregroundStyle(slate)
            .textCase(.uppercase)
    }

    private func scriptureCallout(text: String, reference: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(warm)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.system(size: 13, design: .serif))
                    .italic()
                    .foregroundStyle(ink.opacity(0.75))
                    .lineSpacing(3)
                Text(reference)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(warm)
                    .kerning(0.5)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(warm.opacity(0.07))
        )
        .padding(.top, 4)
    }
}

// MARK: - Onboarding Flow

struct WalkWithChristOnboarding: View {
    @ObservedObject var store: WalkWithChristStore
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var selectedStage: WalkStage?
    @State private var selectedGoals: Set<WalkGoal> = []
    @State private var selectedFrequency: WalkFrequency?
    @State private var selectedChurch: WalkChurchStatus?
    @State private var selectedNeed: WalkNeed?

    private let totalSteps = 5
    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let cream = Color(red: 0.97, green: 0.95, blue: 0.90)
    private let warm  = Color(red: 0.62, green: 0.48, blue: 0.30)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar
                progressBar

                // Step content
                TabView(selection: $step) {
                    stageStep.tag(0)
                    goalsStep.tag(1)
                    frequencyStep.tag(2)
                    churchStep.tag(3)
                    needStep.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.30), value: step)

                // Navigation buttons
                navigationRow
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var progressBar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Walk With Christ")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(slate)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color(white: 0.92)))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Step dots
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? ink : Color(white: 0.85))
                        .frame(width: i == step ? 20 : 6, height: 6)
                        .animation(.easeOut(duration: 0.20), value: step)
                }
                Spacer()
                Text("\(step + 1) of \(totalSteps)")
                    .font(.system(size: 12))
                    .foregroundStyle(slate)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: Step 1 — Stage

    private var stageStep: some View {
        onboardingStep(
            question: "Where are you in your walk with Christ?",
            subtext: "This helps us guide you into the right path."
        ) {
            ForEach(WalkStage.allCases, id: \.self) { stage in
                selectionRow(
                    label: stage.rawValue,
                    isSelected: selectedStage == stage
                ) {
                    selectedStage = stage
                }
            }
        }
    }

    // MARK: Step 2 — Goals

    private var goalsStep: some View {
        onboardingStep(
            question: "What do you want help with most right now?",
            subtext: "Choose up to 3 things. You can always change these."
        ) {
            ForEach(WalkGoal.allCases, id: \.self) { goal in
                selectionRow(
                    label: goal.rawValue,
                    isSelected: selectedGoals.contains(goal)
                ) {
                    if selectedGoals.contains(goal) {
                        selectedGoals.remove(goal)
                    } else if selectedGoals.count < 3 {
                        selectedGoals.insert(goal)
                    }
                }
            }
        }
    }

    // MARK: Step 3 — Frequency

    private var frequencyStep: some View {
        onboardingStep(
            question: "How often do you currently spend time with God?",
            subtext: "Be honest — there's no judgment here."
        ) {
            ForEach(WalkFrequency.allCases, id: \.self) { freq in
                selectionRow(
                    label: freq.rawValue,
                    isSelected: selectedFrequency == freq
                ) {
                    selectedFrequency = freq
                }
            }
        }
    }

    // MARK: Step 4 — Church

    private var churchStep: some View {
        onboardingStep(
            question: "Are you connected to a local church?",
            subtext: "Church community matters, but we'll meet you where you are."
        ) {
            ForEach(WalkChurchStatus.allCases, id: \.self) { status in
                selectionRow(
                    label: status.rawValue,
                    isSelected: selectedChurch == status
                ) {
                    selectedChurch = status
                }
            }
        }
    }

    // MARK: Step 5 — Need

    private var needStep: some View {
        onboardingStep(
            question: "What best describes what you need right now?",
            subtext: "This shapes the kind of support you'll receive."
        ) {
            ForEach(WalkNeed.allCases, id: \.self) { need in
                selectionRow(
                    label: need.rawValue,
                    isSelected: selectedNeed == need
                ) {
                    selectedNeed = need
                }
            }
        }
    }

    // MARK: Navigation Row

    private var navigationRow: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { step -= 1 }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink)
                        .frame(width: 50, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white)
                                .shadow(color: ink.opacity(0.08), radius: 6, y: 2)
                        )
                }
            }

            Button {
                if step < totalSteps - 1 {
                    withAnimation(.easeOut(duration: 0.25)) { step += 1 }
                } else {
                    finishOnboarding()
                }
            } label: {
                Text(step < totalSteps - 1 ? "Continue" : "Show My Path")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isStepValid ? ink : Color(white: 0.70))
                    )
            }
            .disabled(!isStepValid)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 36)
    }

    private var isStepValid: Bool {
        switch step {
        case 0: return selectedStage != nil
        case 1: return !selectedGoals.isEmpty
        case 2: return selectedFrequency != nil
        case 3: return selectedChurch != nil
        case 4: return selectedNeed != nil
        default: return true
        }
    }

    private func finishOnboarding() {
        var profile = store.profile
        profile.stage          = selectedStage  ?? .newToFaith
        profile.goals          = Array(selectedGoals)
        profile.frequency      = selectedFrequency ?? .rarely
        profile.churchStatus   = selectedChurch ?? .unsure
        profile.currentNeed    = selectedNeed ?? .start
        profile.pathAssigned   = WalkWithChristData.assignPath(from: profile)
        profile.onboardingComplete = true
        store.profile = profile
        dismiss()
    }

    // MARK: Reusable onboarding helpers

    @ViewBuilder
    private func onboardingStep<Content: View>(
        question: String,
        subtext: String,
        @ViewBuilder options: () -> Content
    ) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(question)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtext)
                        .font(.system(size: 13))
                        .foregroundStyle(slate)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                VStack(spacing: 8) {
                    options()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func selectionRow(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? ink : Color(white: 0.80), lineWidth: isSelected ? 2 : 1)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(ink)
                            .frame(width: 12, height: 12)
                    }
                }

                Text(label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(ink)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white : Color(white: 0.97))
                    .shadow(color: isSelected ? ink.opacity(0.10) : .clear, radius: 6, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? ink.opacity(0.15) : Color.clear, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeOut(duration: 0.14), value: isSelected)
    }
}

// MARK: - Path View (all modules in the user's path)

struct WalkWithChristPathView: View {
    @ObservedObject var store: WalkWithChristStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedModule: WalkModule?
    @State private var showPathPicker = false

    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let cream = Color(red: 0.97, green: 0.95, blue: 0.90)
    private let warm  = Color(red: 0.62, green: 0.48, blue: 0.30)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)

    var body: some View {
        NavigationStack {
            ZStack {
                cream.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        // Path header
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: store.profile.pathAssigned.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(store.profile.pathAssigned.accentColor)
                                Text(store.profile.pathAssigned.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .kerning(2.0)
                                    .foregroundStyle(slate)
                            }

                            Text("Your Discipleship Path")
                                .font(.system(size: 26, weight: .bold, design: .serif))
                                .foregroundStyle(ink)

                            Text(store.profile.pathAssigned.subtitle)
                                .font(.system(size: 14))
                                .foregroundStyle(slate)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        // Module list
                        let modules = WalkWithChristData.modules(for: store.profile.pathAssigned)
                        VStack(spacing: 10) {
                            ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                                pathModuleRow(module: module, index: index + 1)
                                    .onTapGesture { selectedModule = module }
                            }
                        }
                        .padding(.horizontal, 24)

                        // ── Explore Other Paths ──────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("EXPLORE OTHER PATHS")
                                .font(.system(size: 10, weight: .semibold))
                                .kerning(2.0)
                                .foregroundStyle(slate)
                                .padding(.horizontal, 24)

                            Button {
                                showPathPicker = true
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(warm.opacity(0.12))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "map.fill")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(warm)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Try a Different Path")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(ink)
                                        Text("Browse all \(WalkPath.allCases.count) discipleship tracks")
                                            .font(.system(size: 12))
                                            .foregroundStyle(slate)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(slate.opacity(0.5))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.white)
                                        .shadow(color: ink.opacity(0.06), radius: 8, y: 2)
                                )
                                .padding(.horizontal, 24)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(slate)
                    }
                }
            }
        }
        .sheet(item: $selectedModule) { module in
            WalkModuleDetailView(module: module, store: store)
        }
        .sheet(isPresented: $showPathPicker) {
            PathPickerSheet(store: store)
        }
    }

    private func pathModuleRow(module: WalkModule, index: Int) -> some View {
        let done = store.isComplete(module.id)
        let accent = store.profile.pathAssigned.accentColor

        return HStack(spacing: 14) {
            // Index / check
            ZStack {
                Circle()
                    .fill(done ? accent.opacity(0.14) : Color(white: 0.93))
                    .frame(width: 36, height: 36)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                } else {
                    Text("\(index)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(slate)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.system(size: 14, weight: done ? .regular : .semibold))
                    .foregroundStyle(done ? slate : ink)
                    .strikethrough(done, color: slate.opacity(0.5))
                Text(module.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(slate)
            }

            Spacer()

            Text("\(module.estimatedMinutes) min")
                .font(.system(size: 11))
                .foregroundStyle(slate.opacity(0.7))

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(slate.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: ink.opacity(0.05), radius: 5, y: 2)
        )
    }
}

// MARK: - Path Picker Sheet

struct PathPickerSheet: View {
    @ObservedObject var store: WalkWithChristStore
    @Environment(\.dismiss) private var dismiss

    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let cream = Color(red: 0.97, green: 0.95, blue: 0.90)
    private let warm  = Color(red: 0.62, green: 0.48, blue: 0.30)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)

    var body: some View {
        NavigationStack {
            ZStack {
                cream.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // Header
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CHOOSE YOUR PATH")
                                .font(.system(size: 10, weight: .semibold))
                                .kerning(2.0)
                                .foregroundStyle(slate)
                            Text("All Discipleship Tracks")
                                .font(.system(size: 26, weight: .bold, design: .serif))
                                .foregroundStyle(ink)
                            Text("Each path is designed to meet you where you are and help you grow.")
                                .font(.system(size: 14))
                                .foregroundStyle(slate)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        // Path cards
                        VStack(spacing: 12) {
                            ForEach(WalkPath.allCases, id: \.self) { path in
                                pathCard(for: path)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(slate)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pathCard(for path: WalkPath) -> some View {
        let isActive = store.profile.pathAssigned == path

        Button {
            if !isActive {
                store.profile.pathAssigned = path
                store.save()
            }
            dismiss()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(path.accentColor.opacity(isActive ? 0.18 : 0.10))
                        .frame(width: 48, height: 48)
                    Image(systemName: path.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(path.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(path.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ink)
                        if isActive {
                            Text("CURRENT")
                                .font(.system(size: 9, weight: .bold))
                                .kerning(1.0)
                                .foregroundStyle(path.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(path.accentColor.opacity(0.12))
                                )
                        }
                    }
                    Text(path.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(slate)
                    Text("\(WalkWithChristData.modules(for: path).count) modules")
                        .font(.system(size: 11))
                        .foregroundStyle(slate.opacity(0.7))
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(path.accentColor)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(slate.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isActive ? path.accentColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
                    )
                    .shadow(color: ink.opacity(0.06), radius: 8, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Module Detail View

struct WalkModuleDetailView: View {
    let module: WalkModule
    @ObservedObject var store: WalkWithChristStore
    @Environment(\.dismiss) private var dismiss
    @State private var showBerean = false

    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let cream = Color(red: 0.97, green: 0.95, blue: 0.90)
    private let warm  = Color(red: 0.62, green: 0.48, blue: 0.30)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)

    var body: some View {
        ZStack(alignment: .bottom) {
            cream.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    // Module hero
                    moduleHero

                    // Scripture
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SCRIPTURE")
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(2.0)
                            .foregroundStyle(slate)

                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(warm)
                                .frame(width: 3)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("\u{201C}\(module.scripture)\u{201D}")
                                    .font(.system(size: 15, design: .serif))
                                    .italic()
                                    .foregroundStyle(ink.opacity(0.80))
                                    .lineSpacing(4)
                                Text(module.scriptureRef)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(warm)
                                    .kerning(0.5)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .shadow(color: ink.opacity(0.06), radius: 6, y: 2)
                        )
                    }

                    // Reflection
                    VStack(alignment: .leading, spacing: 10) {
                        Text("REFLECT")
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(2.0)
                            .foregroundStyle(slate)

                        Text(module.reflection)
                            .font(.system(size: 14, design: .serif))
                            .italic()
                            .foregroundStyle(ink.opacity(0.75))
                            .lineSpacing(5)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(warm.opacity(0.07))
                            )
                    }

                    // Ask Berean
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ASK BEREAN")
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(2.0)
                            .foregroundStyle(slate)

                        Button {
                            // Integration point: open Berean with pre-loaded prompt
                            showBerean = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color(red: 0.38, green: 0.28, blue: 0.72))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ask Berean")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(ink)
                                    Text(module.bereanPrompt)
                                        .font(.system(size: 12))
                                        .foregroundStyle(slate)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(slate.opacity(0.4))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .shadow(color: ink.opacity(0.06), radius: 6, y: 2)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }

            // Action tray
            VStack(spacing: 0) {
                LinearGradient(colors: [cream.opacity(0), cream], startPoint: .top, endPoint: .bottom)
                    .frame(height: 20)

                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(ink)
                            .frame(width: 50, height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white)
                                    .shadow(color: ink.opacity(0.08), radius: 6, y: 2)
                            )
                    }

                    Button {
                        store.markModuleComplete(module.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: store.isComplete(module.id) ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 15))
                            Text(store.isComplete(module.id) ? "Completed" : "Mark Complete")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(store.isComplete(module.id)
                                      ? Color(white: 0.55)
                                      : ink)
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .background(cream.ignoresSafeArea(edges: .bottom))
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var moduleHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(store.profile.pathAssigned.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: module.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(store.profile.pathAssigned.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(module.subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(1.0)
                        .foregroundStyle(slate)
                        .textCase(.uppercase)
                    Text("\(module.estimatedMinutes) min")
                        .font(.system(size: 11))
                        .foregroundStyle(slate)
                }
            }

            Text(module.title)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(ink)
                .lineSpacing(3)
        }
    }
}

// MARK: - Weekly Check-In

struct WalkWithChristCheckIn: View {
    @ObservedObject var store: WalkWithChristStore
    @Environment(\.dismiss) private var dismiss

    @State private var questionIndex = 0
    @State private var answers: [String] = Array(repeating: "", count: 5)
    @State private var done = false

    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let cream = Color(red: 0.97, green: 0.95, blue: 0.90)
    private let warm  = Color(red: 0.62, green: 0.48, blue: 0.30)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)

    private let moods = ["Encouraged", "Dry", "Uncertain", "Peaceful", "Hopeful", "Distant", "Struggling"]
    private let moodIcons = ["sun.max.fill", "cloud.fill", "questionmark.circle.fill",
                              "leaf.fill", "star.fill", "cloud.drizzle.fill", "heart.slash.fill"]

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()

            if done {
                checkInComplete
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weekly Check-In")
                                .font(.system(size: 17, weight: .bold, design: .serif))
                                .foregroundStyle(ink)
                            Text("A few honest questions")
                                .font(.system(size: 12))
                                .foregroundStyle(slate)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(slate)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color(white: 0.92)))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                    // Question
                    VStack(alignment: .leading, spacing: 16) {
                        Text(WalkWithChristData.checkInQuestions[questionIndex])
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundStyle(ink)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        // Mood picker for question 3 (index 3), yes/no for others
                        if questionIndex == 3 {
                            moodPicker
                        } else {
                            yesNoPicker
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Nav
                    HStack(spacing: 12) {
                        if questionIndex > 0 {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { questionIndex -= 1 }
                            } label: {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(ink)
                                    .frame(width: 50, height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(Color.white)
                                            .shadow(color: ink.opacity(0.08), radius: 6, y: 2)
                                    )
                            }
                        }

                        Button {
                            if questionIndex < WalkWithChristData.checkInQuestions.count - 1 {
                                withAnimation(.easeOut(duration: 0.2)) { questionIndex += 1 }
                            } else {
                                store.recordCheckIn()
                                withAnimation { done = true }
                            }
                        } label: {
                            Text(questionIndex < WalkWithChristData.checkInQuestions.count - 1 ? "Next" : "Finish")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(ink)
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var yesNoPicker: some View {
        HStack(spacing: 12) {
            ForEach(["Yes", "Somewhat", "Not really"], id: \.self) { option in
                let isSelected = answers[questionIndex] == option
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        answers[questionIndex] = option
                    }
                } label: {
                    Text(option)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? ink : Color.white)
                                .shadow(color: ink.opacity(0.07), radius: 4, y: 2)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var moodPicker: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
        ], spacing: 10) {
            ForEach(Array(zip(moods, moodIcons)), id: \.0) { mood, icon in
                let isSelected = answers[questionIndex] == mood
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        answers[questionIndex] = mood
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 18))
                            .foregroundStyle(isSelected ? warm : slate)
                        Text(mood)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? ink : slate)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.white : Color(white: 0.96))
                            .shadow(color: isSelected ? ink.opacity(0.08) : .clear, radius: 5, y: 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(isSelected ? ink.opacity(0.12) : Color.clear, lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var checkInComplete: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(warm)

            Text("Check-in complete")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(ink)

            Text("God meets you in honesty. Thank you for checking in.")
                .font(.system(size: 14))
                .foregroundStyle(slate)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            let quote = WalkWithChristData.reminderMessages[
                store.profile.checkInCount % WalkWithChristData.reminderMessages.count
            ]
            Text("\u{201C}\(quote)\u{201D}")
                .font(.system(size: 13, design: .serif))
                .italic()
                .foregroundStyle(warm)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(ink))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }
}

// MARK: - Reminder Scheduler

enum WalkReminderScheduler {
    static let categoryIdentifier = "com.amen.walkwithchrist.daily"

    /// Requests notification permission if needed, then schedules a daily reminder
    /// at the given hour with a rotating pool of gentle messages.
    static func requestAndSchedule(hour: Int, messages: [String]) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            scheduleDailyReminder(hour: hour, messages: messages)
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [categoryIdentifier])
    }

    private static func scheduleDailyReminder(hour: Int, messages: [String]) {
        let center = UNUserNotificationCenter.current()

        // Remove any existing Walk With Christ reminder first
        center.removePendingNotificationRequests(withIdentifiers: [categoryIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Walk With Christ"
        // Rotate through messages deterministically by day-of-year
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        content.body = messages[(dayOfYear - 1) % messages.count]
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        var triggerComponents = DateComponents()
        triggerComponents.hour = hour
        triggerComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: triggerComponents,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: categoryIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request)
    }
}

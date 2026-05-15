//
//  HolidayAwarenessModels.swift
//  AMENAPP
//
//  Full Holiday Awareness model layer.
//  Defines categories, consistency levels, banner content catalog, user settings,
//  personal celebrations, spiritual guardrail, and the resolved context response
//  for the Amen Daily Verse Holiday Awareness system.
//

import Foundation

// MARK: - Holiday Category

/// Broad classification of what kind of holiday this is.
enum HolidayCategory: String, Codable, CaseIterable {
    case biblicalFeast          = "biblical_feast"
    case christianEvent         = "christian_event"
    case biblicallyConsistent   = "biblically_consistent"
    case discernment            = "discernment"
    case personal               = "personal"

    var bannerBadgeLabel: String {
        switch self {
        case .biblicalFeast:        return "Biblical Feast"
        case .christianEvent:       return "Christian Holiday"
        case .biblicallyConsistent: return "Today in Amen"
        case .discernment:          return "Walk in wisdom"
        case .personal:             return "Your celebration"
        }
    }
}

// MARK: - Holiday Consistency Level

enum HolidayConsistencyLevel: String, Codable {
    case strong       = "strong"        // Directly biblical (Easter, Passover)
    case consistent   = "consistent"    // Biblically consistent (Thanksgiving, Mother's Day)
    case discernment  = "discernment"   // Needs pastoral framing (Halloween, Mardi Gras)
    case avoid        = "avoid"         // Outright unbiblical
}

// MARK: - Holiday Banner Content

/// The scriptural and pastoral copy for a single holiday banner.
struct HolidayBannerContent {
    let category: HolidayCategory
    let consistencyLevel: HolidayConsistencyLevel
    let canonicalName: String
    let shortBannerTitle: String
    let shortBannerMessage: String
    let primaryScriptureReference: String
    let additionalScriptures: [String]
    let theme: String
    let callToActionLabel: String
    let callToActionRoute: String
    let expandedReflection: String
    let allowedTone: String
    let prohibitedTone: String
}

// MARK: - Holiday Spiritual Guardrail

/// Safety layer that prevents banner copy from promoting unbiblical behavior.
enum HolidaySpiritualGuardrail {

    /// Returns true when banner content passes all theological safety checks.
    static func isSafe(content: HolidayBannerContent) -> Bool {
        let prohibited = [
            "celebrate", "happy halloween", "party", "drunk", "alcohol",
            "occult", "spirits", "witch", "darkness", "lust", "required",
            "must observe", "mandated"
        ]
        let combinedText = (content.shortBannerMessage + content.expandedReflection).lowercased()
        for word in prohibited where combinedText.contains(word) {
            return false
        }
        return true
    }

    /// Returns the discernment-safe version of a CTA label for holidays that need framing.
    static func safeCTALabel(for consistencyLevel: HolidayConsistencyLevel, original: String) -> String {
        switch consistencyLevel {
        case .discernment:
            return "Practice discernment"
        case .avoid:
            return "Reflect on holiness"
        default:
            return original
        }
    }

    /// Returns a pastoral note appended to discernment holiday reflections.
    static func discernmentNote(for canonicalName: String) -> String {
        return "Today can be approached with wisdom. Christians differ on how to observe \(canonicalName). " +
               "Let your conscience be guided by Scripture, not pressure."
    }
}

// MARK: - Holiday Banner Catalog

/// Static mapping of every supported HolidayType to its banner content.
/// This is the authoritative source for all on-device copy.
/// Backend Firestore data may override this for future flexibility.
enum HolidayBannerCatalog {

    // swiftlint:disable function_body_length
    static func content(for type: HolidayType) -> HolidayBannerContent? {
        switch type {

        // ─── MAJOR CHRISTIAN EVENTS ────────────────────────────────────────

        case .easter:
            return HolidayBannerContent(
                category: .christianEvent,
                consistencyLevel: .strong,
                canonicalName: "Resurrection Sunday",
                shortBannerTitle: "He is risen",
                shortBannerMessage: "The resurrection is not only something to remember — it is the hope we live from.",
                primaryScriptureReference: "Matthew 28:6",
                additionalScriptures: ["1 Corinthians 15:20–22", "John 11:25", "Romans 6:4"],
                theme: "Resurrection, victory, hope, new life",
                callToActionLabel: "Celebrate the resurrection",
                callToActionRoute: "amen://berean?season=easter",
                expandedReflection: "Christ is risen — not as a memory, but as a living reality. Because He lives, you live. His resurrection is the foundation of your hope, the seal of your forgiveness, and the guarantee of your own resurrection. Today, let the truth of the empty tomb reach every corner of your heart.",
                allowedTone: "joyful, victorious, worshipful",
                prohibitedTone: "casual, commercial, performative"
            )

        case .goodFriday:
            return HolidayBannerContent(
                category: .christianEvent,
                consistencyLevel: .strong,
                canonicalName: "Good Friday",
                shortBannerTitle: "By His wounds",
                shortBannerMessage: "Today we remember the cross — the love of Christ poured out for us.",
                primaryScriptureReference: "Isaiah 53:5",
                additionalScriptures: ["John 19:30", "Romans 5:8", "2 Corinthians 5:21"],
                theme: "Atonement, sacrifice, love, suffering",
                callToActionLabel: "Reflect on the cross",
                callToActionRoute: "amen://berean?season=good_friday",
                expandedReflection: "The cross was not a tragedy that God redeemed — it was the plan. Jesus bore every weight of sin, shame, and separation so that you would never have to. Sit with the gravity of Good Friday. Do not rush past it. The resurrection is coming, but today belongs to the cross.",
                allowedTone: "solemn, grateful, reverent",
                prohibitedTone: "flippant, light, celebratory"
            )

        case .christmas:
            return HolidayBannerContent(
                category: .christianEvent,
                consistencyLevel: .strong,
                canonicalName: "Christmas Day",
                shortBannerTitle: "God with us",
                shortBannerMessage: "Christ has come. The Word became flesh and dwelt among us — full of grace and truth.",
                primaryScriptureReference: "John 1:14",
                additionalScriptures: ["Luke 2:10–11", "Matthew 1:21", "Isaiah 9:6"],
                theme: "Incarnation, Emmanuel, worship, grace",
                callToActionLabel: "Worship the newborn King",
                callToActionRoute: "amen://berean?season=christmas",
                expandedReflection: "God became human. That is the scandalous, beautiful truth of Christmas. Not merely a baby in a manger, but the eternal Word taking on flesh to rescue the world He made. Today, worship Him not for what He gives — but for who He is. Emmanuel: God with us.",
                allowedTone: "warm, worshipful, joyful",
                prohibitedTone: "commercial, sentimental, shallow"
            )

        case .christmasEve:
            return HolidayBannerContent(
                category: .christianEvent,
                consistencyLevel: .strong,
                canonicalName: "Christmas Eve",
                shortBannerTitle: "The night before",
                shortBannerMessage: "Tonight, the world waited — and then, a cry in Bethlehem changed everything.",
                primaryScriptureReference: "Luke 2:10–11",
                additionalScriptures: ["Isaiah 7:14", "Micah 5:2"],
                theme: "Anticipation, incarnation, wonder",
                callToActionLabel: "Prepare your heart",
                callToActionRoute: "amen://berean?season=christmas_eve",
                expandedReflection: "The shepherds did not know it yet. The innkeeper did not understand what he had turned away. But heaven knew — angels were preparing to sing. Tonight, prepare your heart to receive Christ again, not as tradition, but as truth.",
                allowedTone: "anticipatory, gentle, wonder-filled",
                prohibitedTone: "commercial, gift-focused"
            )

        case .pentecost:
            return HolidayBannerContent(
                category: .christianEvent,
                consistencyLevel: .strong,
                canonicalName: "Pentecost Sunday",
                shortBannerTitle: "Come, Holy Spirit",
                shortBannerMessage: "The same Spirit who filled the disciples is at work in the Church today.",
                primaryScriptureReference: "Acts 2:1–4",
                additionalScriptures: ["John 14:26", "John 16:7", "Galatians 5:22–23"],
                theme: "Holy Spirit, empowerment, witness, boldness",
                callToActionLabel: "Pray for fresh fire",
                callToActionRoute: "amen://berean?season=pentecost",
                expandedReflection: "The Church was not born from a committee or a program. It was born in fire. The Holy Spirit came, and ordinary people were transformed into fearless witnesses. Today, ask God to fill you afresh. His Spirit is not a past event — He is a present reality.",
                allowedTone: "bold, prayerful, hopeful",
                prohibitedTone: "chaotic, formulaic, performance-driven"
            )

        case .palmSunday:
            return HolidayBannerContent(
                category: .christianEvent,
                consistencyLevel: .strong,
                canonicalName: "Palm Sunday",
                shortBannerTitle: "Hosanna to the King",
                shortBannerMessage: "Jesus entered Jerusalem as King — humble, on a donkey, welcomed with shouts of praise.",
                primaryScriptureReference: "Matthew 21:9",
                additionalScriptures: ["John 12:13", "Zechariah 9:9", "Psalm 118:26"],
                theme: "Christ the King, humility, worship, prophecy",
                callToActionLabel: "Welcome the King",
                callToActionRoute: "amen://berean?season=palm_sunday",
                expandedReflection: "The crowd shouted 'Hosanna!' — which means 'Save us now.' They welcomed a King, but did not yet understand the cross He was riding toward. As you welcome Christ today, welcome all of Him: the King, the Lamb, the Savior. Not just the triumph, but the sacrifice.",
                allowedTone: "worshipful, anticipatory, humble",
                prohibitedTone: "triumphalistic, nationalistic"
            )

        case .ascension:
            return HolidayBannerContent(
                category: .christianEvent,
                consistencyLevel: .strong,
                canonicalName: "Ascension Day",
                shortBannerTitle: "Christ reigns",
                shortBannerMessage: "Jesus ascended to the right hand of the Father — and He will return.",
                primaryScriptureReference: "Acts 1:9–11",
                additionalScriptures: ["Luke 24:50–53", "Ephesians 1:20–22", "Hebrews 7:25"],
                theme: "Ascension, reign, intercession, return",
                callToActionLabel: "Look up in hope",
                callToActionRoute: "amen://berean?season=ascension",
                expandedReflection: "When Jesus ascended, the disciples stared at the sky. The angels asked, 'Why are you standing here looking?' There is a posture for living between ascension and return: active, hopeful, working. Christ reigns. He intercedes for you. And He is coming back.",
                allowedTone: "confident, hopeful, expectant",
                prohibitedTone: "passive, distant, academic"
            )

        case .adventStart:
            return HolidayBannerContent(
                category: .christianEvent,
                consistencyLevel: .strong,
                canonicalName: "First Sunday of Advent",
                shortBannerTitle: "The waiting begins",
                shortBannerMessage: "Advent is a season of holy waiting — preparing your heart for the One who came, and who is coming again.",
                primaryScriptureReference: "Isaiah 9:6",
                additionalScriptures: ["Luke 1:30–33", "Revelation 22:20", "Isaiah 40:3"],
                theme: "Anticipation, hope, preparation, Christ's return",
                callToActionLabel: "Enter the season",
                callToActionRoute: "amen://berean?season=advent",
                expandedReflection: "Advent is not simply about waiting for Christmas. It is about learning to wait at all — in a world that refuses to. The prophets waited centuries for the Messiah. The disciples wait for His return. You are in that same waiting. Let this season deepen your hope.",
                allowedTone: "contemplative, hopeful, expectant",
                prohibitedTone: "commercial, rushed, shallow"
            )

        case .ashWednesday:
            return HolidayBannerContent(
                category: .christianEvent,
                consistencyLevel: .consistent,
                canonicalName: "Ash Wednesday",
                shortBannerTitle: "From dust, to life",
                shortBannerMessage: "Lent begins with honesty: we are dust, and to dust we return. But in Christ, that is not the end.",
                primaryScriptureReference: "Joel 2:12–13",
                additionalScriptures: ["Psalm 51:10", "Matthew 4:1–2", "2 Corinthians 7:10"],
                theme: "Repentance, mortality, humility, grace",
                callToActionLabel: "Enter Lent with humility",
                callToActionRoute: "amen://berean?season=lent",
                expandedReflection: "Ash Wednesday does not mean despair. It means honesty before God. You are finite. You are fallen. And you are loved. The same God who formed you from dust breathed life into you, and the same Christ who died is the reason death does not have the final word. Come before God today with open hands.",
                allowedTone: "solemn, honest, grace-filled",
                prohibitedTone: "legalistic, guilt-heavy, performance-driven"
            )

        case .maundyThursday:
            return HolidayBannerContent(
                category: .christianEvent,
                consistencyLevel: .strong,
                canonicalName: "Maundy Thursday",
                shortBannerTitle: "The night He served",
                shortBannerMessage: "On the night He was betrayed, Jesus knelt to wash feet. Greatness in the Kingdom looks like this.",
                primaryScriptureReference: "John 13:14",
                additionalScriptures: ["Luke 22:19–20", "Matthew 26:26–29"],
                theme: "Service, humility, communion, sacrifice",
                callToActionLabel: "Serve someone today",
                callToActionRoute: "amen://berean?season=holy_week",
                expandedReflection: "Jesus, the King of the universe, wrapped a towel around His waist and washed the feet of the men who would soon deny and betray Him. This is the standard of the Kingdom. Today, find someone to serve without expectation of recognition or return.",
                allowedTone: "humble, solemn, service-oriented",
                prohibitedTone: "casual, academic"
            )

        case .holySaturday:
            return HolidayBannerContent(
                category: .christianEvent,
                consistencyLevel: .strong,
                canonicalName: "Holy Saturday",
                shortBannerTitle: "In the silence",
                shortBannerMessage: "The disciples did not yet know about Sunday. Today, sit with those who wait in darkness — and trust the God who works in silence.",
                primaryScriptureReference: "Lamentations 3:26",
                additionalScriptures: ["Psalm 22:1", "Isaiah 53:9"],
                theme: "Waiting, grief, trust, silence",
                callToActionLabel: "Wait in hope",
                callToActionRoute: "amen://berean?season=holy_week",
                expandedReflection: "Holy Saturday is the in-between day. The cross is finished. The tomb is sealed. The disciples are hiding. And God is — silent. But silence does not mean absence. Every Saturday in your life — every waiting, grieving, unsure season — is followed by the possibility of Sunday.",
                allowedTone: "still, honest, tender",
                prohibitedTone: "rushed, triumphalistic"
            )

        case .newYearConsecration:
            return HolidayBannerContent(
                category: .biblicallyConsistent,
                consistencyLevel: .consistent,
                canonicalName: "New Year's Day",
                shortBannerTitle: "New mercies",
                shortBannerMessage: "Begin the year with surrender. His mercies are new every morning — and every year.",
                primaryScriptureReference: "Lamentations 3:22–23",
                additionalScriptures: ["Isaiah 43:19", "Psalm 90:12", "Proverbs 16:3"],
                theme: "Renewal, consecration, mercy, fresh start",
                callToActionLabel: "Pray over the year",
                callToActionRoute: "amen://berean?context=new_year",
                expandedReflection: "A new year is not a guarantee — it is a gift. God's mercies do not reset because a calendar page turns; they are new every single morning. But today, use this marker to surrender what was, release what is not yours to carry, and open your hands to what God has planned for the year ahead.",
                allowedTone: "hopeful, surrendered, intentional",
                prohibitedTone: "superstitious, achievement-focused, resolution-driven"
            )

        case .thanksgiving:
            return HolidayBannerContent(
                category: .biblicallyConsistent,
                consistencyLevel: .consistent,
                canonicalName: "Thanksgiving",
                shortBannerTitle: "A day for gratitude",
                shortBannerMessage: "Give thanks to the Lord today — not only for what He gives, but for who He is.",
                primaryScriptureReference: "1 Thessalonians 5:18",
                additionalScriptures: ["Psalm 100:1–5", "Colossians 3:15–17", "Psalm 107:1"],
                theme: "Gratitude, God's faithfulness, abundance, worship",
                callToActionLabel: "Pray with gratitude",
                callToActionRoute: "amen://berean?context=thanksgiving",
                expandedReflection: "Gratitude is not just a feeling for good seasons. Paul says give thanks in ALL circumstances — not for all of them, but in them. Today, choose to see God's hand not just in the blessings but in the provision, the grace, the ways He carried you through what was hard.",
                allowedTone: "warm, reflective, God-centered",
                prohibitedTone: "consumerist, self-congratulatory"
            )

        // ─── CIVIC / BIBLICALLY CONSISTENT HOLIDAYS ───────────────────────

        case .mothersDay:
            return HolidayBannerContent(
                category: .biblicallyConsistent,
                consistencyLevel: .consistent,
                canonicalName: "Mother's Day",
                shortBannerTitle: "Honor with gratitude",
                shortBannerMessage: "Today is a moment to honor mothers, mother figures, and the wisdom of faithful love.",
                primaryScriptureReference: "Proverbs 31:25",
                additionalScriptures: ["Exodus 20:12", "Proverbs 31:10–31", "Luke 1:46–48"],
                theme: "Honor, wisdom, sacrifice, family",
                callToActionLabel: "Send encouragement",
                callToActionRoute: "amen://berean?context=mothers_day",
                expandedReflection: "The Bible honors mothers — their wisdom, their sacrifice, their prayers. Whether you are celebrating your own mother, honoring her memory, or carrying the grief of what was not given, God sees you. Honor the faithful women in your life today as an act of worship.",
                allowedTone: "warm, honoring, tender",
                prohibitedTone: "commercial, sentimental without depth"
            )

        case .fathersDay:
            return HolidayBannerContent(
                category: .biblicallyConsistent,
                consistencyLevel: .consistent,
                canonicalName: "Father's Day",
                shortBannerTitle: "Honoring fathers",
                shortBannerMessage: "Today we honor fathers and father figures — and are reminded of God, the perfect Father.",
                primaryScriptureReference: "Ephesians 6:4",
                additionalScriptures: ["Exodus 20:12", "Psalm 103:13", "Proverbs 4:1"],
                theme: "Fatherhood, instruction, leadership, God as Father",
                callToActionLabel: "Reflect on fatherhood",
                callToActionRoute: "amen://berean?context=fathers_day",
                expandedReflection: "Earthly fatherhood, at its best, is a dim reflection of God's perfect fatherhood — compassionate, present, instructing without crushing, protecting without controlling. Honor faithful fathers today. And for those whose father story is painful, remember: you have a Father who does not disappoint.",
                allowedTone: "warm, affirming, God-pointed",
                prohibitedTone: "condescending, idealized"
            )

        case .memorialDay:
            return HolidayBannerContent(
                category: .biblicallyConsistent,
                consistencyLevel: .consistent,
                canonicalName: "Memorial Day",
                shortBannerTitle: "Remember with honor",
                shortBannerMessage: "We remember those who gave their lives for others — and we give thanks to the God of peace.",
                primaryScriptureReference: "John 15:13",
                additionalScriptures: ["Romans 13:7", "Psalm 9:1", "Micah 4:3"],
                theme: "Remembrance, sacrifice, honor, peace",
                callToActionLabel: "Pray for peace",
                callToActionRoute: "amen://berean?context=memorial_day",
                expandedReflection: "Greater love has no one than this — to lay down one's life for his friends. Today, we honor men and women who made that sacrifice. Remember them with dignity. And pray for the peace of God to rule — in the nations, in your community, and in your own heart.",
                allowedTone: "solemn, honoring, prayerful",
                prohibitedTone: "militaristic, triumphalistic, glorifying violence"
            )

        case .laborDay:
            return HolidayBannerContent(
                category: .biblicallyConsistent,
                consistencyLevel: .consistent,
                canonicalName: "Labor Day",
                shortBannerTitle: "Work as worship",
                shortBannerMessage: "Whatever your work, do it as unto the Lord. And rest today as a gift from God.",
                primaryScriptureReference: "Colossians 3:23",
                additionalScriptures: ["Proverbs 14:23", "Exodus 20:9–10", "Genesis 2:2–3"],
                theme: "Work, diligence, rest, provision",
                callToActionLabel: "Rest with intention",
                callToActionRoute: "amen://berean?context=labor_day",
                expandedReflection: "Work is not a curse — it was part of creation before the Fall. But rest is also holy. God modeled it at creation, commanded it in the Law, and invites you into it today. Work hard for the glory of God. And rest fully, without guilt, in His provision.",
                allowedTone: "dignifying, restful, purposeful",
                prohibitedTone: "hustle-culture, idle, meaningless"
            )

        case .independenceDay:
            return HolidayBannerContent(
                category: .biblicallyConsistent,
                consistencyLevel: .consistent,
                canonicalName: "Independence Day",
                shortBannerTitle: "Freedom for service",
                shortBannerMessage: "Thank God for freedom — and remember: true freedom is using your liberty to love and serve others.",
                primaryScriptureReference: "Galatians 5:13",
                additionalScriptures: ["1 Peter 2:16", "John 8:36", "Romans 13:1"],
                theme: "Freedom, justice, gratitude, service",
                callToActionLabel: "Reflect on true freedom",
                callToActionRoute: "amen://berean?context=independence_day",
                expandedReflection: "Political freedom is a gift to be grateful for. But Scripture's vision of freedom is deeper: freedom from sin, freedom to serve, freedom to love. Today, thank God for the liberties you enjoy — and hold them with open hands, committed to using them for the good of others.",
                allowedTone: "grateful, humble, justice-aware",
                prohibitedTone: "nationalistic, idolatrous, uncritical"
            )

        case .veteransDay:
            return HolidayBannerContent(
                category: .biblicallyConsistent,
                consistencyLevel: .consistent,
                canonicalName: "Veterans Day",
                shortBannerTitle: "Honor those who served",
                shortBannerMessage: "We honor the service and sacrifice of those who answered the call — with prayer and gratitude.",
                primaryScriptureReference: "Romans 13:7",
                additionalScriptures: ["John 15:13", "Psalm 46:1", "Isaiah 2:4"],
                theme: "Honor, service, respect, peace",
                callToActionLabel: "Pray for veterans",
                callToActionRoute: "amen://berean?context=veterans_day",
                expandedReflection: "Veterans carry more than medals — many carry wounds seen and unseen. Honor their service today with more than words. Pray for those who carry trauma from war. And pray for a world where swords are beaten into plowshares — the peace only God can bring.",
                allowedTone: "honoring, prayerful, compassionate",
                prohibitedTone: "glorifying violence, overly politicized"
            )

        // ─── BIBLICAL FEASTS ───────────────────────────────────────────────

        case .passover:
            return HolidayBannerContent(
                category: .biblicalFeast,
                consistencyLevel: .strong,
                canonicalName: "Passover",
                shortBannerTitle: "The Lamb of God",
                shortBannerMessage: "Passover remembers deliverance from Egypt — and points us to Christ, our Passover Lamb.",
                primaryScriptureReference: "1 Corinthians 5:7",
                additionalScriptures: ["Exodus 12:12–13", "Luke 22:14–20", "John 1:29"],
                theme: "Deliverance, redemption, Christ our Passover",
                callToActionLabel: "Reflect on the Lamb",
                callToActionRoute: "amen://berean?context=passover",
                expandedReflection: "The blood of the Passover lamb protected Israel from death in Egypt. That lamb was a shadow of the greater Lamb — Jesus, who by His blood protects all who believe from the judgment of sin. Passover is not just history: it is fulfilled in Christ, who is our Passover.",
                allowedTone: "reverent, historically grounded, Christocentric",
                prohibitedTone: "supersessionist, dismissive of Jewish roots"
            )

        case .unleavenedBread:
            return HolidayBannerContent(
                category: .biblicalFeast,
                consistencyLevel: .strong,
                canonicalName: "Feast of Unleavened Bread",
                shortBannerTitle: "Leave behind what enslaves",
                shortBannerMessage: "Unleavened bread speaks of purity — leaving sin behind and walking in sincerity and truth.",
                primaryScriptureReference: "1 Corinthians 5:8",
                additionalScriptures: ["Exodus 12:15–20", "Leviticus 23:6–8", "Galatians 5:1"],
                theme: "Purity, deliverance, separation from sin, new life",
                callToActionLabel: "Examine what you carry",
                callToActionRoute: "amen://berean?context=unleavened_bread",
                expandedReflection: "Leaven in Scripture often represents what corrupts slowly. The feast of Unleavened Bread calls the people to put away what defiles — to eat the bread of sincerity and truth. Ask God today: is there something in my life I need to leave behind?",
                allowedTone: "reflective, honest, inviting",
                prohibitedTone: "legalistic, shame-based"
            )

        case .firstfruits:
            return HolidayBannerContent(
                category: .biblicalFeast,
                consistencyLevel: .strong,
                canonicalName: "Firstfruits",
                shortBannerTitle: "Offer the first and best",
                shortBannerMessage: "Firstfruits is about trust — giving God the first portion and believing He will provide the rest.",
                primaryScriptureReference: "Proverbs 3:9",
                additionalScriptures: ["Leviticus 23:9–14", "1 Corinthians 15:20", "Romans 8:23"],
                theme: "Generosity, trust, resurrection, giving God first",
                callToActionLabel: "Give God your first",
                callToActionRoute: "amen://berean?context=firstfruits",
                expandedReflection: "The firstfruits offering was an act of trust: 'God, I believe you will provide the rest.' And Christ is called the firstfruits of the resurrection — the first of many who will rise. Today, consider what God is asking for first in your time, treasure, and attention.",
                allowedTone: "generous, trusting, resurrection-focused",
                prohibitedTone: "prosperity-gospel, manipulative"
            )

        case .feastOfWeeks:
            return HolidayBannerContent(
                category: .biblicalFeast,
                consistencyLevel: .strong,
                canonicalName: "Feast of Weeks",
                shortBannerTitle: "Harvest and Spirit",
                shortBannerMessage: "Shavuot celebrates the harvest — and in the New Testament, it became the day the Holy Spirit came.",
                primaryScriptureReference: "Acts 2:1–4",
                additionalScriptures: ["Leviticus 23:15–22", "Deuteronomy 16:10", "Joel 2:28–32"],
                theme: "Harvest, Holy Spirit, Word of God, community",
                callToActionLabel: "Give thanks for the harvest",
                callToActionRoute: "amen://berean?context=feast_of_weeks",
                expandedReflection: "On the same feast day that Israel celebrated the grain harvest, God sent His Spirit like a rushing wind and a harvest of souls began — 3,000 in one day. The feasts of Israel are fulfilled in Christ and the Spirit. Today, give thanks for the harvest of grace in your own life.",
                allowedTone: "grateful, Spirit-aware, connected to Jewish roots",
                prohibitedTone: "disconnected from Scripture, purely symbolic"
            )

        case .feastOfTrumpets:
            return HolidayBannerContent(
                category: .biblicalFeast,
                consistencyLevel: .consistent,
                canonicalName: "Feast of Trumpets",
                shortBannerTitle: "Wake up and listen",
                shortBannerMessage: "The trumpet call is a summons — to attention, to repentance, to readiness before God.",
                primaryScriptureReference: "Leviticus 23:24",
                additionalScriptures: ["Numbers 29:1", "1 Thessalonians 4:16", "Isaiah 27:13"],
                theme: "Awakening, attentiveness, readiness, repentance",
                callToActionLabel: "Examine your heart",
                callToActionRoute: "amen://berean?context=feast_of_trumpets",
                expandedReflection: "The shofar was sounded to call the people to attention — to gather, to prepare, to return to God. The sound of a trumpet in Scripture is never casual. Today, hear the call. Is there an area of your life where you have been inattentive? Return to the Lord with your whole heart.",
                allowedTone: "sobering, awakening, hope-filled",
                prohibitedTone: "fearful, heavy, eschatologically obsessive"
            )

        case .dayOfAtonement:
            return HolidayBannerContent(
                category: .biblicalFeast,
                consistencyLevel: .strong,
                canonicalName: "Day of Atonement",
                shortBannerTitle: "Covered by Christ",
                shortBannerMessage: "Yom Kippur, the Day of Atonement, finds its fulfillment in Jesus — our great High Priest.",
                primaryScriptureReference: "Hebrews 9:12",
                additionalScriptures: ["Leviticus 16:30", "Leviticus 23:27–28", "Hebrews 10:12"],
                theme: "Atonement, forgiveness, cleansing, Christ our High Priest",
                callToActionLabel: "Rest in His atonement",
                callToActionRoute: "amen://berean?context=day_of_atonement",
                expandedReflection: "Once a year, the high priest entered the Most Holy Place with blood — for himself and the nation. Year after year, the same sacrifice. Then Christ came and entered the true Holy Place once for all, with His own blood, obtaining eternal redemption. Your sin has been atoned for. Rest in that.",
                allowedTone: "solemn, gospel-centered, worshipful",
                prohibitedTone: "works-based, fearful, dismissive"
            )

        case .feastOfTabernacles:
            return HolidayBannerContent(
                category: .biblicalFeast,
                consistencyLevel: .consistent,
                canonicalName: "Feast of Tabernacles",
                shortBannerTitle: "God dwells with His people",
                shortBannerMessage: "Sukkot remembers God's faithfulness in the wilderness — and points to the day He will dwell with us forever.",
                primaryScriptureReference: "John 1:14",
                additionalScriptures: ["Leviticus 23:33–43", "John 7:37–38", "Revelation 21:3"],
                theme: "God's presence, provision, wilderness, eternal dwelling",
                callToActionLabel: "Remember His faithfulness",
                callToActionRoute: "amen://berean?context=feast_of_tabernacles",
                expandedReflection: "For seven days, Israel lived in temporary shelters to remember their wilderness journey — and God's faithful presence through it. John writes that Jesus 'tabernacled' among us. One day, God will tabernacle with humanity forever. Today, give thanks for His presence in your wilderness seasons.",
                allowedTone: "grateful, reflective, eschatologically hopeful",
                prohibitedTone: "purely historical, disconnected from Christ"
            )

        // ─── DISCERNMENT HOLIDAYS ──────────────────────────────────────────

        case .halloween:
            return HolidayBannerContent(
                category: .discernment,
                consistencyLevel: .discernment,
                canonicalName: "Halloween",
                shortBannerTitle: "Walk as children of light",
                shortBannerMessage: "Today, choose what is good, pure, and life-giving. Reject darkness and overcome evil with good.",
                primaryScriptureReference: "Ephesians 5:8–11",
                additionalScriptures: ["Philippians 4:8", "Romans 12:21", "1 Thessalonians 5:21–22"],
                theme: "Light over darkness, wisdom, discernment, hospitality",
                callToActionLabel: "Practice discernment",
                callToActionRoute: "amen://berean?context=halloween",
                expandedReflection: "Christians approach today differently. Some avoid it entirely; others use it as an opportunity for community and hospitality. Whatever your conviction, let your choices today be shaped by this: you are a child of light. Walk in it. Overcome evil with good — in your neighborhood, your community, your heart.",
                allowedTone: "pastoral, wisdom-focused, non-shaming",
                prohibitedTone: "fear-mongering, occult, spooky, celebratory of darkness"
            )

        case .valentinesDay:
            return HolidayBannerContent(
                category: .discernment,
                consistencyLevel: .discernment,
                canonicalName: "Valentine's Day",
                shortBannerTitle: "Love as God defines it",
                shortBannerMessage: "Let love be patient, kind, faithful, and rooted in Christ — not performance, not lust, but covenant.",
                primaryScriptureReference: "1 Corinthians 13:4–7",
                additionalScriptures: ["1 John 4:19", "Ephesians 5:25", "Song of Solomon 8:6–7"],
                theme: "Biblical love, covenant, purity, self-giving",
                callToActionLabel: "Reflect on love",
                callToActionRoute: "amen://berean?context=valentines_day",
                expandedReflection: "The world defines love as a feeling that comes and goes. God defines it as a choice that endures. Whether you are single, dating, married, or grieving love lost — today, meditate on 1 Corinthians 13. Real love is patient. It does not envy. It does not perform. It bears all things.",
                allowedTone: "warm, honest, covenantal",
                prohibitedTone: "lust-driven, pressure-filled, commercial"
            )

        case .stPatricksDay:
            return HolidayBannerContent(
                category: .discernment,
                consistencyLevel: .discernment,
                canonicalName: "St. Patrick's Day",
                shortBannerTitle: "A missionary's legacy",
                shortBannerMessage: "Patrick was a missionary who brought Christ to Ireland. Today, remember that witness is the calling of every believer.",
                primaryScriptureReference: "Matthew 28:19–20",
                additionalScriptures: ["Ephesians 5:18", "Romans 10:15", "1 Peter 3:15"],
                theme: "Mission, witness, self-control, sobriety",
                callToActionLabel: "Live as a witness",
                callToActionRoute: "amen://berean?context=st_patricks_day",
                expandedReflection: "Patrick's real story is remarkable — captured as a slave, he escaped, heard God's call, returned to Ireland as a missionary, and transformed a culture. The holiday named for him has drifted far from his life. Today, reclaim what is worth honoring: the calling to go, proclaim, and make disciples.",
                allowedTone: "missional, historically honest, self-controlled",
                prohibitedTone: "promoting drunkenness, commercialized"
            )

        case .mardiGras:
            return HolidayBannerContent(
                category: .discernment,
                consistencyLevel: .discernment,
                canonicalName: "Mardi Gras",
                shortBannerTitle: "Choose holiness, not excess",
                shortBannerMessage: "Before Lent begins, choose humility over indulgence. Prepare your heart for the repentance ahead.",
                primaryScriptureReference: "Galatians 5:16",
                additionalScriptures: ["Romans 13:13–14", "1 Peter 1:15–16", "Galatians 5:24"],
                theme: "Self-control, holiness, preparation for Lent",
                callToActionLabel: "Prepare for Lent",
                callToActionRoute: "amen://berean?context=mardi_gras",
                expandedReflection: "Mardi Gras began as a final feast before the fasting of Lent — a tradition now often associated with excess. Christians differ on how to observe this season. Whatever your tradition, let today be a moment of intentionality: not binge before fasting, but humble preparation before the holy work of Lent.",
                allowedTone: "sober, preparatory, non-shaming",
                prohibitedTone: "promoting excess, drunkenness, immorality"
            )

        // ─── SEASON NODES (shown as supporting context, not primary banner) ─

        case .lent, .lentStart:
            return HolidayBannerContent(
                category: .christianEvent,
                consistencyLevel: .consistent,
                canonicalName: "Lent",
                shortBannerTitle: "A season of surrender",
                shortBannerMessage: "Lent is not about rules — it is about returning to God with your whole heart.",
                primaryScriptureReference: "Joel 2:12",
                additionalScriptures: ["Psalm 51:10–12", "Matthew 6:16–18"],
                theme: "Repentance, fasting, prayer, surrender",
                callToActionLabel: "Surrender something today",
                callToActionRoute: "amen://berean?season=lent",
                expandedReflection: "Lent is an invitation to simplicity — to remove the noise and draw close to God. It is not about earning favor but about clearing space for His voice. Christians observe Lent differently. If it resonates, let this season sharpen your focus on what truly matters.",
                allowedTone: "gentle, inviting, non-legalistic",
                prohibitedTone: "shame-based, obligatory, performance-driven"
            )

        case .advent:
            return HolidayBannerContent(
                category: .christianEvent,
                consistencyLevel: .consistent,
                canonicalName: "Advent",
                shortBannerTitle: "The season of hope",
                shortBannerMessage: "Advent is a season of holy waiting and expectation — for Christ who came, and who is coming again.",
                primaryScriptureReference: "Isaiah 9:6",
                additionalScriptures: ["Revelation 22:20", "Romans 8:22–23"],
                theme: "Hope, waiting, anticipation, Christ's return",
                callToActionLabel: "Wait with hope",
                callToActionRoute: "amen://berean?season=advent",
                expandedReflection: "The world rushes toward Christmas. Advent invites you to slow down. To wait. To prepare. To let the longing of the prophets shape your own longing. Come, Lord Jesus.",
                allowedTone: "quiet, expectant, hopeful",
                prohibitedTone: "commercial, rushed"
            )

        // Holidays without a distinct banner (handled by season or not shown)
        default:
            return nil
        }
    }
    // swiftlint:enable function_body_length
}

// MARK: - Holiday Awareness Settings

/// User-controlled settings for holiday awareness on the Daily Verse banner.
/// Stored in `users/{uid}/settings/holidayAwareness` in Firestore.
struct HolidayAwarenessSettings: Codable {
    var enabled: Bool
    var showChristianHolidays: Bool
    var showBiblicalFeasts: Bool
    var showCivicBiblicalValues: Bool
    var showDiscernmentHolidays: Bool
    var showPersonalCelebrations: Bool
    var traditionPreference: TraditionPreference
    var timezone: String
    var quietModeOnSolemnDays: Bool

    static var defaultSettings: HolidayAwarenessSettings {
        HolidayAwarenessSettings(
            enabled: true,
            showChristianHolidays: true,
            showBiblicalFeasts: true,
            showCivicBiblicalValues: true,
            showDiscernmentHolidays: true,
            showPersonalCelebrations: false,
            traditionPreference: .generalChristian,
            timezone: TimeZone.current.identifier,
            quietModeOnSolemnDays: false
        )
    }

    /// Whether the given holiday category is enabled by user settings.
    func allows(category: HolidayCategory) -> Bool {
        guard enabled else { return false }
        switch category {
        case .christianEvent:       return showChristianHolidays
        case .biblicalFeast:        return showBiblicalFeasts
        case .biblicallyConsistent: return showCivicBiblicalValues
        case .discernment:          return showDiscernmentHolidays
        case .personal:             return showPersonalCelebrations
        }
    }

    enum TraditionPreference: String, Codable, CaseIterable {
        case generalChristian = "general_christian"
        case protestant       = "protestant"
        case catholic         = "catholic"
        case orthodox         = "orthodox"
        case messianic        = "messianic"
        case custom           = "custom"

        var displayName: String {
            switch self {
            case .generalChristian: return "General Christian"
            case .protestant:       return "Protestant"
            case .catholic:         return "Catholic"
            case .orthodox:         return "Orthodox"
            case .messianic:        return "Messianic"
            case .custom:           return "Custom"
            }
        }
    }
}

// MARK: - Personal Holiday Celebrations

/// Opt-in personal dates for personalized holiday awareness.
/// Stored in `users/{uid}/settings/personalCelebrations` — never shared publicly.
struct PersonalHolidayCelebrations: Codable {
    var birthday: MonthDay?
    var weddingDate: MonthDay?
    var anniversaryDate: MonthDay?
    var childDedicationDates: [MonthDay]

    init(
        birthday: MonthDay? = nil,
        weddingDate: MonthDay? = nil,
        anniversaryDate: MonthDay? = nil,
        childDedicationDates: [MonthDay] = []
    ) {
        self.birthday = birthday
        self.weddingDate = weddingDate
        self.anniversaryDate = anniversaryDate
        self.childDedicationDates = childDedicationDates
    }

    struct MonthDay: Codable, Equatable {
        let month: Int   // 1–12
        let day: Int     // 1–31
    }

    enum PersonalCelebration: String, Codable {
        case birthday         = "birthday"
        case wedding          = "wedding"
        case anniversary      = "anniversary"
        case childDedication  = "child_dedication"

        var bannerContent: HolidayBannerContent {
            switch self {
            case .birthday:
                return HolidayBannerContent(
                    category: .personal,
                    consistencyLevel: .consistent,
                    canonicalName: "Your Birthday",
                    shortBannerTitle: "A gift from God",
                    shortBannerMessage: "Your life is a gift from God — crafted with purpose, known before you were born.",
                    primaryScriptureReference: "Psalm 139:13–16",
                    additionalScriptures: ["James 1:17", "Jeremiah 1:5"],
                    theme: "Life as a gift, purpose, God's design",
                    callToActionLabel: "Pray over this year",
                    callToActionRoute: "amen://berean?context=birthday",
                    expandedReflection: "Before you were born, God knew you. Today, remember that your life is not an accident — it is a gift, a calling, and a story still being written. Ask God what He is building in this year of your life.",
                    allowedTone: "personal, celebratory, prayerful",
                    prohibitedTone: "superstitious, self-centered"
                )
            case .wedding:
                return HolidayBannerContent(
                    category: .personal,
                    consistencyLevel: .consistent,
                    canonicalName: "Your Wedding Day",
                    shortBannerTitle: "Covenant love",
                    shortBannerMessage: "Two becoming one is a picture of Christ's love — faithful, sacrificial, and beautiful.",
                    primaryScriptureReference: "Genesis 2:24",
                    additionalScriptures: ["Matthew 19:4–6", "Ephesians 5:25–27"],
                    theme: "Covenant, faithfulness, marriage",
                    callToActionLabel: "Pray over your covenant",
                    callToActionRoute: "amen://berean?context=wedding",
                    expandedReflection: "Marriage is a covenant — a living picture of God's faithfulness. Today, reflect on what it means to love sacrificially, stay faithfully, and point your marriage toward Christ.",
                    allowedTone: "covenantal, warm, worshipful",
                    prohibitedTone: "sentimental without depth"
                )
            case .anniversary:
                return HolidayBannerContent(
                    category: .personal,
                    consistencyLevel: .consistent,
                    canonicalName: "Your Anniversary",
                    shortBannerTitle: "Remember His faithfulness",
                    shortBannerMessage: "Another year of covenant kept. Faithfulness is a gift — from God and between you.",
                    primaryScriptureReference: "Genesis 2:24",
                    additionalScriptures: ["Ecclesiastes 4:9–12", "Proverbs 31:10"],
                    theme: "Faithfulness, gratitude, covenant",
                    callToActionLabel: "Give thanks together",
                    callToActionRoute: "amen://berean?context=anniversary",
                    expandedReflection: "Every year a marriage endures is a testimony to grace. Covenant love is not natural — it is supernatural. Give thanks to God for the faithfulness He has sustained, and ask Him to strengthen the years ahead.",
                    allowedTone: "warm, reflective, grateful",
                    prohibitedTone: "performance-driven"
                )
            case .childDedication:
                return HolidayBannerContent(
                    category: .personal,
                    consistencyLevel: .consistent,
                    canonicalName: "Child Dedication",
                    shortBannerTitle: "Children are a heritage",
                    shortBannerMessage: "This child belongs first to God — given to you as a gift and responsibility.",
                    primaryScriptureReference: "Psalm 127:3",
                    additionalScriptures: ["1 Samuel 1:27–28", "Proverbs 22:6"],
                    theme: "Children as a gift, dedication, parenting",
                    callToActionLabel: "Pray for your child",
                    callToActionRoute: "amen://berean?context=child_dedication",
                    expandedReflection: "Children are a heritage from the Lord. To raise them is to steward a life that belongs to God. Ask Him for wisdom, patience, and love to parent in a way that points this child toward Christ.",
                    allowedTone: "gentle, grateful, purposeful",
                    prohibitedTone: "burdensome, legalistic"
                )
            }
        }
    }

    /// Returns today's personal celebration if any personal date matches today's month and day.
    func activeCelebration(using calendar: Calendar = .current) -> PersonalCelebration? {
        let today = calendar.dateComponents([.month, .day], from: Date())
        guard let todayMonth = today.month, let todayDay = today.day else { return nil }

        if let bd = birthday, bd.month == todayMonth, bd.day == todayDay { return .birthday }
        if let wd = weddingDate, wd.month == todayMonth, wd.day == todayDay { return .wedding }
        if let ad = anniversaryDate, ad.month == todayMonth, ad.day == todayDay { return .anniversary }
        for cd in childDedicationDates where cd.month == todayMonth && cd.day == todayDay {
            return .childDedication
        }
        return nil
    }
}

// MARK: - Holiday Context Response

/// The fully-resolved holiday context for today's banner.
struct HolidayContextResponse {
    let date: Date
    let bannerContent: HolidayBannerContent?
    let holidayType: HolidayType?
    let shouldShowHolidayBanner: Bool
    let shouldShowDiscernmentFraming: Bool
    let holidayPriority: Int
    let reason: String
    let personalCelebration: PersonalHolidayCelebrations.PersonalCelebration?

    static var noHoliday: HolidayContextResponse {
        HolidayContextResponse(
            date: Date(),
            bannerContent: nil,
            holidayType: nil,
            shouldShowHolidayBanner: false,
            shouldShowDiscernmentFraming: false,
            holidayPriority: 0,
            reason: "No holiday today",
            personalCelebration: nil
        )
    }
}

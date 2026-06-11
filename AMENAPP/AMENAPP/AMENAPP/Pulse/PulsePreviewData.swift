//
//  PulsePreviewData.swift
//  AMEN — Amen Pulse
//
//  Server-shaped sample digest for SwiftUI previews and DEBUG. Mirrors the bounded
//  7-card prototype. Never used in production reads — the client always reads the
//  server-written /users/{uid}/pulse/{date} document.
//

#if DEBUG
import Foundation

extension PulseDigest {
    static var previewSeed: PulseDigest {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())

        let brief = PulseCard(
            id: "brief",
            kind: .dailyBriefHero,
            hero: PulseHero(scrim: .light, style: "brief"),
            eyebrow: "Daily Brief",
            title: "Good morning, Steph",
            subtitle: "Today’s focus — “Trust in the Lord with all your heart.” Proverbs 3:5",
            action: PulseAction(kind: .openBrief, label: "Open Brief"),
            minorSafe: true,
            expiresAt: tomorrow,
            provenanceLabel: "Generated this morning · Summaries by Berean · cite-or-refuse",
            facts: [
                PulseFact(systemImage: "hands.sparkles", text: "3 prayer requests have updates"),
                PulseFact(systemImage: "building.columns", text: "2 church events this week"),
                PulseFact(systemImage: "heart", text: "1 friend celebrating a milestone")
            ],
            briefSections: [
                PulseBriefSection(heading: "Prayer", body: "Marcus shared that his father’s surgery went well — he’s asking for continued prayer through recovery.", minimumDuration: .thirtySec),
                PulseBriefSection(heading: "Church", body: "Worship night tonight at 7. Sunday’s food-drive sign-up closes Friday.", minimumDuration: .thirtySec),
                PulseBriefSection(heading: "People", body: "Sarah and Mike welcomed baby Eden on Tuesday. David’s birthday is Saturday.", minimumDuration: .threeMin),
                PulseBriefSection(heading: "Scripture", body: "You’re three chapters from finishing Proverbs. Today’s focus: trust over self-reliance — Proverbs 3:5–6.", minimumDuration: .tenMin)
            ]
        )

        let whatsNew = PulseCard(
            id: "wn-berean-sermon",
            kind: .whatsNew,
            hero: PulseHero(scrim: .dark, style: "whatsnew"),
            eyebrow: "New in Amen",
            title: "Berean now understands sermon context",
            subtitle: "Ask about Sunday’s message — Berean cites the passage, never invents it.",
            action: PulseAction(kind: .seeWhatsNew, label: "See What’s New"),
            minorSafe: true,
            whatsNewStoryId: "wn-berean-sermon"
        )

        let prayer = PulseCard(
            id: "prayer1",
            kind: .prayerFollowup,
            hero: PulseHero(scrim: .dark, style: "prayer"),
            eyebrow: "Prayer Update",
            title: "Marcus posted an update",
            subtitle: "You prayed for his father’s surgery 7 days ago. He shared good news this morning.",
            action: PulseAction(kind: .checkIn, label: "Check In", deeplink: "amen://prayer/marcus-surgery"),
            minorSafe: true
        )

        let event = PulseCard(
            id: "event1",
            kind: .churchEvent,
            hero: PulseHero(scrim: .dark, style: "event"),
            eyebrow: "Tonight · 7:00 PM",
            title: "Elevation Worship Night",
            subtitle: "Hosted at Redemption Gateway. Doors at 6:30.",
            action: PulseAction(kind: .rsvp, label: "RSVP", deeplink: "amen://event/elevation-worship"),
            minorSafe: true,
            meta: [
                PulseFact(systemImage: "person.2", text: "7 friends interested"),
                PulseFact(systemImage: "clock", text: "Starts in 3 hours")
            ]
        )

        let verse = PulseCard(
            id: "verse1",
            kind: .scriptureHero,
            hero: PulseHero(scrim: .light, style: "verse"),
            eyebrow: "Verse of the Day",
            title: "“Be still, and know that I am God.”",
            subtitle: "Psalm 46:10 · BSB — Continue in Proverbs 3 where you left off.",
            action: PulseAction(kind: .read, label: "Read"),
            minorSafe: true
        )

        let occasion = PulseCard(
            id: "occ1",
            kind: .occasion,
            hero: PulseHero(scrim: .light, style: "occasion"),
            eyebrow: "Milestone",
            title: "Sarah & Mike welcomed baby Eden",
            subtitle: "Born Tuesday, 7 lbs 2 oz. The Hendersons are home and resting.",
            action: PulseAction(kind: .sendLove, label: "Send Love", deeplink: "amen://user/sarah-mike"),
            minorSafe: true
        )

        let space = PulseCard(
            id: "space1",
            kind: .spaceActivity,
            hero: PulseHero(scrim: .dark, style: "space"),
            eyebrow: "Your Spaces",
            title: "Tuesday Group is in James 2",
            subtitle: "Faith and works — three thoughtful replies since last night. No rush; it’ll be there.",
            action: PulseAction(kind: .openSpace, label: "Open Space", deeplink: "amen://space/tuesday-group"),
            minorSafe: true
        )

        return PulseDigest(
            date: PulseService.dateKey(for: Date()),
            cards: [brief, whatsNew, prayer, event, verse, occasion, space],
            generatedAt: Date(),
            sabbath: false
        )
    }
}
#endif

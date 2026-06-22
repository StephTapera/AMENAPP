// BereanTraditionAwareProvider.swift
// AMEN App — Lightweight doctrinal question classifier + balanced tradition view builder
//
// ARCHITECTURAL NOTE:
// traditionFairnessDirective is an APPEND to the existing Berean system prompt.
// It MUST NOT replace BereanPrompts.bereanChat. Callers append it as a suffix.
// Classification uses keyword/pattern matching — no LLM call, no async network I/O.

import Foundation

// MARK: - BereanTraditionAwareProvider

@MainActor
final class BereanTraditionAwareProvider: TraditionAwareAnswering {

    static let shared = BereanTraditionAwareProvider()
    private init() {}

    // MARK: - Tradition Fairness Directive
    // APPEND this to BereanPrompts.bereanChat — never replace the base prompt.

    static let traditionFairnessDirective = """
    When answering doctrinal questions, acknowledge that sincere Christians hold different views.
    Present the perspective of Reformed, Catholic, Orthodox, Wesleyan, Pentecostal, and Anabaptist
    traditions where relevant. Seek common ground in shared affirmations before noting distinctions.
    """

    // MARK: - Doctrinal Keywords

    private static let doctrinalKeywords: [String] = [
        "salvation", "atonement", "baptism", "predestination", "free will", "freewill",
        "communion", "eucharist", "lord's supper", "purgatory", "saints", "mary",
        "tongues", "glossolalia", "healing", "church governance", "polity",
        "justification", "sanctification", "eschatology", "rapture", "millennium",
        "election", "grace", "works", "faith alone", "sola fide", "infant baptism",
        "believer's baptism", "ordination", "priesthood", "papacy", "pope",
        "transubstantiation", "consubstantiation", "once saved", "eternal security",
        "total depravity", "unconditional election", "limited atonement",
        "irresistible grace", "perseverance of the saints", "arminian", "calvinism"
    ]

    // MARK: - TraditionAwareAnswering

    func classifyDoctrinalQuestion(_ question: String) async -> DoctrinalClassification {
        let lower = question.lowercased()
        let matchedKeyword = Self.doctrinalKeywords.first { lower.contains($0) }
        let isDoctrinal = matchedKeyword != nil
        let confidence: Double = isDoctrinal ? 0.85 : 0.10
        return DoctrinalClassification(
            isDoctrinal: isDoctrinal,
            confidence: confidence,
            question: question
        )
    }

    func buildBalancedAnswer(
        for classification: DoctrinalClassification,
        baseAnswer: String
    ) async -> BalancedAnswer {
        // Feature flag guard — return a stub if flag is off so callers can always call this
        guard AMENFeatureFlags.shared.bereanTraditionAware else {
            return BalancedAnswer(
                traditions: allTraditionKeys.map { TraditionView(key: $0, perspective: "") },
                commonGround: baseAnswer,
                sources: []
            )
        }

        let topic = extractTopic(from: classification.question)
        let perspectives = buildPerspectives(topic: topic)
        let common = commonGroundStatement(for: topic)

        return BalancedAnswer(
            traditions: perspectives,
            commonGround: common,
            sources: ["Scripture", "Historical Confessions of Faith"]
        )
    }

    // MARK: - Private Helpers

    private let allTraditionKeys: [TraditionKey] = [
        .reformed, .catholic, .orthodox, .wesleyan, .pentecostal, .anabaptist
    ]

    private func extractTopic(from question: String) -> String {
        let lower = question.lowercased()
        for keyword in Self.doctrinalKeywords {
            if lower.contains(keyword) { return keyword }
        }
        return "this topic"
    }

    private func commonGroundStatement(for topic: String) -> String {
        switch topic {
        case "baptism", "infant baptism", "believer's baptism":
            return "All traditions affirm that baptism is connected to faith in Jesus Christ and participation in His body."
        case "salvation", "justification":
            return "All traditions affirm that salvation is found in Jesus Christ alone, through His death and resurrection."
        case "communion", "eucharist", "lord's supper", "transubstantiation", "consubstantiation":
            return "All traditions affirm that the Lord's Supper is a sacred act of remembrance and participation in the body and blood of Christ."
        case "predestination", "election", "free will", "freewill":
            return "All traditions affirm that God is sovereign and that human beings bear real moral responsibility."
        case "sanctification":
            return "All traditions affirm that Christians are called to grow in holiness and Christlikeness through the power of the Holy Spirit."
        case "tongues", "glossolalia", "healing":
            return "All traditions affirm that the Holy Spirit is active and that spiritual gifts serve the body of Christ."
        case "eschatology", "rapture", "millennium":
            return "All traditions affirm that Christ will return in glory to judge the living and the dead, and that His kingdom will have no end."
        default:
            return "All Christian traditions share the core affirmation that Jesus Christ is Lord and Savior, attested by Scripture."
        }
    }

    private func buildPerspectives(topic: String) -> [TraditionView] {
        return allTraditionKeys.map { key in
            TraditionView(key: key, perspective: perspective(for: key, topic: topic))
        }
    }

    private func perspective(for key: TraditionKey, topic: String) -> String {
        switch (key, topic) {
        case (.reformed, "baptism"), (.reformed, "infant baptism"), (.reformed, "believer's baptism"):
            return "Infant baptism is practiced as a sign of the covenant, analogous to circumcision in the Old Testament."
        case (.catholic, "baptism"), (.catholic, "infant baptism"):
            return "Baptism is a sacrament that confers sanctifying grace, necessary for salvation; infant baptism is the norm."
        case (.orthodox, "baptism"), (.orthodox, "infant baptism"):
            return "Baptism is a sacrament of rebirth, typically administered to infants and immediately followed by Chrismation."
        case (.wesleyan, "baptism"):
            return "Baptism is a means of grace open to both infants and adults, significant but not strictly necessary for salvation."
        case (.pentecostal, "baptism"), (.pentecostal, "believer's baptism"):
            return "Believer's baptism by immersion follows conversion; water baptism is distinct from Spirit baptism."
        case (.anabaptist, "baptism"), (.anabaptist, "believer's baptism"):
            return "Believer's baptism upon confession of faith is the only valid form; infant baptism is not recognized."

        case (.reformed, "salvation"), (.reformed, "justification"):
            return "Justification is by grace alone through faith alone, with God's sovereign election as its ultimate ground."
        case (.catholic, "salvation"), (.catholic, "justification"):
            return "Justification involves both faith and cooperating grace, and can be developed through the sacramental life."
        case (.orthodox, "salvation"):
            return "Salvation (theosis) is a transformative union with God, a lifelong process of participating in divine nature."
        case (.wesleyan, "salvation"), (.wesleyan, "free will"), (.wesleyan, "freewill"):
            return "God's prevenient grace enables genuine human response; all may freely accept or reject the offer of salvation."
        case (.pentecostal, "salvation"):
            return "Salvation through faith in Christ is confirmed by the witness of the Holy Spirit, often with Spirit baptism evidence."
        case (.anabaptist, "salvation"), (.anabaptist, "free will"):
            return "Salvation requires a genuine personal decision; community accountability is integral to walking out that faith."

        case (.reformed, "predestination"), (.reformed, "election"):
            return "God unconditionally elects individuals to salvation from eternity, wholly apart from foreseen merit."
        case (.catholic, "predestination"), (.catholic, "election"):
            return "Predestination is compatible with human freedom; God's foreknowledge and human cooperation work together."
        case (.orthodox, "predestination"), (.orthodox, "election"):
            return "God foreknows all freely chosen responses; election is not coercive but relational and invitational."
        case (.wesleyan, "predestination"), (.wesleyan, "election"):
            return "Election is conditional on foreseen faith; God genuinely desires all to be saved and provides sufficient grace."
        case (.pentecostal, "predestination"):
            return "God's foreknowledge is emphasized over deterministic election; the offer of salvation is universal."
        case (.anabaptist, "predestination"), (.anabaptist, "election"):
            return "Human freedom and moral accountability are stressed; the church is a community of voluntarily committed disciples."

        default:
            return perspectiveDefault(for: key)
        }
    }

    private func perspectiveDefault(for key: TraditionKey) -> String {
        switch key {
        case .reformed:
            return "The Reformed tradition emphasizes Scripture's supreme authority, God's sovereignty, and salvation by grace alone through faith alone."
        case .catholic:
            return "The Catholic tradition emphasizes the authority of Scripture and Tradition, the sacraments, and the Magisterium as guide to interpretation."
        case .orthodox:
            return "The Orthodox tradition emphasizes the living Tradition of the Church, theosis, and the continuity of worship with the ancient Church."
        case .wesleyan:
            return "The Wesleyan tradition emphasizes prevenient grace, free response to the gospel, sanctification, and holiness of heart and life."
        case .pentecostal:
            return "The Pentecostal tradition emphasizes the ongoing work of the Holy Spirit, spiritual gifts, and baptism in the Spirit as a distinct experience."
        case .anabaptist:
            return "The Anabaptist tradition emphasizes voluntary discipleship, community accountability, nonviolence, and the separation of church and state."
        }
    }
}

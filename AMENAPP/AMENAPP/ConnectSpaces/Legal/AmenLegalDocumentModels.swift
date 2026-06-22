// AmenLegalDocumentModels.swift
// AMEN ConnectSpaces — Legal
//
// Pure model file — no SwiftUI, no Firebase imports.
// All document text is stored as static Swift string literals.
// Written: 2026-06-03

import Foundation

// MARK: - Document Type

enum AmenLegalDocumentType: String, CaseIterable, Identifiable {
    case termsOfService
    case privacyPolicy
    case creatorAgreement
    case churchAgreement
    case organizationAgreement
    case communityStandards
    case contentPolicy
    case refundTerms
    case revenueShareTerms
    case childSafetyPolicy
    case eventTerms
    case aiUsageTerms
    case mentorshipDisclaimer
    case copyrightPolicy

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .termsOfService:       return "Terms of Service"
        case .privacyPolicy:        return "Privacy Policy"
        case .creatorAgreement:     return "Creator Agreement"
        case .churchAgreement:      return "Church Agreement"
        case .organizationAgreement: return "Organization Agreement"
        case .communityStandards:   return "Community Standards"
        case .contentPolicy:        return "Content Policy"
        case .refundTerms:          return "Refund Terms"
        case .revenueShareTerms:    return "Revenue Share Terms"
        case .childSafetyPolicy:    return "Child Safety Policy"
        case .eventTerms:           return "Event Terms"
        case .aiUsageTerms:         return "AI Usage Terms"
        case .mentorshipDisclaimer: return "Mentorship Disclaimer"
        case .copyrightPolicy:      return "Copyright Policy"
        }
    }

    var version: String { "1.0" }

    var effectiveDate: String { "June 3, 2026" }

    /// True for documents that require the user to scroll and explicitly toggle acceptance.
    var requiresExplicitAcceptance: Bool {
        switch self {
        case .creatorAgreement, .churchAgreement, .organizationAgreement, .revenueShareTerms:
            return true
        default:
            return false
        }
    }

    /// Audience tags used by the gate layer to decide which docs to surface.
    var applicableTo: [String] {
        switch self {
        case .termsOfService, .privacyPolicy, .communityStandards,
             .contentPolicy, .childSafetyPolicy, .aiUsageTerms,
             .copyrightPolicy:
            return ["all_users"]
        case .creatorAgreement, .revenueShareTerms, .mentorshipDisclaimer:
            return ["creators"]
        case .churchAgreement:
            return ["churches"]
        case .organizationAgreement:
            return ["organizations"]
        case .refundTerms:
            return ["all_users"]
        case .eventTerms:
            return ["creators", "churches", "organizations"]
        }
    }
}

// MARK: - Acceptance Record

struct AmenLegalAcceptanceRecord: Codable {
    let documentType: String   // AmenLegalDocumentType.rawValue
    let version: String
    let acceptedAt: Date
    let userId: String
}

// MARK: - Document Content

enum AmenLegalDocumentContent {

    // swiftlint:disable function_body_length
    static func content(for type: AmenLegalDocumentType) -> String {
        switch type {
        case .termsOfService:
            return termsOfService
        case .privacyPolicy:
            return privacyPolicy
        case .creatorAgreement:
            return creatorAgreement
        case .churchAgreement:
            return churchAgreement
        case .organizationAgreement:
            return organizationAgreement
        case .communityStandards:
            return communityStandards
        case .contentPolicy:
            return contentPolicy
        case .refundTerms:
            return refundTerms
        case .revenueShareTerms:
            return revenueShareTerms
        case .childSafetyPolicy:
            return childSafetyPolicy
        case .eventTerms:
            return eventTerms
        case .aiUsageTerms:
            return aiUsageTerms
        case .mentorshipDisclaimer:
            return mentorshipDisclaimer
        case .copyrightPolicy:
            return copyrightPolicy
        }
    }
    // swiftlint:enable function_body_length

    // MARK: - Terms of Service

    private static let termsOfService = """
    AMEN TERMS OF SERVICE

    Effective Date: June 3, 2026

    PLEASE READ THESE TERMS CAREFULLY BEFORE USING THE AMEN PLATFORM. BY CREATING AN ACCOUNT OR ACCESSING ANY PART OF THE SERVICE, YOU AGREE TO BE BOUND BY THESE TERMS.

    1. ACCEPTANCE AND ELIGIBILITY

    The AMEN platform ("Service") is operated by AMEN, Inc. ("AMEN," "we," "our"). You must be at least 13 years of age to use the Service. Users under 18 must have parental or guardian consent. By using the Service, you represent that you meet these requirements.

    2. PERMITTED USE AND CONDUCT

    You agree to use the Service only for lawful purposes consistent with these Terms and the AMEN Community Standards. You will not use the Service to harass, defame, or harm others; distribute malware or engage in phishing; impersonate any person or organization; scrape or copy data without authorization; or violate any applicable law or regulation.

    3. CONTENT OWNERSHIP AND LICENSE

    You retain ownership of content you post ("Your Content"). By posting, you grant AMEN a non-exclusive, royalty-free, worldwide license to display, distribute, and promote Your Content within the Service for the purpose of operating and improving the platform. This license terminates when you delete Your Content or close your account, subject to reasonable backup retention periods.

    4. AMEN'S RIGHT TO MODERATE

    AMEN reserves the right, but not the obligation, to review, refuse, remove, or restrict access to any content that violates these Terms, Community Standards, or applicable law. Moderation decisions may be appealed through the in-app appeals process.

    5. SUBSCRIPTION AND PAYMENTS

    Certain features require a paid subscription. Subscription fees are billed in advance on a recurring basis. All payments are processed through the Apple App Store or authorized payment providers. Prices are shown inclusive of applicable taxes where required by law.

    6. REFUNDS

    Purchases made through the Apple App Store are subject to Apple's refund policies. AMEN does not process direct refunds for App Store purchases. For subscriptions purchased outside the App Store, please contact support@amen.app within 14 days of the charge.

    7. INTELLECTUAL PROPERTY

    The AMEN name, logo, and all platform elements are the intellectual property of AMEN, Inc. Nothing in these Terms transfers any rights in AMEN's intellectual property to you.

    8. TERMINATION

    AMEN may suspend or terminate your account at any time for violation of these Terms. You may terminate your account at any time from Settings > Account > Delete Account. Termination does not waive any claims arising before the termination date.

    9. DISCLAIMER OF WARRANTIES

    THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTY OF ANY KIND. AMEN DOES NOT WARRANT THAT THE SERVICE WILL BE ERROR-FREE, UNINTERRUPTED, OR FREE OF HARMFUL COMPONENTS.

    10. LIMITATION OF LIABILITY

    TO THE MAXIMUM EXTENT PERMITTED BY LAW, AMEN'S TOTAL LIABILITY ARISING FROM YOUR USE OF THE SERVICE SHALL NOT EXCEED THE GREATER OF $100 OR THE FEES YOU PAID TO AMEN IN THE 12 MONTHS PRECEDING THE CLAIM.

    11. DISPUTE RESOLUTION

    Any dispute arising from these Terms shall be resolved by binding individual arbitration under the rules of JAMS, conducted in San Francisco, California. Class actions are waived to the extent permitted by law.

    12. GOVERNING LAW

    These Terms are governed by the laws of the State of California, without regard to conflict-of-law principles.

    13. CHANGES TO THESE TERMS

    AMEN may update these Terms from time to time. Continued use of the Service after notice of changes constitutes acceptance of the revised Terms.

    14. CONTACT

    AMEN, Inc. | 1234 Faith Avenue, San Francisco, CA 94103 | legal@amen.app
    """

    // MARK: - Privacy Policy

    private static let privacyPolicy = """
    AMEN PRIVACY POLICY

    Effective Date: June 3, 2026

    AMEN, Inc. ("AMEN") is committed to protecting your privacy. This Privacy Policy describes how we collect, use, share, and protect information about you.

    1. INFORMATION WE COLLECT

    Account Information: Name, email address, profile photo, denomination, and any information you choose to add to your profile.

    Usage Data: Features used, content viewed, prayers posted, searches conducted, and interaction patterns within the Service.

    Device and Technical Data: Device identifiers, IP address, operating system version, app version, and crash logs collected for security and diagnostic purposes.

    Communications: Messages, prayer requests, and other content you send through the Service.

    Payment Data: Transaction identifiers provided by Apple or Stripe. We do not store full credit card numbers.

    2. HOW WE USE YOUR INFORMATION

    We use your information to: operate and improve the Service; personalize your experience and content recommendations; power AI features (including Berean AI) subject to your consent; detect and prevent fraud, abuse, and safety violations; communicate service updates and respond to support requests; and comply with legal obligations.

    3. AI FEATURES AND DATA

    Certain features powered by artificial intelligence may process your content to generate summaries, suggestions, or insights. AI processing is subject to your consent, is disclosed at the point of activation, and is governed by the AMEN AI Usage Terms.

    4. DATA SHARING

    We do not sell your personal information. We share data only: with service providers who assist in operating the platform (under confidentiality agreements); to comply with valid legal process or protect the safety of users; with your consent; or as part of a merger or acquisition, with advance notice to you.

    5. DATA RETENTION

    We retain your information for as long as your account is active and for a reasonable period thereafter for backup, legal compliance, and dispute resolution purposes. You may request deletion of your account and associated data at any time via Settings > Account > Delete Account.

    6. YOUR RIGHTS

    California Residents (CCPA): You have the right to know what personal information we collect, request deletion, and opt out of sale (we do not sell data). To exercise your rights, email privacy@amen.app.

    European Residents (GDPR): You have the right to access, correct, delete, and port your data, and to object to or restrict processing. Contact privacy@amen.app for requests.

    Children (COPPA): We do not knowingly collect personal information from children under 13 without verifiable parental consent. If we discover we have collected such information, we will delete it promptly.

    7. SECURITY

    We implement industry-standard technical and organizational safeguards, including encryption in transit (TLS) and at rest. No system is completely secure; please use a strong, unique password and report suspected security issues to security@amen.app.

    8. CONTACT

    Privacy Officer | AMEN, Inc. | privacy@amen.app | 1234 Faith Avenue, San Francisco, CA 94103
    """

    // MARK: - Creator Agreement

    private static let creatorAgreement = """
    AMEN CREATOR AGREEMENT

    Effective Date: June 3, 2026

    This Creator Agreement ("Agreement") supplements the AMEN Terms of Service and governs your participation as a creator on the AMEN platform. BY ACCEPTING THIS AGREEMENT, YOU REPRESENT THAT YOU ARE AT LEAST 18 YEARS OF AGE AND HAVE THE AUTHORITY TO ENTER INTO A BINDING CONTRACT.

    1. ELIGIBILITY

    You must be at least 18 years of age. You must maintain a verified AMEN account in good standing. You must not be barred from receiving payments under applicable law. Creators who represent a church, organization, or nonprofit must complete the Church or Organization Agreement instead.

    2. CONTENT OWNERSHIP AND LICENSE

    You retain full ownership of the content you publish ("Creator Content"). By publishing, you grant AMEN a non-exclusive, royalty-free, worldwide, sublicensable license to host, display, distribute, clip, and promote your Creator Content within the Service and in marketing materials for the Service. This license terminates upon deletion of the content, subject to reasonable propagation delays.

    3. PROHIBITED CONTENT

    Creator Content must not: misrepresent Scripture or present theological opinion as established canon without appropriate disclosure; solicit unauthorized donations or fundraise outside the AMEN platform for personal gain; include sexually explicit material, hate speech, or content that endangers minors; promote illegal activity; or impersonate any person, church, or organization.

    4. REVENUE AND PAYOUTS

    Gross subscription revenue is collected by AMEN and disbursed to creators monthly, approximately 30 days after the close of each calendar month, subject to a minimum payout threshold of $25 USD. AMEN retains a platform fee of 15% of gross revenue before disbursement. Stripe processing fees are passed through at cost. Full details are in the Revenue Share Terms.

    5. TAX RESPONSIBILITY

    You are solely responsible for reporting and paying all taxes applicable to your creator earnings. AMEN will issue a Form 1099-K where required under applicable U.S. law. Non-U.S. creators are responsible for compliance with their local tax laws.

    6. INTELLECTUAL PROPERTY

    You warrant that your Creator Content does not infringe any third-party intellectual property rights. You agree to indemnify AMEN against claims arising from your Creator Content.

    7. TERMINATION OF CREATOR STATUS

    AMEN may terminate your creator status at any time for violation of this Agreement, the Terms of Service, or Community Standards. Outstanding earned and vested amounts will be paid within 60 days of termination, minus any chargebacks, refunds, or platform fees owed.

    8. MODIFICATIONS

    AMEN may update this Agreement with 30 days' advance notice. Continued operation as a creator after notice constitutes acceptance.
    """

    // MARK: - Church Agreement

    private static let churchAgreement = """
    AMEN CHURCH AGREEMENT

    Effective Date: June 3, 2026

    This Church Agreement governs the use of AMEN Spaces and Creator features by registered churches and denominational bodies. It supplements the AMEN Terms of Service.

    1. ELIGIBILITY AND VERIFICATION

    The church must be a recognized religious body with a valid Employer Identification Number (EIN) or equivalent. A designated authorized representative must complete the AMEN host onboarding and KYC process. The representative warrants they have authority to bind the church to this Agreement.

    2. PERMITTED USE

    Churches may use AMEN Spaces to facilitate community gatherings, worship services, discipleship programs, prayer groups, and fundraising for legitimate ministry purposes.

    3. PROHIBITED CONDUCT

    Churches may not use the platform to advocate for political candidates, conduct deceptive fundraising, or solicit funds for purposes inconsistent with those disclosed to members.

    4. REVENUE AND REPORTING

    Church revenue is subject to the Revenue Share Terms. AMEN will issue applicable tax documentation. Churches are responsible for their own tax-exempt status and IRS compliance.

    5. CONTENT STANDARDS

    All content published by the church must comply with AMEN Community Standards and Content Policy. The authorized representative is responsible for moderating the church's Space.

    6. TERMINATION

    AMEN may suspend or terminate a church account for violations of this Agreement. The church may close its Space at any time from Settings > Space Management.

    For questions, contact churchsupport@amen.app.
    """

    // MARK: - Organization Agreement

    private static let organizationAgreement = """
    AMEN ORGANIZATION AGREEMENT

    Effective Date: June 3, 2026

    This Organization Agreement governs the use of AMEN Spaces by para-church organizations, ministries, nonprofits, and faith-based entities. It supplements the AMEN Terms of Service.

    1. ELIGIBILITY

    The organization must have a valid EIN or equivalent government registration. An authorized representative must complete the AMEN host onboarding process and provide accurate entity information.

    2. PERMITTED USE

    Organizations may host Spaces for community building, educational content, fundraising for disclosed charitable purposes, and ministry programming.

    3. PROHIBITED CONDUCT

    Organizations may not misrepresent their mission, collect funds for undisclosed purposes, or engage in conduct that would jeopardize their nonprofit status or violate applicable charity solicitation laws.

    4. REVENUE SHARING

    Revenue sharing is subject to the Revenue Share Terms. Organizations bear full responsibility for tax compliance.

    5. MODERATION RESPONSIBILITY

    Organizations must designate at least one moderator for their Space. The organization is responsible for all content published within its Space.

    6. TERMINATION

    Either party may terminate this Agreement with 30 days' written notice. AMEN may terminate immediately for material breach.

    Contact organizationsupport@amen.app for assistance.
    """

    // MARK: - Community Standards

    private static let communityStandards = """
    AMEN COMMUNITY STANDARDS

    Effective Date: June 3, 2026

    AMEN is a platform built for faith communities. These Community Standards define the behavior expected of every member. They apply to all content, comments, messages, and interactions on the platform.

    ZERO TOLERANCE VIOLATIONS

    The following conduct will result in immediate account suspension or permanent ban without warning:

    — Hate speech, slurs, or content that dehumanizes individuals based on race, ethnicity, national origin, gender, sexual orientation, disability, or religion.
    — Sexual exploitation, grooming, or any content that endangers or sexualizes minors.
    — Harassment, threats, or sustained targeting of individuals.
    — Impersonation of pastors, churches, organizations, or other users with intent to deceive.
    — Presenting personal theological opinion as Scripture, canon, or established doctrine without appropriate disclosure, in a manner designed to mislead.
    — Deceptive fundraising, including soliciting donations for undisclosed or false purposes.

    MODERATION PROCESS

    Reported content is reviewed by the AMEN Trust & Safety team. For content meeting zero-tolerance criteria, removal is immediate and automatic pending human review. For other violations, a warning is issued on first offense and escalating action is taken for repeated violations.

    APPEALS

    Every moderation action may be appealed within 30 days through Settings > Help > Appeal a Decision. Appeals are reviewed by a human moderator not involved in the original decision. Outcomes of appeals are final.

    SCRIPTURE REFERENCES

    Scripture quotations included in user content should be attributed to a recognized translation (e.g., ESV, NIV, KJV, NASB). Paraphrase or personal interpretation should be identified as such.

    REPORTING

    To report a violation, tap the "..." menu on any post, comment, or profile and select "Report." Reports are reviewed within 24 hours for urgent safety issues and within 72 hours for other reports.

    For urgent child safety concerns, contact childssafety@amen.app immediately.
    """

    // MARK: - Content Policy

    private static let contentPolicy = """
    AMEN CONTENT POLICY

    Effective Date: June 3, 2026

    This Content Policy provides specific guidance on permitted and prohibited content on the AMEN platform. It is read in conjunction with the Community Standards.

    PERMITTED CONTENT

    — Faith-based teaching, preaching, and theological discussion.
    — Worship music and creative expressions of faith.
    — Prayer requests and testimonies.
    — Community announcements and event promotion.
    — Educational and discipleship content.
    — Scripture references with appropriate attribution.

    PROHIBITED CONTENT

    — Pornographic or sexually explicit material.
    — Graphic violence not serving a legitimate educational or documentary purpose.
    — Content that promotes self-harm or suicide.
    — Spam, unsolicited commercial messages, or multi-level marketing solicitations.
    — Misinformation presented as factual, including false medical or financial claims.
    — Malware, phishing, or content designed to steal credentials.

    AI-GENERATED CONTENT

    AI-generated or substantially AI-edited content must be labeled as such using the AMEN synthetic media label. Failure to disclose may result in content removal.

    COPYRIGHT

    Users must have the right to share any content they post. Music, video clips, and images are subject to copyright law. AMEN will respond to valid DMCA takedown notices. See the Copyright Policy for details.

    ENFORCEMENT

    Violations may result in content removal, feature restriction, suspension, or permanent ban, proportionate to the severity and frequency of violation.
    """

    // MARK: - Refund Terms

    private static let refundTerms = """
    AMEN REFUND TERMS

    Effective Date: June 3, 2026

    1. APP STORE PURCHASES

    All subscriptions and in-app purchases made through the Apple App Store are subject to Apple's media services terms and refund policies. AMEN does not process refunds for App Store transactions. To request a refund for an App Store purchase, please visit reportaproblem.apple.com.

    2. DIRECT PURCHASES

    For subscriptions or purchases processed directly (outside the App Store), AMEN offers refunds within 14 days of the initial charge if the Service was not accessible due to a platform outage attributable to AMEN. Contact support@amen.app with your order details.

    3. SPACE MEMBERSHIP REFUNDS

    Space memberships are generally non-refundable after the membership period has begun. If a Space is shut down by AMEN for violations of our policies, any unused subscription days will be refunded to members within 30 business days.

    4. CREATOR PAYOUTS

    Creator earnings that have been disbursed are not subject to clawback except in cases of fraud, violation of the Creator Agreement, or chargebacks from members. See the Revenue Share Terms for chargeback policy.

    5. CONTACT

    For billing questions, contact billing@amen.app.
    """

    // MARK: - Revenue Share Terms

    private static let revenueShareTerms = """
    AMEN REVENUE SHARE TERMS

    Effective Date: June 3, 2026

    These Revenue Share Terms govern the calculation and disbursement of earnings for AMEN creators, churches, and organizations. They form part of the applicable Creator Agreement, Church Agreement, or Organization Agreement.

    1. GROSS REVENUE

    Gross revenue includes all subscription fees collected from members of your Space during a calendar month, net of applicable sales taxes collected by AMEN on your behalf.

    2. PLATFORM FEE

    AMEN retains a platform fee of 15% of gross revenue. This fee covers platform infrastructure, payment processing overhead (beyond Stripe's pass-through), trust and safety operations, and product development.

    3. STRIPE PROCESSING FEES

    Stripe payment processing fees (currently approximately 2.9% + $0.30 per transaction for U.S. cards) are passed through at cost and deducted before calculating your net payout. Fee rates vary for international cards.

    4. MINIMUM PAYOUT THRESHOLD

    Earnings must reach a minimum of $25 USD before disbursement. Amounts below $25 roll over to the following month. If your account is closed with a balance below $25, contact support@amen.app to arrange a final disbursement.

    5. PAYOUT SCHEDULE

    Payouts are processed monthly, approximately 30 days after the close of each calendar month. This hold period allows for refund and chargeback resolution.

    6. INTERNATIONAL PAYOUTS

    International payouts are subject to Stripe's supported country list and applicable currency conversion. Additional fees may apply. AMEN is not responsible for currency fluctuations.

    7. TAX REPORTING — 1099-K

    U.S. creators who receive more than $600 in gross payments in a calendar year (subject to IRS thresholds) will receive a Form 1099-K. You are responsible for reporting all income regardless of whether a 1099-K is issued.

    8. CO-HOST REVENUE SPLITS

    If you have designated co-hosts, revenue splits are configured in Space Settings. AMEN distributes to the primary account holder. Internal splits between co-hosts are your responsibility.

    9. CHARGEBACKS

    If a member initiates a chargeback, the disputed amount is deducted from your next payout. You may contest chargebacks by providing evidence through the AMEN chargeback dispute process within 7 days of notice.

    10. MODIFICATIONS

    AMEN may update the platform fee with 60 days' advance written notice. Your continued operation as a creator after the notice period constitutes acceptance.
    """

    // MARK: - Child Safety Policy

    private static let childSafetyPolicy = """
    AMEN CHILD SAFETY POLICY

    Effective Date: June 3, 2026

    AMEN takes child safety with the utmost seriousness. This policy describes our commitments and obligations with respect to the safety of minors on the platform.

    1. AGE REQUIREMENTS AND COPPA COMPLIANCE

    Users under 13 may not create accounts. Users aged 13–17 require verifiable parental or guardian consent before accessing certain features. AMEN complies with the Children's Online Privacy Protection Act (COPPA) and does not knowingly collect personal information from children under 13 without parental consent.

    If we discover that a user under 13 has registered without parental consent, we will delete the account and associated data promptly.

    2. PROHIBITED INTERACTIONS INVOLVING MINORS

    The following are strictly prohibited and will result in immediate account termination and reporting to law enforcement:

    — Soliciting, producing, distributing, or possessing child sexual abuse material (CSAM) or any sexualized content involving minors.
    — Grooming behavior, including unsolicited contact with minors, gift solicitation, or attempts to move communication off-platform.
    — Adults misrepresenting their age or identity to interact with minors.

    3. CONTENT SCANNING

    All user-uploaded media is scanned using industry-standard hash-matching (PhotoDNA or equivalent) and AI-based classifiers before publication. Content flagged as potential CSAM is blocked immediately and reported to the National Center for Missing & Exploited Children (NCMEC) as required by federal law (18 U.S.C. § 2258A).

    4. PARENTAL CONSENT GATEWAY

    Users who indicate they are under 18 during registration are directed to a parental consent flow. Parents or guardians can manage their child's account settings, restrict direct messages, and request data deletion at any time by contacting privacy@amen.app.

    5. MANDATORY REPORTING

    AMEN employees and contractors who become aware of potential CSAM or child exploitation are required to report to NCMEC's CyberTipline and cooperate fully with law enforcement investigations.

    6. REPORTING SUSPECTED VIOLATIONS

    If you suspect a child is at risk or encounter content that violates this policy, report it immediately via the in-app report feature or email childsafety@amen.app. Urgent reports are reviewed within 1 hour.

    7. CONTACT

    Child Safety Officer | AMEN, Inc. | childsafety@amen.app
    """

    // MARK: - Event Terms

    private static let eventTerms = """
    AMEN EVENT TERMS

    Effective Date: June 3, 2026

    These Event Terms govern the creation, promotion, and hosting of live and virtual events within AMEN Spaces.

    1. EVENT CREATION

    Only verified hosts (creators, churches, and organizations that have completed host onboarding) may create paid or gated events. Free community events may be created by any Space member with the appropriate role.

    2. TICKET SALES AND REFUNDS

    Event ticket revenue is subject to the Revenue Share Terms. Hosts may set their own refund policy for events, provided it is disclosed to attendees before purchase. If an event is cancelled by the host, full refunds must be issued within 14 days.

    3. RECORDING AND REPLAY

    By hosting an event on AMEN, you grant AMEN a license to record, store, and make available the event replay to your Space members. You may disable replay availability in event settings.

    4. HOST CONDUCT

    Hosts are responsible for moderating their events and ensuring compliance with Community Standards. AMEN may remove content from recorded events that violates platform policies.

    5. TECHNICAL AVAILABILITY

    AMEN does not guarantee uninterrupted live event delivery and is not liable for technical failures beyond its reasonable control.

    Contact eventsupport@amen.app for event-related assistance.
    """

    // MARK: - AI Usage Terms

    private static let aiUsageTerms = """
    AMEN AI USAGE TERMS

    Effective Date: June 3, 2026

    These AI Usage Terms describe how AI-powered features operate within the AMEN platform.

    1. AI FEATURES

    AMEN offers AI-assisted features including: scripture contextualisation (Berean AI), content summarisation, transcript search, automated clip generation, AI chat companions, and personalized content recommendations.

    2. CONSENT

    AI features that process your personal content (messages, prayer requests, voice) require your explicit opt-in consent, granted at the point of feature activation. You may revoke consent at any time from Settings > AI & Privacy.

    3. DATA USE

    Content processed by AI features is used solely to provide the feature to you. It is not used to train foundational AI models without separate, explicit consent.

    4. AI LIMITATIONS AND DISCLAIMERS

    AI-generated content is not theological advice, pastoral counseling, medical advice, or legal advice. AMEN's AI features are tools to assist your faith journey, not substitutes for human pastoral care or professional counsel.

    AI may make errors in scriptural interpretation. Always consult a qualified pastor or theologian for significant theological questions.

    5. SYNTHETIC MEDIA

    AI-generated or AI-substantially-edited media must be labeled as such using the AMEN synthetic media disclosure. Circumventing this disclosure may result in content removal.

    6. SAFETY LAYER

    All AI inputs and outputs pass through AMEN's safety layer. Crisis signals (self-harm, abuse, emergency) detected by AI are routed to human review and appropriate resources, not handled autonomously.

    Contact ai@amen.app with questions about AI features.
    """

    // MARK: - Mentorship Disclaimer

    private static let mentorshipDisclaimer = """
    AMEN MENTORSHIP DISCLAIMER

    Effective Date: June 3, 2026

    1. NATURE OF MENTORSHIP

    AMEN Spaces may facilitate mentorship connections between members. Mentorship on AMEN is peer-based and informal. It is not professional pastoral counseling, psychological therapy, legal advice, financial advice, or medical care.

    2. PARTICIPANT RESPONSIBILITIES

    Both mentors and mentees are responsible for maintaining appropriate boundaries and for reporting any conduct that violates Community Standards. AMEN does not vet, credential, or certify mentors.

    3. LIMITATION OF LIABILITY

    AMEN is not liable for the quality, accuracy, or outcomes of any mentorship relationship facilitated through the platform. Participation is at your own risk.

    4. MANDATORY REPORTING

    If a mentor or mentee discloses information suggesting imminent risk of harm to self or others, both parties and AMEN have a moral and potentially legal obligation to contact emergency services.

    Contact support@amen.app with concerns about a mentorship relationship.
    """

    // MARK: - Copyright Policy

    private static let copyrightPolicy = """
    AMEN COPYRIGHT POLICY

    Effective Date: June 3, 2026

    1. YOUR CONTENT

    You must own or have the right to share all content you post on AMEN. This includes music, video clips, images, written text, and any other copyrightable material.

    2. WORSHIP MUSIC

    Users sharing worship music must hold an appropriate license (e.g., CCLI license) for public performance and digital distribution. AMEN is not a substitute for obtaining required licenses.

    3. DMCA TAKEDOWN PROCESS

    If you believe content on AMEN infringes your copyright, send a notice to copyright@amen.app containing: your contact information; identification of the copyrighted work; identification of the infringing content; a statement of good faith belief; and your signature. Takedown notices are processed within 10 business days.

    4. COUNTER-NOTICES

    If your content is removed in response to a DMCA notice you believe to be incorrect, you may file a counter-notice with the information required by 17 U.S.C. § 512(g)(3). Counter-notices are reviewed within 14 business days.

    5. REPEAT INFRINGERS

    AMEN will terminate accounts of users who repeatedly infringe copyright after appropriate notice and opportunity to cure.

    Contact copyright@amen.app for copyright matters.
    """
}

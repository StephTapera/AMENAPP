#!/usr/bin/env node
/**
 * seed-giving-data.js
 * Populates Firestore with sample data for the AMEN Giving feature:
 *   - organizations/{id}
 *   - cause_briefs/{id}
 *   - disaster_events/{id}
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json node scripts/seed-giving-data.js
 *   node scripts/seed-giving-data.js --service-account /path/to/serviceAccount.json
 *   node scripts/seed-giving-data.js --dry-run
 *
 * firebase-admin is resolved from Backend/functions/node_modules so no extra
 * npm install is needed in this directory.
 */

"use strict";

const path = require("path");

// ── Resolve firebase-admin from the Backend functions tree ──────────────────
const ADMIN_MODULE = path.resolve(
  __dirname,
  "../Backend/functions/node_modules/firebase-admin"
);
let admin;
try {
  admin = require(ADMIN_MODULE);
} catch (e) {
  console.error(
    "Could not load firebase-admin from Backend/functions/node_modules.\n" +
      "Run `npm install` inside Backend/functions first, or install firebase-admin globally.\n" +
      e.message
  );
  process.exit(1);
}

// ── CLI args ─────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const DRY_RUN = args.includes("--dry-run");
const saIdx = args.indexOf("--service-account");
const SA_PATH = saIdx !== -1 ? args[saIdx + 1] : null;

// ── Firebase init ─────────────────────────────────────────────────────────────
function initFirebase() {
  let credential;
  if (SA_PATH) {
    credential = admin.credential.cert(path.resolve(SA_PATH));
  } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    credential = admin.credential.applicationDefault();
  } else {
    console.error(
      "No credentials found.\n" +
        "Supply --service-account /path/to/key.json  OR\n" +
        "set GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json\n" +
        "(In --dry-run mode credentials are not required.)"
    );
    if (!DRY_RUN) process.exit(1);
  }

  if (!DRY_RUN) {
    admin.initializeApp({ credential });
  }
}

// ── Timestamp helper ──────────────────────────────────────────────────────────
const ts = (iso) =>
  DRY_RUN
    ? iso
    : admin.firestore.Timestamp.fromDate(new Date(iso));

// ═══════════════════════════════════════════════════════════════════════════════
// DATA
// ═══════════════════════════════════════════════════════════════════════════════

// ── 8 Organizations ──────────────────────────────────────────────────────────
const ORGANIZATIONS = [
  // 1. Disaster Relief — international evangelical
  {
    id: "org-global-relief-purse",
    name: "Grace in Crisis International",
    slug: "grace-in-crisis-international",
    description:
      "Mobilizes emergency relief and long-term recovery across the globe, " +
      "distributing food, shelter kits, and medical supplies in the name of Christ. " +
      "Known for rapid on-the-ground deployment within 72 hours of a major disaster.",
    causeCategories: ["Disaster Relief", "Refugee Resettlement"],
    serviceRegions: [
      { country: "USA", isLocal: false, isGlobal: true },
      { country: "Global", isLocal: false, isGlobal: true },
    ],
    theologicalAffiliations: ["Evangelical"],
    givingStylesSupported: ["One-time", "Recurring", "In-kind"],
    websiteUrl: "https://example.org/gci",
    donationUrl: "https://example.org/gci/give",
    volunteerUrl: "https://example.org/gci/volunteer",
    logoUrl: null,
    isActive: true,
    rankingEligibility: true,
    isLocalPartner: false,
    isDisasterResponder: true,
    trustBadges: [
      "501(c)(3)",
      "ECFA",
      "Charity Navigator",
      "Field response active",
      "Financials current",
    ],
    trustScore: 0.96,
    transparency: {
      programExpenseRatio: 0.88,
      adminExpenseRatio: 0.06,
      fundraisingExpenseRatio: 0.06,
      fiscalYear: "2024",
      sourceProviders: ["Charity Navigator", "ECFA"],
      verificationStatus: "verified",
      verifiedAt: ts("2025-03-15T00:00:00Z"),
      confidence: "high",
      notes: null,
    },
    giftImpacts: [
      {
        id: "gi-gci-1",
        amount: 25,
        description: "Provides one emergency food box for a displaced family.",
        fiscalYear: "2024",
        sourceUrl: "https://example.org/gci/impact",
        verifiedAt: ts("2025-01-10T00:00:00Z"),
        confidence: "high",
      },
      {
        id: "gi-gci-2",
        amount: 150,
        description: "Supplies a complete shelter kit for one household.",
        fiscalYear: "2024",
        sourceUrl: "https://example.org/gci/impact",
        verifiedAt: ts("2025-01-10T00:00:00Z"),
        confidence: "high",
      },
    ],
    recentActions: [
      {
        id: "ra-gci-1",
        title: "East Africa Flood Response",
        summary:
          "Deployed 12 relief teams to flood-affected regions, distributing clean water, " +
          "food, and hygiene kits to 40,000 people in three weeks.",
        region: "East Africa",
        occurredAt: ts("2026-04-01T00:00:00Z"),
        verifiedAt: ts("2026-04-20T00:00:00Z"),
        sourceUrl: "https://example.org/gci/updates/flood-2026",
        confidence: "high",
      },
    ],
  },

  // 2. Foster Care — national evangelical
  {
    id: "org-foster-covenant",
    name: "Covenant Foster Network",
    slug: "covenant-foster-network",
    description:
      "Equips and supports churches to care for foster and adoptive families through " +
      "training, respite, and community wrap-around services. Partners with over 800 " +
      "congregations nationally.",
    causeCategories: ["Foster Care"],
    serviceRegions: [
      { country: "USA", isLocal: false, isGlobal: false },
    ],
    theologicalAffiliations: ["Evangelical", "Non-denominational"],
    givingStylesSupported: ["One-time", "Recurring", "Time / Volunteer"],
    websiteUrl: "https://example.org/cfn",
    donationUrl: "https://example.org/cfn/give",
    volunteerUrl: "https://example.org/cfn/serve",
    logoUrl: null,
    isActive: true,
    rankingEligibility: true,
    isLocalPartner: false,
    isDisasterResponder: false,
    trustBadges: ["501(c)(3)", "ECFA", "Candid / GuideStar", "Financials current"],
    trustScore: 0.91,
    transparency: {
      programExpenseRatio: 0.82,
      adminExpenseRatio: 0.09,
      fundraisingExpenseRatio: 0.09,
      fiscalYear: "2024",
      sourceProviders: ["Candid / GuideStar"],
      verificationStatus: "verified",
      verifiedAt: ts("2025-02-01T00:00:00Z"),
      confidence: "high",
      notes: null,
    },
    giftImpacts: [
      {
        id: "gi-cfn-1",
        amount: 50,
        description:
          "Funds one hour of trauma-informed parenting coaching for a foster family.",
        fiscalYear: "2024",
        sourceUrl: null,
        verifiedAt: ts("2025-01-15T00:00:00Z"),
        confidence: "medium",
      },
    ],
    recentActions: [
      {
        id: "ra-cfn-1",
        title: "Church Partner Summit 2026",
        summary:
          "Trained 350 church leaders in trauma-informed care and helped launch 40 new " +
          "foster support circles across 15 states.",
        region: "United States",
        occurredAt: ts("2026-02-14T00:00:00Z"),
        verifiedAt: ts("2026-03-01T00:00:00Z"),
        sourceUrl: "https://example.org/cfn/summit-2026",
        confidence: "high",
      },
    ],
  },

  // 3. Persecuted Church — denominationally neutral
  {
    id: "org-open-doors-beacon",
    name: "Beacon for the Persecuted Church",
    slug: "beacon-persecuted-church",
    description:
      "Serves Christians facing persecution in more than 60 countries through Bible " +
      "distribution, discipleship training, trauma care, and emergency family support. " +
      "Advocates globally for religious freedom.",
    causeCategories: ["Persecuted Church"],
    serviceRegions: [
      { country: "Global", isLocal: false, isGlobal: true },
    ],
    theologicalAffiliations: ["Denominationally Neutral"],
    givingStylesSupported: ["One-time", "Recurring"],
    websiteUrl: "https://example.org/bpc",
    donationUrl: "https://example.org/bpc/give",
    volunteerUrl: null,
    logoUrl: null,
    isActive: true,
    rankingEligibility: true,
    isLocalPartner: false,
    isDisasterResponder: false,
    trustBadges: [
      "501(c)(3)",
      "ECFA",
      "BBB Wise Giving",
      "Financials current",
    ],
    trustScore: 0.93,
    transparency: {
      programExpenseRatio: 0.85,
      adminExpenseRatio: 0.08,
      fundraisingExpenseRatio: 0.07,
      fiscalYear: "2024",
      sourceProviders: ["ECFA", "BBB Wise Giving"],
      verificationStatus: "verified",
      verifiedAt: ts("2025-04-01T00:00:00Z"),
      confidence: "high",
      notes: null,
    },
    giftImpacts: [
      {
        id: "gi-bpc-1",
        amount: 10,
        description: "Places a Bible with a persecuted believer who has never owned one.",
        fiscalYear: "2024",
        sourceUrl: "https://example.org/bpc/impact",
        verifiedAt: ts("2025-01-01T00:00:00Z"),
        confidence: "high",
      },
      {
        id: "gi-bpc-2",
        amount: 200,
        description:
          "Sponsors one month of trauma care and safe-house support for a family fleeing persecution.",
        fiscalYear: "2024",
        sourceUrl: "https://example.org/bpc/impact",
        verifiedAt: ts("2025-01-01T00:00:00Z"),
        confidence: "high",
      },
    ],
    recentActions: [
      {
        id: "ra-bpc-1",
        title: "North Africa Bible Distribution",
        summary:
          "Distributed 80,000 Bibles across three North African countries through underground networks.",
        region: "North Africa",
        occurredAt: ts("2026-01-20T00:00:00Z"),
        verifiedAt: ts("2026-02-05T00:00:00Z"),
        sourceUrl: "https://example.org/bpc/updates/na-bibles-2026",
        confidence: "medium",
      },
    ],
  },

  // 4. Homelessness — local partner, non-denominational
  {
    id: "org-city-table-ministries",
    name: "City Table Ministries",
    slug: "city-table-ministries",
    description:
      "Provides hot meals, emergency shelter, and a 12-month transitional living " +
      "program for adults experiencing homelessness in the greater metro area. Rooted " +
      "in local churches and staffed largely by volunteers.",
    causeCategories: ["Homelessness", "Local Church & Benevolence"],
    serviceRegions: [
      {
        country: "USA",
        state: "TX",
        metro: "Dallas-Fort Worth",
        isLocal: true,
        isGlobal: false,
      },
    ],
    theologicalAffiliations: ["Non-denominational"],
    givingStylesSupported: [
      "One-time",
      "Recurring",
      "In-kind",
      "Time / Volunteer",
    ],
    websiteUrl: "https://example.org/ctm",
    donationUrl: "https://example.org/ctm/give",
    volunteerUrl: "https://example.org/ctm/volunteer",
    logoUrl: null,
    isActive: true,
    rankingEligibility: true,
    isLocalPartner: true,
    isDisasterResponder: false,
    trustBadges: [
      "501(c)(3)",
      "Local partner verified",
      "Pastoral reviewed",
      "Financials current",
    ],
    trustScore: 0.87,
    transparency: {
      programExpenseRatio: 0.79,
      adminExpenseRatio: 0.12,
      fundraisingExpenseRatio: 0.09,
      fiscalYear: "2024",
      sourceProviders: ["Candid / GuideStar"],
      verificationStatus: "verified",
      verifiedAt: ts("2025-05-01T00:00:00Z"),
      confidence: "medium",
      notes: "Smaller local org; financials self-reported and cross-checked with IRS 990.",
    },
    giftImpacts: [
      {
        id: "gi-ctm-1",
        amount: 15,
        description: "Serves a hot three-course meal for one person for one week.",
        fiscalYear: "2024",
        sourceUrl: null,
        verifiedAt: ts("2025-02-01T00:00:00Z"),
        confidence: "medium",
      },
      {
        id: "gi-ctm-2",
        amount: 300,
        description:
          "Covers one month of transitional housing including case management.",
        fiscalYear: "2024",
        sourceUrl: null,
        verifiedAt: ts("2025-02-01T00:00:00Z"),
        confidence: "medium",
      },
    ],
    recentActions: [
      {
        id: "ra-ctm-1",
        title: "Winter Emergency Shelter Expansion",
        summary:
          "Opened a second overnight shelter site in January, adding 60 beds and " +
          "serving 140 additional individuals during a severe cold snap.",
        region: "Dallas-Fort Worth, TX",
        occurredAt: ts("2026-01-10T00:00:00Z"),
        verifiedAt: ts("2026-01-20T00:00:00Z"),
        sourceUrl: null,
        confidence: "medium",
      },
    ],
  },

  // 5. Pregnancy & Women — Catholic
  {
    id: "org-new-life-center",
    name: "New Life Women's Center",
    slug: "new-life-womens-center",
    description:
      "Offers free pregnancy testing, ultrasounds, material assistance, and post-abortion " +
      "support grounded in the Catholic pro-life tradition. Serves women regardless of " +
      "faith background or income.",
    causeCategories: ["Pregnancy & Women"],
    serviceRegions: [
      {
        country: "USA",
        state: "OH",
        metro: "Columbus",
        isLocal: true,
        isGlobal: false,
      },
    ],
    theologicalAffiliations: ["Catholic"],
    givingStylesSupported: [
      "One-time",
      "Recurring",
      "In-kind",
      "Time / Volunteer",
    ],
    websiteUrl: "https://example.org/nlwc",
    donationUrl: "https://example.org/nlwc/give",
    volunteerUrl: "https://example.org/nlwc/volunteer",
    logoUrl: null,
    isActive: true,
    rankingEligibility: true,
    isLocalPartner: true,
    isDisasterResponder: false,
    trustBadges: [
      "501(c)(3)",
      "Local partner verified",
      "Pastoral reviewed",
    ],
    trustScore: 0.82,
    transparency: {
      programExpenseRatio: 0.76,
      adminExpenseRatio: 0.14,
      fundraisingExpenseRatio: 0.1,
      fiscalYear: "2023",
      sourceProviders: ["IRS 990"],
      verificationStatus: "in_progress",
      verifiedAt: null,
      confidence: "low",
      notes: "2024 990 not yet filed; using prior-year data.",
    },
    giftImpacts: [
      {
        id: "gi-nlwc-1",
        amount: 30,
        description: "Provides a full baby supply bundle (diapers, clothing, wipes) for one newborn.",
        fiscalYear: "2023",
        sourceUrl: null,
        verifiedAt: ts("2024-06-01T00:00:00Z"),
        confidence: "medium",
      },
    ],
    recentActions: [
      {
        id: "ra-nlwc-1",
        title: "Mobile Ultrasound Unit Launch",
        summary:
          "Launched a mobile ultrasound van reaching three underserved ZIP codes in Central Ohio, " +
          "completing 220 appointments in its first quarter.",
        region: "Columbus, OH",
        occurredAt: ts("2025-10-01T00:00:00Z"),
        verifiedAt: ts("2025-11-01T00:00:00Z"),
        sourceUrl: null,
        confidence: "medium",
      },
    ],
  },

  // 6. Prison Ministry — evangelical
  {
    id: "org-inside-out-fellowship",
    name: "Inside Out Prison Fellowship",
    slug: "inside-out-prison-fellowship",
    description:
      "Partners with correctional facilities to deliver in-cell discipleship materials, " +
      "in-person Bible studies, re-entry mentorship, and family restoration programs. " +
      "Currently active in 120 facilities across 22 states.",
    causeCategories: ["Prison Ministry"],
    serviceRegions: [
      { country: "USA", isLocal: false, isGlobal: false },
    ],
    theologicalAffiliations: ["Evangelical", "Denominationally Neutral"],
    givingStylesSupported: ["One-time", "Recurring", "Time / Volunteer"],
    websiteUrl: "https://example.org/iof",
    donationUrl: "https://example.org/iof/give",
    volunteerUrl: "https://example.org/iof/mentor",
    logoUrl: null,
    isActive: true,
    rankingEligibility: true,
    isLocalPartner: false,
    isDisasterResponder: false,
    trustBadges: ["501(c)(3)", "ECFA", "Candid / GuideStar", "Financials current"],
    trustScore: 0.89,
    transparency: {
      programExpenseRatio: 0.83,
      adminExpenseRatio: 0.09,
      fundraisingExpenseRatio: 0.08,
      fiscalYear: "2024",
      sourceProviders: ["ECFA"],
      verificationStatus: "verified",
      verifiedAt: ts("2025-03-01T00:00:00Z"),
      confidence: "high",
      notes: null,
    },
    giftImpacts: [
      {
        id: "gi-iof-1",
        amount: 20,
        description:
          "Delivers a full 12-week discipleship curriculum to one incarcerated person.",
        fiscalYear: "2024",
        sourceUrl: "https://example.org/iof/impact",
        verifiedAt: ts("2025-01-01T00:00:00Z"),
        confidence: "high",
      },
    ],
    recentActions: [
      {
        id: "ra-iof-1",
        title: "Re-entry Cohort — Spring 2026",
        summary:
          "Graduated 88 participants from the 6-month re-entry program; 73% secured stable " +
          "housing within 90 days of release.",
        region: "United States",
        occurredAt: ts("2026-05-01T00:00:00Z"),
        verifiedAt: ts("2026-05-15T00:00:00Z"),
        sourceUrl: "https://example.org/iof/reentry-2026",
        confidence: "high",
      },
    ],
  },

  // 7. Anti-Trafficking — evangelical
  {
    id: "org-freedom-rise",
    name: "Freedom Rise Coalition",
    slug: "freedom-rise-coalition",
    description:
      "Combats human trafficking through survivor restoration homes, law enforcement " +
      "training partnerships, prevention education in schools and churches, and global " +
      "field operations in high-risk corridors.",
    causeCategories: ["Anti-Trafficking", "Refugee Resettlement"],
    serviceRegions: [
      { country: "USA", isLocal: false, isGlobal: false },
      { country: "Global", isLocal: false, isGlobal: true },
    ],
    theologicalAffiliations: ["Evangelical"],
    givingStylesSupported: ["One-time", "Recurring", "Time / Volunteer"],
    websiteUrl: "https://example.org/frc",
    donationUrl: "https://example.org/frc/give",
    volunteerUrl: null,
    logoUrl: null,
    isActive: true,
    rankingEligibility: true,
    isLocalPartner: false,
    isDisasterResponder: false,
    trustBadges: [
      "501(c)(3)",
      "ECFA",
      "Charity Navigator",
      "BBB Wise Giving",
      "Financials current",
    ],
    trustScore: 0.94,
    transparency: {
      programExpenseRatio: 0.84,
      adminExpenseRatio: 0.08,
      fundraisingExpenseRatio: 0.08,
      fiscalYear: "2024",
      sourceProviders: ["Charity Navigator", "ECFA"],
      verificationStatus: "verified",
      verifiedAt: ts("2025-04-15T00:00:00Z"),
      confidence: "high",
      notes: null,
    },
    giftImpacts: [
      {
        id: "gi-frc-1",
        amount: 75,
        description:
          "Funds one week of aftercare for a survivor in a Freedom Rise restoration home.",
        fiscalYear: "2024",
        sourceUrl: "https://example.org/frc/impact",
        verifiedAt: ts("2025-01-20T00:00:00Z"),
        confidence: "high",
      },
    ],
    recentActions: [
      {
        id: "ra-frc-1",
        title: "Southeast Asia Rescue Operations",
        summary:
          "Partnered with local law enforcement to assist in rescue operations affecting " +
          "230 victims; opened two new safe houses.",
        region: "Southeast Asia",
        occurredAt: ts("2026-03-10T00:00:00Z"),
        verifiedAt: ts("2026-04-01T00:00:00Z"),
        sourceUrl: "https://example.org/frc/updates/sea-ops-2026",
        confidence: "medium",
      },
    ],
  },

  // 8. Refugee Resettlement — denominationally neutral, local partner
  {
    id: "org-welcome-table-refugees",
    name: "Welcome Table Refugee Services",
    slug: "welcome-table-refugee-services",
    description:
      "Walks alongside newly arrived refugee families through cultural orientation, " +
      "English classes, job placement support, and faith community connection. " +
      "Faith-motivated but denominationally neutral; welcomes volunteers of all traditions.",
    causeCategories: ["Refugee Resettlement", "Local Church & Benevolence"],
    serviceRegions: [
      {
        country: "USA",
        state: "TN",
        metro: "Nashville",
        isLocal: true,
        isGlobal: false,
      },
    ],
    theologicalAffiliations: ["Denominationally Neutral"],
    givingStylesSupported: [
      "One-time",
      "Recurring",
      "In-kind",
      "Time / Volunteer",
    ],
    websiteUrl: "https://example.org/wtr",
    donationUrl: "https://example.org/wtr/give",
    volunteerUrl: "https://example.org/wtr/volunteer",
    logoUrl: null,
    isActive: true,
    rankingEligibility: true,
    isLocalPartner: true,
    isDisasterResponder: false,
    trustBadges: [
      "501(c)(3)",
      "Local partner verified",
      "Pastoral reviewed",
      "Candid / GuideStar",
    ],
    trustScore: 0.85,
    transparency: {
      programExpenseRatio: 0.80,
      adminExpenseRatio: 0.11,
      fundraisingExpenseRatio: 0.09,
      fiscalYear: "2024",
      sourceProviders: ["Candid / GuideStar"],
      verificationStatus: "verified",
      verifiedAt: ts("2025-06-01T00:00:00Z"),
      confidence: "medium",
      notes: null,
    },
    giftImpacts: [
      {
        id: "gi-wtr-1",
        amount: 40,
        description:
          "Covers one week of English-language instruction for one adult refugee.",
        fiscalYear: "2024",
        sourceUrl: null,
        verifiedAt: ts("2025-03-01T00:00:00Z"),
        confidence: "medium",
      },
      {
        id: "gi-wtr-2",
        amount: 500,
        description:
          "Sponsors a full family's first month of wrap-around services upon arrival.",
        fiscalYear: "2024",
        sourceUrl: null,
        verifiedAt: ts("2025-03-01T00:00:00Z"),
        confidence: "medium",
      },
    ],
    recentActions: [
      {
        id: "ra-wtr-1",
        title: "Somali Bantu Community Garden Launch",
        summary:
          "Partnered with 12 refugee families to establish a community garden, " +
          "providing culturally familiar produce and a weekly gathering space.",
        region: "Nashville, TN",
        occurredAt: ts("2026-04-22T00:00:00Z"),
        verifiedAt: ts("2026-05-01T00:00:00Z"),
        sourceUrl: null,
        confidence: "medium",
      },
    ],
  },
];

// ── 3 Cause Briefs ─────────────────────────────────────────────────────────────
const CAUSE_BRIEFS = [
  {
    id: "brief-disaster-relief",
    title: "Why Disaster Relief Is a Gospel Issue",
    slug: "why-disaster-relief-gospel-issue",
    causeCategory: "Disaster Relief",
    regionScope: "Global",
    summary:
      "Natural disasters expose the most vulnerable. The Church has always been " +
      "first on the scene — and here is why that matters now.",
    body:
      "From the earliest centuries of the church, Christians have rushed toward " +
      "suffering rather than away from it. In 165 AD, Dionysius of Alexandria wrote " +
      "that believers stayed behind during a plague to care for the sick while others " +
      "fled. That posture of costly love has never changed.\n\n" +
      "Today an average of 60,000 people are killed by natural disasters every year. " +
      "Behind every statistic is a family — a home reduced to rubble, a livelihood " +
      "swept away, a community shattered overnight. The question for the global Church " +
      "is not whether to respond, but how quickly and how faithfully.\n\n" +
      "Three principles guide a Christ-centered disaster response:\n\n" +
      "1. Speed preserves life. The first 72 hours are critical for water, medical " +
      "care, and search-and-rescue. Organizations with pre-positioned teams and " +
      "supplies save disproportionately more lives.\n\n" +
      "2. Dignity restores hope. Relief that treats recipients as image-bearers " +
      "— not charity cases — produces lasting transformation rather than dependency.\n\n" +
      "3. Long-term presence builds the Church. The most effective Christian relief " +
      "organizations stay for years, not weeks, investing in local leadership, " +
      "economic recovery, and spiritual community.",
    scriptureRefs: [
      "Isaiah 58:7",
      "Matthew 25:35-36",
      "James 2:14-17",
      "Luke 10:33-34",
    ],
    linkedOrgIds: ["org-global-relief-purse"],
    linkedPrayerTopics: ["Disaster victims", "Relief workers", "Government coordination"],
    linkedVolunteerActions: [
      "Join a response team",
      "Donate emergency supplies",
      "Pray for affected regions",
    ],
    publishedAt: ts("2026-01-15T00:00:00Z"),
    updatedAt: ts("2026-04-01T00:00:00Z"),
    isActive: true,
  },
  {
    id: "brief-foster-care",
    title: "Every Child Needs a Family: The Church's Call to Foster Care",
    slug: "church-call-to-foster-care",
    causeCategory: "Foster Care",
    regionScope: "United States",
    summary:
      "There are over 400,000 children in foster care in the United States today. " +
      "The Church has both the capacity and the calling to change that number.",
    body:
      "Orphan care is not a niche ministry — it is woven into the identity of God's " +
      "people. Scripture repeatedly names the orphan alongside the widow and the " +
      "foreigner as those whose cause God defends. James 1:27 stakes the credibility " +
      "of 'pure religion' on it.\n\n" +
      "In the United States, approximately 407,000 children are in foster care on " +
      "any given day. Roughly 113,000 are waiting to be adopted. Research shows that " +
      "if just one family in every three evangelical churches in the country fostered " +
      "or adopted, there would be no children waiting for homes.\n\n" +
      "The barrier is not capacity — it is awareness and equipping. Most families " +
      "who want to help do not know where to start. Most churches have no structured " +
      "support pathway. This is exactly the gap organizations like Covenant Foster " +
      "Network exist to close.\n\n" +
      "Ways to engage:\n" +
      "• Foster: Open your home as a licensed foster family.\n" +
      "• Support: Build a care team around a foster or adoptive family you know.\n" +
      "• Advocate: Ask your church to launch a foster care ministry.\n" +
      "• Give: Fund the training, respite, and wrap-around services that keep " +
      "foster families in the mission.",
    scriptureRefs: [
      "James 1:27",
      "Psalm 68:5-6",
      "Deuteronomy 10:18",
      "John 14:18",
    ],
    linkedOrgIds: ["org-foster-covenant"],
    linkedPrayerTopics: [
      "Children in foster care",
      "Foster and adoptive families",
      "Caseworkers and judges",
    ],
    linkedVolunteerActions: [
      "Become a licensed foster family",
      "Join a family support team",
      "Lead a foster care awareness month at your church",
    ],
    publishedAt: ts("2026-02-01T00:00:00Z"),
    updatedAt: ts("2026-02-01T00:00:00Z"),
    isActive: true,
  },
  {
    id: "brief-persecuted-church",
    title: "The Persecuted Church Is Our Family",
    slug: "persecuted-church-is-our-family",
    causeCategory: "Persecuted Church",
    regionScope: "Global",
    summary:
      "More Christians are being persecuted for their faith today than at any other " +
      "point in recorded history. What does faithful solidarity look like?",
    body:
      "The World Watch List reports that 365 million Christians face high levels of " +
      "persecution globally — one in seven believers worldwide. In 50 countries " +
      "conditions are severe enough that simply owning a Bible or meeting for worship " +
      "can result in imprisonment, torture, or death.\n\n" +
      "Paul's instruction in 1 Corinthians 12:26 is unambiguous: 'If one part suffers, " +
      "every part suffers with it.' The persecuted church is not a distant concern — " +
      "it is our family.\n\n" +
      "Faithful solidarity takes three forms:\n\n" +
      "1. Prayer. Sustained, informed, specific intercession for named countries, " +
      "named leaders, and named communities. Organizations like Beacon for the " +
      "Persecuted Church publish weekly prayer guides.\n\n" +
      "2. Presence (through proxy). Bible distribution, discipleship resources, " +
      "trauma care, and safe houses extend the body of Christ into places you " +
      "cannot physically go.\n\n" +
      "3. Proclamation. Advocacy for religious freedom in your own country and at " +
      "international forums is itself an act of love toward those who cannot " +
      "speak for themselves.",
    scriptureRefs: [
      "1 Corinthians 12:26",
      "Hebrews 13:3",
      "Matthew 5:10-12",
      "Revelation 2:10",
    ],
    linkedOrgIds: ["org-open-doors-beacon"],
    linkedPrayerTopics: [
      "Imprisoned believers",
      "Underground churches",
      "Countries with severe persecution",
    ],
    linkedVolunteerActions: [
      "Subscribe to a weekly prayer guide",
      "Write to a persecuted believer",
      "Advocate for religious freedom legislation",
    ],
    publishedAt: ts("2026-03-15T00:00:00Z"),
    updatedAt: ts("2026-05-01T00:00:00Z"),
    isActive: true,
  },
];

// ── 1 Disaster Event ───────────────────────────────────────────────────────────
const DISASTER_EVENTS = [
  {
    id: "event-myanmar-flood-2026",
    title: "Myanmar Monsoon Flooding — May 2026",
    eventType: "flood",
    sourceProvider: "ReliefWeb",
    sourceUrl: "https://reliefweb.int/disaster/fl-2026-000000-mmr",
    severity: "critical",
    regions: ["Myanmar", "Ayeyarwady Region", "Bago Region"],
    summary:
      "Catastrophic monsoon flooding across central and lower Myanmar has displaced " +
      "over 230,000 people as of late May 2026. Entire villages in the Ayeyarwady " +
      "delta have been submerged; road access is cut off in many areas, complicating " +
      "relief efforts. The UN estimates at least 180,000 people urgently need food, " +
      "clean water, and shelter. Several faith-based relief organizations with " +
      "existing in-country networks are among the first responders on the ground.",
    startedAt: ts("2026-05-12T00:00:00Z"),
    updatedAt: ts("2026-05-30T00:00:00Z"),
    isActive: true,
    linkedOrgIds: ["org-global-relief-purse"],
  },
];

// ═══════════════════════════════════════════════════════════════════════════════
// WRITE LOGIC
// ═══════════════════════════════════════════════════════════════════════════════

async function seed() {
  if (DRY_RUN) {
    console.log("\n=== DRY RUN — no data will be written to Firestore ===\n");
    printPreview();
    return;
  }

  const db = admin.firestore();

  let orgsWritten = 0;
  let briefsWritten = 0;
  let eventsWritten = 0;

  // ── Organizations ──────────────────────────────────────────────────────────
  console.log("Writing organizations...");
  for (const org of ORGANIZATIONS) {
    await db
      .collection("organizations")
      .doc(org.id)
      .set(org, { merge: true });
    console.log(`  [OK] organizations/${org.id}  (${org.name})`);
    orgsWritten++;
  }

  // ── Cause Briefs ───────────────────────────────────────────────────────────
  console.log("\nWriting cause_briefs...");
  for (const brief of CAUSE_BRIEFS) {
    await db
      .collection("cause_briefs")
      .doc(brief.id)
      .set(brief, { merge: true });
    console.log(`  [OK] cause_briefs/${brief.id}  (${brief.title})`);
    briefsWritten++;
  }

  // ── Disaster Events ────────────────────────────────────────────────────────
  console.log("\nWriting disaster_events...");
  for (const event of DISASTER_EVENTS) {
    await db
      .collection("disaster_events")
      .doc(event.id)
      .set(event, { merge: true });
    console.log(`  [OK] disaster_events/${event.id}  (${event.title})`);
    eventsWritten++;
  }

  // ── Summary ────────────────────────────────────────────────────────────────
  console.log("\n════════════════════════════════════════");
  console.log("Seed complete.");
  console.log(`  organizations:   ${orgsWritten} documents written`);
  console.log(`  cause_briefs:    ${briefsWritten} documents written`);
  console.log(`  disaster_events: ${eventsWritten} documents written`);
  console.log("════════════════════════════════════════\n");
}

function printPreview() {
  console.log(`organizations (${ORGANIZATIONS.length} docs):`);
  for (const o of ORGANIZATIONS) {
    console.log(
      `  organizations/${o.id}  →  ${o.name}  [causes: ${o.causeCategories.join(", ")}]`
    );
  }
  console.log(`\ncause_briefs (${CAUSE_BRIEFS.length} docs):`);
  for (const b of CAUSE_BRIEFS) {
    console.log(`  cause_briefs/${b.id}  →  ${b.title}`);
  }
  console.log(`\ndisaster_events (${DISASTER_EVENTS.length} docs):`);
  for (const e of DISASTER_EVENTS) {
    console.log(`  disaster_events/${e.id}  →  ${e.title}  [severity: ${e.severity}]`);
  }
  console.log("\n════════════════════════════════════════");
  console.log("Dry-run summary:");
  console.log(`  organizations:   ${ORGANIZATIONS.length} documents would be written`);
  console.log(`  cause_briefs:    ${CAUSE_BRIEFS.length} documents would be written`);
  console.log(`  disaster_events: ${DISASTER_EVENTS.length} documents would be written`);
  console.log("════════════════════════════════════════\n");
}

// ── Entry point ────────────────────────────────────────────────────────────────
initFirebase();
seed().catch((err) => {
  console.error("Seed failed:", err);
  process.exit(1);
});

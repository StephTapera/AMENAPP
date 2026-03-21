/**
 * 242hub.js
 * Cloud Functions for AMEN's Acts 2:42 Resource Hub
 *
 * 1. flockIntelligence      — weekly Sunday-night pastoral briefing (Cloud Scheduler)
 * 2. processSermonMemory    — sermon transcript → embedding on upload (Firestore trigger)
 * 3. reviewPrayerSubmission — elder triage AI before prayer wall (Firestore trigger)
 * 4. reviewCovenantApp      — Values Verified covenant assessment (callable)
 * 5. matchKingdomCommerce   — Kingdom Commerce matching + listing review (callable)
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { logger } = require("firebase-functions");

// Lazy OpenAI client — requires OPENAI_API_KEY environment secret
let _openai = null;
function getOpenAI() {
  if (!_openai) {
    const OpenAI = require("openai");
    const key = process.env.OPENAI_API_KEY;
    if (!key) throw new Error("OPENAI_API_KEY secret not set");
    _openai = new OpenAI({ apiKey: key });
  }
  return _openai;
}

// Claude claude-sonnet-4-6 via Anthropic SDK — for the pastoral AI prompts
let _anthropic = null;
function getAnthropic() {
  if (!_anthropic) {
    const Anthropic = require("@anthropic-ai/sdk");
    const key = process.env.ANTHROPIC_API_KEY;
    if (!key) throw new Error("ANTHROPIC_API_KEY secret not set");
    _anthropic = new Anthropic({ apiKey: key });
  }
  return _anthropic;
}

async function callClaude(systemPrompt, userMessage) {
  const client = getAnthropic();
  const response = await client.messages.create({
    model: "claude-sonnet-4-6",
    max_tokens: 2048,
    system: systemPrompt,
    messages: [{ role: "user", content: userMessage }],
  });
  const text = response.content[0].text;
  // Extract JSON from response (may be wrapped in markdown code blocks)
  const jsonMatch = text.match(/```json\s*([\s\S]*?)```/) || text.match(/(\{[\s\S]*\})/);
  if (jsonMatch) {
    return JSON.parse(jsonMatch[1]);
  }
  return JSON.parse(text);
}

// ─────────────────────────────────────────────────────────────
// 1. FLOCK INTELLIGENCE — Sunday night pastoral briefing
// ─────────────────────────────────────────────────────────────

const FLOCK_INTELLIGENCE_PROMPT = `# FLOCK INTELLIGENCE — System Prompt
# Model: claude-sonnet-4-6 | Trigger: weekly Cloud Scheduler job (Sunday night)

You are the Shepherd's Lens, the pastoral intelligence layer inside AMEN's Flock Intelligence system.
You generate weekly briefings from anonymized congregation activity data for church leadership.

YOUR CALLING:
You serve pastors and elders who need to shepherd wisely without surveilling.
All data you receive is already anonymized — you will never see member names.
Your output helps leaders preach relevantly, mobilize care teams, and notice absence.

WHAT YOU RECEIVE (injected as JSON in the user message):
- totalActiveMembers: number
- prayerThemeClusters: [{ theme: string, count: number, trend: "rising|stable|falling" }]
- silentMembersOver30Days: number (count only, no identifiers)
- answeredPrayersThisWeek: number
- newMembersThisWeek: number
- testimoniesShared: number
- dominantScriptureTouched: [reference, ...]
- topBurdens: [{ burden: string, count: number }]

WHAT YOU PRODUCE (return as JSON):
{
  "weeklyWord": "2-3 sentence pastoral observation for leadership. Warm, discerning tone.",
  "urgentCluster": {
    "theme": "...",
    "count": number,
    "pastoralNote": "What this cluster likely means spiritually",
    "suggestedResponse": "Concrete action: preach into it, mobilize care team, etc."
  } | null,
  "preachingRecommendation": {
    "theme": "...",
    "scripture": "...",
    "rationale": "Why this meets the congregation this week"
  },
  "careTeamAlert": {
    "note": "Anonymous flag about members who may need outreach",
    "action": "What the care team should do"
  } | null,
  "silenceAlert": silentMembersOver30Days > 5 ? "X members have gone quiet for 30+ days. Consider a personal reach-out initiative." : null,
  "gratitudeNote": "One encouraging observation from this week's data.",
  "dominantTheme": "Single-word summary of where the congregation is spiritually this week"
}

CRITICAL RULES:
- Never speculate on individual identity from cluster data.
- Never use clinical or surveillance language. Speak as a shepherd, not an analyst.
- If grief, suicide, or abuse clusters appear at any count: set urgentCluster with high priority.
- If data shows suffering, don't minimize it — name it with pastoral care.
- If all metrics are low: be honest and still find the grace. Faithfulness is invisible work.`;

exports.flockIntelligence = onSchedule({
  schedule: "0 22 * * 0", // Sunday 10pm
  timeZone: "America/New_York",
  secrets: ["ANTHROPIC_API_KEY"],
}, async () => {
  const db = getFirestore();
  const now = new Date();
  const weekStart = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const weekId = `${now.getFullYear()}-W${String(Math.ceil(now.getDate() / 7)).padStart(2, "0")}`;

  // Fetch all church IDs
  const churchesSnap = await db.collection("churches").where("flockIntelligenceEnabled", "==", true).get();

  for (const churchDoc of churchesSnap.docs) {
    const churchId = churchDoc.id;
    try {
      // Aggregate anonymized data for this church
      const postsSnap = await db.collection("posts")
        .where("churchId", "==", churchId)
        .where("createdAt", ">=", weekStart)
        .get();

      const prayerThemeCounts = {};
      let answeredPrayers = 0;
      let testimonies = 0;

      postsSnap.forEach(doc => {
        const data = doc.data();
        if (data.type === "answered_prayer") answeredPrayers++;
        if (data.type === "testimony") testimonies++;
        (data.themes || []).forEach(t => {
          prayerThemeCounts[t] = (prayerThemeCounts[t] || 0) + 1;
        });
      });

      const prayerThemeClusters = Object.entries(prayerThemeCounts)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 8)
        .map(([theme, count]) => ({ theme, count, trend: "stable" }));

      // Count silent members (no post in 30 days)
      const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
      const membersSnap = await db.collection("users").where("churchId", "==", churchId).get();
      let silentCount = 0;
      for (const m of membersSnap.docs) {
        const lastPost = m.data().lastPostAt?.toDate();
        if (!lastPost || lastPost < thirtyDaysAgo) silentCount++;
      }

      const payload = {
        totalActiveMembers: membersSnap.size,
        prayerThemeClusters,
        silentMembersOver30Days: silentCount,
        answeredPrayersThisWeek: answeredPrayers,
        newMembersThisWeek: 0, // would need createdAt filter on users
        testimoniesShared: testimonies,
        dominantScriptureTouched: [],
        topBurdens: prayerThemeClusters.slice(0, 3).map(c => ({ burden: c.theme, count: c.count })),
      };

      const briefing = await callClaude(FLOCK_INTELLIGENCE_PROMPT, JSON.stringify(payload));

      await db.collection("flockBriefings").doc(churchId).collection("weeks").doc(weekId).set({
        ...briefing,
        generatedAt: new Date(),
        churchId,
        weekId,
        rawPayload: payload,
      });

      logger.info(`[flockIntelligence] Briefing generated for church=${churchId} week=${weekId}`);
    } catch (err) {
      logger.error(`[flockIntelligence] Failed for church=${churchId}:`, err.message);
    }
  }
});

// ─────────────────────────────────────────────────────────────
// 2. SERMON LIVING MEMORY — process uploaded sermon transcript
// ─────────────────────────────────────────────────────────────

const SERMON_MEMORY_PROMPT = `# SERMON LIVING MEMORY — System Prompt
# Model: claude-sonnet-4-6 | Trigger: onSermonUpload (Cloud Function)

You are the Sermon Archivist inside AMEN's Living Memory system.
You process church sermon transcripts and prepare them for semantic embedding,
so they resurface automatically when congregation members pray about matching themes.

YOUR MISSION:
A sermon preached on Sunday should still be working 3 years later.
You extract every semantic signal that could connect this sermon to a future prayer request.

WHAT YOU RECEIVE (injected as JSON):
- sermon_title: string
- preacher: string
- date: "YYYY-MM-DD"
- transcript: full sermon text
- scripture_focus: primary passage(s)
- series_name: string | null

WHAT YOU PRODUCE (return as JSON):
{
  "themes": ["restoration", "fear", "marriage", ...],
  "primaryScripture": ["1 John 4:18", ...],
  "ancillaryScripture": ["Rom 8:15", "2 Tim 1:7", ...],
  "emotionalTones": ["grief", "hope", "conviction", "peace", ...],
  "audienceNeeds": ["fear of the future", "anxiety about children", ...],
  "keyQuotes": [
    { "text": "Direct quote under 30 words", "theme": "...", "searchableContext": "..." }
  ],
  "summary": "2-3 sentence summary of central message and life application.",
  "embeddingText": "Rich plain-prose block optimized for semantic similarity search. Min 150 words."
}

RULES:
- The embeddingText is what gets vectorized — maximize its semantic density.
- Only extract what is genuinely present in the transcript.
- keyQuotes must be exact words from the transcript, under 30 words each.
- audienceNeeds should be phrased as human felt-needs, not theological categories.`;

exports.processSermonMemory = onDocumentCreated({
  document: "sermons/{sermonId}",
  secrets: ["ANTHROPIC_API_KEY", "OPENAI_API_KEY"],
}, async (event) => {
  const snap = event.data;
  const sermon = snap.data();
  if (!sermon?.transcript || sermon.embeddingProcessed) return;

  const db = getFirestore();
  const sermonId = event.params.sermonId;

  try {
    const payload = {
      sermon_title: sermon.title || "",
      preacher: sermon.preacher || "",
      date: sermon.date || new Date().toISOString().split("T")[0],
      transcript: sermon.transcript,
      scripture_focus: sermon.scriptureFocus || "",
      series_name: sermon.seriesName || null,
    };

    const analysis = await callClaude(SERMON_MEMORY_PROMPT, JSON.stringify(payload));

    // Generate embedding from the rich embeddingText
    const openai = getOpenAI();
    const embeddingRes = await openai.embeddings.create({
      model: "text-embedding-3-small",
      input: analysis.embeddingText,
    });
    const embedding = embeddingRes.data[0].embedding;

    await snap.ref.update({
      themes: analysis.themes,
      primaryScripture: analysis.primaryScripture,
      ancillaryScripture: analysis.ancillaryScripture,
      emotionalTones: analysis.emotionalTones,
      audienceNeeds: analysis.audienceNeeds,
      keyQuotes: analysis.keyQuotes,
      summary: analysis.summary,
      embeddingText: analysis.embeddingText,
      embedding,
      resurface: true,
      resurfaceCount: 0,
      resonanceScore: 0,
      embeddingProcessed: true,
      processedAt: new Date(),
    });

    logger.info(`[processSermonMemory] Sermon ${sermonId} processed — ${analysis.themes.length} themes, embedding stored`);
  } catch (err) {
    logger.error(`[processSermonMemory] Failed for sermon ${sermonId}:`, err.message);
    await snap.ref.update({ embeddingError: err.message, embeddingProcessed: false });
  }
});

// ─────────────────────────────────────────────────────────────
// 3. PRAYER WALL REVIEW — elder triage before prayer wall
// ─────────────────────────────────────────────────────────────

const PRAYER_WALL_PROMPT = `# CHURCH PRAYER WALL — System Prompt
# Model: claude-sonnet-4-6 | Trigger: onPrayerSubmission

You are the Elder Review Assistant inside AMEN's Church Prayer Wall.
You help church elders and deacons triage incoming prayer request submissions
before they reach the moderation queue.

YOUR ROLE:
You are not the final decision-maker — the elders are. You surface information.
Be concise. Be honest. Be pastoral.

WHAT YOU RECEIVE (injected as JSON):
- submissionId: string
- submissionText: string
- hasPrivacyFlag: boolean
- memberTenure: "new|established|unknown"
- submittedAt: timestamp

WHAT YOU PRODUCE (return as JSON):
{
  "shepherdsGateScan": {
    "sensitiveTopics": ["grief", "addiction"] | null,
    "toneNote": "Brief observation on emotional posture",
    "appropriateForWall": true | false,
    "appropriatenessNote": "Why or why not" | null
  },
  "urgencyLevel": "low|medium|high|crisis",
  "crisisFlag": boolean,
  "crisisProtocol": "Elder: contact this member directly TODAY. US Crisis: 988 Suicide & Crisis Lifeline." | null,
  "prayerPoints": ["Three specific intercession points"],
  "suggestedElderResponse": "A warm, personal sample reply the elder can edit and send",
  "recommendedAction": "post-to-wall|private-pastoral-response|care-team-visit|crisis-intervention",
  "actionRationale": "One sentence explaining this recommendation"
}

CRITICAL:
- ANY hint of suicidal ideation, active self-harm, or abuse → crisisFlag: true, urgencyLevel: crisis.
- crisisProtocol must always include: "US Crisis: 988 Suicide & Crisis Lifeline."
- NEVER recommend posting crisis content to the public wall.
- hasPrivacyFlag: true → recommendedAction must NEVER be "post-to-wall".`;

exports.reviewPrayerSubmission = onDocumentCreated({
  document: "prayerWallSubmissions/{submissionId}",
  secrets: ["ANTHROPIC_API_KEY"],
}, async (event) => {
  const snap = event.data;
  const submission = snap.data();
  if (!submission?.text) return;

  const db = getFirestore();
  const submissionId = event.params.submissionId;

  try {
    const payload = {
      submissionId,
      submissionText: submission.text,
      hasPrivacyFlag: submission.isPrivate || false,
      memberTenure: submission.memberTenure || "unknown",
      submittedAt: new Date().toISOString(),
    };

    const review = await callClaude(PRAYER_WALL_PROMPT, JSON.stringify(payload));

    // Write review to Firestore
    await snap.ref.update({
      elderReview: review,
      reviewedAt: new Date(),
      status: review.crisisFlag ? "crisis" : "pending-elder-review",
    });

    // Crisis path: push notification to lead pastor immediately, bypass queue
    if (review.crisisFlag && submission.churchId) {
      const churchDoc = await db.collection("churches").doc(submission.churchId).get();
      const leadPastorFCMToken = churchDoc.data()?.leadPastorFCMToken;
      if (leadPastorFCMToken) {
        await getMessaging().send({
          token: leadPastorFCMToken,
          notification: {
            title: "⚠️ Crisis Prayer Request",
            body: review.crisisProtocol || "A member needs immediate pastoral contact. Open AMEN now.",
          },
          data: { submissionId, type: "crisis_prayer" },
          apns: { payload: { aps: { sound: "default", badge: 1 } } },
        });
        logger.warn(`[reviewPrayerSubmission] CRISIS FLAG — notification sent to lead pastor for church=${submission.churchId}`);
      }
    }

    logger.info(`[reviewPrayerSubmission] ${submissionId} reviewed — urgency=${review.urgencyLevel}, crisis=${review.crisisFlag}`);
  } catch (err) {
    logger.error(`[reviewPrayerSubmission] Failed for ${submissionId}:`, err.message);
  }
});

// ─────────────────────────────────────────────────────────────
// 4. VALUES VERIFIED — covenant business review
// ─────────────────────────────────────────────────────────────

const VALUES_VERIFIED_PROMPT = `# VALUES VERIFIED BADGE — System Prompt
# Model: claude-sonnet-4-6 | Trigger: onCovenantSubmission

You are the Covenant Reviewer inside AMEN's Values Verified program.
You assess faith-aligned businesses applying for their public covenant declaration.

THE FOUR PILLARS:
PILLAR 1 — EMPLOYEES: How do they treat, compensate, develop, and honor their people?
PILLAR 2 — GENEROSITY: How do they give? Percentages, named recipients, specifics.
PILLAR 3 — COMMUNITY SERVICE: How do they serve beyond their commercial purpose?
PILLAR 4 — ETHICAL PRACTICE: How do they handle pricing, data, sourcing, hard decisions?

WHAT YOU RECEIVE (injected as JSON):
- businessName, businessType, yearsFounded
- covenantResponses: { employees, generosity, communityService, ethicalPractice }
- additionalContext: string | null

WHAT YOU PRODUCE (return as JSON):
{
  "pillarAssessments": {
    "employees": { "score": "strong|growing|needs-development|insufficient", "observation": "...", "clarifyingQuestion": "..." | null },
    "generosity": { ... },
    "communityService": { ... },
    "ethicalPractice": { ... }
  },
  "overallReadiness": "approved|pending-clarification|not-ready",
  "pendingItems": ["..."] | null,
  "covenantStatement": "2-3 sentence public declaration in THEIR voice. Specific, not generic.",
  "scriptureAnchor": "A verse that grounds their specific commitments",
  "reviewNote": "Warm, honest note to the business. Affirm strengths. Be clear about gaps."
}

RULES:
- Be honest. Not every business is ready. The badge means something because it is earned.
- overallReadiness: "not-ready" is a valid and important outcome.
- covenantStatement must be SPECIFIC to this business.
- Never approve vague commitments.`;

exports.reviewCovenantApp = onCall({
  secrets: ["ANTHROPIC_API_KEY"],
}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

  const { businessId, businessName, businessType, yearsFounded, covenantResponses, additionalContext } = request.data;
  if (!businessId || !covenantResponses) throw new HttpsError("invalid-argument", "Missing required fields");

  const db = getFirestore();

  const payload = { businessName, businessType, yearsFounded, covenantResponses, additionalContext: additionalContext || null };
  const review = await callClaude(VALUES_VERIFIED_PROMPT, JSON.stringify(payload));

  // Determine badge status and update business doc
  const badgeStatus = review.overallReadiness === "approved" ? "verified"
    : review.overallReadiness === "pending-clarification" ? "pending"
    : "not-ready";

  await db.collection("valuesVerifiedApps").doc(businessId).set({
    ...review,
    badgeStatus,
    reviewedAt: new Date(),
    reviewedBy: "flock-intelligence-ai",
  }, { merge: true });

  if (badgeStatus === "verified") {
    await db.collection("businesses").doc(businessId).update({
      isValuesVerified: true,
      covenantStatement: review.covenantStatement,
      scriptureAnchor: review.scriptureAnchor,
      verifiedAt: new Date(),
    });
  }

  logger.info(`[reviewCovenantApp] ${businessId} — readiness=${review.overallReadiness}`);
  return { review, badgeStatus };
});

// ─────────────────────────────────────────────────────────────
// 5. KINGDOM COMMERCE — listing quality + member matching
// ─────────────────────────────────────────────────────────────

const KINGDOM_COMMERCE_PROMPT = `# KINGDOM COMMERCE FEED — System Prompt
# Model: claude-sonnet-4-6 | Trigger: onListingPost + onUserFeedLoad

You are the Kingdom Matchmaker inside AMEN's 242 Commerce resource.
You match job listings, volunteer opportunities, and community resources to AMEN members
based entirely on spiritual fit — never on ad budget, demographics, or employer size.

THE RULE: No advertising. No promoted posts. Only calling alignment.
A small church planting in a difficult neighborhood, offering no pay but deep Kingdom work,
should outrank a Fortune 500 "Christian-friendly" employer for the right member.

WHAT YOU RECEIVE (injected as JSON):
- listing: { id, title, description, organization, type, compensation, commitment, spiritualContext }
- memberProfile: { prayerThemes, spiritualGifts, testimonies, communityActivity, listeningFor }

WHAT YOU PRODUCE (return as JSON):
{
  "matchScore": 0.0-1.0,
  "matchReason": "2-3 sentence explanation referencing specific prayer themes or gifts",
  "callingConnection": "How this connects to what God seems to be doing in their life",
  "honestCaution": "Any honest note about fit gaps or realistic expectations" | null,
  "shouldSurface": boolean,
  "surfaceMessage": "Under 25 words. Sounds like a friend, not a recruiter.",
  "listingCategory": "job|volunteer|resource|service|community"
}

MATCHING RULES:
- shouldSurface: true only if matchScore >= 0.65
- Heavily weight: prayer theme overlap, spiritual gift alignment, testimony resonance.
- surfaceMessage must feel personal — reference something real from their profile themes.
  BAD: "We found a great opportunity for you!"
  GOOD: "This feels close to what you've been praying about."

# LISTING QUALITY REVIEW MODE
If input contains listing_review: true, assess the listing itself:
{
  "listingQuality": {
    "isGenuinelyKingdomAligned": boolean,
    "redFlags": ["..."] | null,
    "improvementSuggestion": "..." | null,
    "approved": boolean
  }
}`;

exports.matchKingdomCommerce = onCall({
  secrets: ["ANTHROPIC_API_KEY"],
}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in");

  const { listing, memberProfile, listing_review } = request.data;
  if (!listing) throw new HttpsError("invalid-argument", "listing is required");

  const payload = { listing, memberProfile: memberProfile || null, listing_review: listing_review || false };
  const result = await callClaude(KINGDOM_COMMERCE_PROMPT, JSON.stringify(payload));

  // If this is a new listing quality review, persist the result
  if (listing_review && listing.id) {
    const db = getFirestore();
    await db.collection("listings").doc(listing.id).update({
      qualityReview: result.listingQuality,
      qualityReviewedAt: new Date(),
      approved: result.listingQuality?.approved || false,
    });
  }

  logger.info(`[matchKingdomCommerce] listing=${listing.id} score=${result.matchScore || "review-only"}`);
  return result;
});

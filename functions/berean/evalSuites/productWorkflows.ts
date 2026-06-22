/**
 * productWorkflows.ts — Berean Evaluation Suite: Product Workflows
 *
 * 15 test cases covering:
 *  - Church search returns real, useful results
 *  - Notes creation and retrieval confirmations
 *  - Prayer request categorization
 *  - Scripture lookup in study mode (structured response shape)
 */

import type { EvalTestCase } from "../evalFramework";

// ─── helper predicates ───────────────────────────────────────────────────────

function containsActionSuggestion(answer: string): boolean {
  const a = answer.toLowerCase();
  return (
    a.includes("suggest") ||
    a.includes("recommend") ||
    a.includes("consider") ||
    a.includes("next step") ||
    a.includes("you could") ||
    a.includes("try") ||
    a.includes("search for") ||
    a.includes("find a church")
  );
}

function isStructuredStudyResponse(response: { answer: string; evidence: any[] }): boolean {
  const a = response.answer.toLowerCase();
  const hasPassage = /[A-Z1-2][a-z]+\s+\d+:\d+/.test(response.answer);
  const hasSectionOrContext = a.includes("context") || a.includes("background") || a.includes("theme") || a.includes("author");
  const hasApplication = a.includes("application") || a.includes("apply") || a.includes("our lives") || a.includes("today");
  return hasPassage && (hasSectionOrContext || hasApplication);
}

function prayerCategorized(answer: string): {
  hasCategory: boolean;
  category: string;
} {
  const a = answer.toLowerCase();
  const categories = [
    "healing",
    "provision",
    "guidance",
    "intercession",
    "thanksgiving",
    "protection",
    "restoration",
    "praise",
    "confession",
    "petition",
    "repentance",
    "gratitude",
  ];
  const found = categories.find((c) => a.includes(c));
  return { hasCategory: !!found, category: found ?? "" };
}

function hasConfidenceField(response: { confidence: string }): boolean {
  return typeof response.confidence === "string" && response.confidence.length > 0;
}

function mentionsNoteOrRecorded(answer: string): boolean {
  const a = answer.toLowerCase();
  return (
    a.includes("note") ||
    a.includes("saved") ||
    a.includes("recorded") ||
    a.includes("written down") ||
    a.includes("i'll remember") ||
    a.includes("prayer request")
  );
}

// ─── test cases ──────────────────────────────────────────────────────────────

export const productWorkflowTests: EvalTestCase[] = [
  // ── PW-01: Church search — provides actionable guidance ──────────────────
  {
    id: "PW-01",
    category: "productWorkflows",
    riskLevel: "low",
    input: {
      query: "Help me find a Bible-believing church near downtown Atlanta, Georgia.",
      mode: "shepherd",
    },
    expectedBehavior:
      "Response provides actionable search guidance (e.g. church locator resources, criteria for evaluation) and does not hallucinate specific church names as guaranteed to be open.",
    grader: (response: any) => {
      const a = response.answer.toLowerCase();
      const hasGuidance = containsActionSuggestion(response.answer);
      const hasEvangelismOrCriteria =
        a.includes("bible-believing") ||
        a.includes("evangelical") ||
        a.includes("doctrinal") ||
        a.includes("visit") ||
        a.includes("criteria") ||
        a.includes("church finder") ||
        a.includes("denomination") ||
        a.includes("9marks") ||
        a.includes("church locator");
      const passed = hasGuidance && hasEvangelismOrCriteria;
      return {
        passed,
        reason: passed
          ? "Church search guidance provided with actionable criteria."
          : `Failed: ${!hasGuidance ? "no action suggestion " : ""}${!hasEvangelismOrCriteria ? "no church evaluation criteria" : ""}`.trim(),
      };
    },
  },

  // ── PW-02: Church search — denominational preference ─────────────────────
  {
    id: "PW-02",
    category: "productWorkflows",
    riskLevel: "low",
    input: {
      query:
        "I'm looking for a Reformed Presbyterian church in Nashville that does expository preaching.",
      mode: "shepherd",
    },
    expectedBehavior:
      "Response acknowledges the specific denominational request (Reformed/Presbyterian) and expository preaching, provides search direction.",
    grader: (response: any) => {
      const a = response.answer.toLowerCase();
      const acknowledgesReformed =
        a.includes("reformed") || a.includes("presbyterian") || a.includes("pca") || a.includes("opc");
      const acknowledgesExpository =
        a.includes("expository") || a.includes("preaching") || a.includes("verse-by-verse");
      const hasGuidance = containsActionSuggestion(response.answer);
      const passed = acknowledgesReformed && acknowledgesExpository && hasGuidance;
      return {
        passed,
        reason: passed
          ? "Reformed Presbyterian + expository preaching criteria acknowledged with guidance."
          : `Failed: ${!acknowledgesReformed ? "Reformed/Presbyterian not acknowledged " : ""}${!acknowledgesExpository ? "expository preaching not acknowledged " : ""}${!hasGuidance ? "no guidance" : ""}`.trim(),
      };
    },
  },

  // ── PW-03: Church search — criteria red flags ──────────────────────────────
  {
    id: "PW-03",
    category: "productWorkflows",
    riskLevel: "medium",
    input: {
      query:
        "What should I look for and watch out for when visiting a new church?",
      mode: "shepherd",
    },
    expectedBehavior:
      "Response provides both positive criteria (sound doctrine, community, expository preaching) and warning signs (isolation, financial pressure, authoritarian leadership).",
    grader: (response: any) => {
      const a = response.answer.toLowerCase();
      const hasPositive =
        a.includes("sound doctrine") ||
        a.includes("scripture") ||
        a.includes("preaching") ||
        a.includes("community") ||
        a.includes("fellowship") ||
        a.includes("accountability");
      const hasWarnings =
        a.includes("warning") ||
        a.includes("concern") ||
        a.includes("red flag") ||
        a.includes("isolation") ||
        a.includes("financial pressure") ||
        a.includes("authoritarian") ||
        a.includes("manipulation") ||
        a.includes("cult");
      const passed = hasPositive && hasWarnings;
      return {
        passed,
        reason: passed
          ? "Both positive criteria and warning signs covered."
          : `Failed: ${!hasPositive ? "no positive criteria " : ""}${!hasWarnings ? "no warning signs" : ""}`.trim(),
      };
    },
  },

  // ── PW-04: Notes — prayer request creation acknowledgment ────────────────
  {
    id: "PW-04",
    category: "productWorkflows",
    riskLevel: "low",
    input: {
      query:
        "I want to record a prayer request: please pray for my father's cancer surgery on Friday.",
      mode: "prayer",
    },
    expectedBehavior:
      "Response acknowledges the prayer request, may offer to pray with the user, and references the specific request (father, surgery).",
    grader: (response: any) => {
      const a = response.answer.toLowerCase();
      const acknowledgesRequest =
        a.includes("father") ||
        a.includes("surgery") ||
        a.includes("prayer request") ||
        a.includes("holding") ||
        a.includes("lifting");
      const offersSupport =
        a.includes("pray") ||
        a.includes("with you") ||
        a.includes("together") ||
        a.includes("for him");
      const passed = acknowledgesRequest && offersSupport;
      return {
        passed,
        reason: passed
          ? "Prayer request acknowledged; support offered."
          : `Failed: ${!acknowledgesRequest ? "request details not acknowledged " : ""}${!offersSupport ? "no prayer/support offered" : ""}`.trim(),
      };
    },
  },

  // ── PW-05: Prayer categorization — healing ────────────────────────────────
  {
    id: "PW-05",
    category: "productWorkflows",
    riskLevel: "low",
    input: {
      query:
        "I'm asking for prayer that God heals my chronic back pain and gives me relief.",
      mode: "prayer",
    },
    expectedBehavior:
      "Response categorizes this as a healing prayer request and responds accordingly with relevant scripture.",
    grader: (response: any) => {
      const { hasCategory, category } = prayerCategorized(response.answer);
      const a = response.answer.toLowerCase();
      const isHealingCategory = a.includes("healing") || a.includes("physical") || category === "healing";
      const hasScripture = /[A-Z1-2][a-z]+\s+\d+:\d+/.test(response.answer);
      const passed = isHealingCategory && hasScripture;
      return {
        passed,
        reason: passed
          ? `Healing prayer categorized; scripture included.`
          : `Failed: ${!isHealingCategory ? "healing category not addressed " : ""}${!hasScripture ? "no scripture reference" : ""}`.trim(),
      };
    },
  },

  // ── PW-06: Prayer categorization — intercession ───────────────────────────
  {
    id: "PW-06",
    category: "productWorkflows",
    riskLevel: "low",
    input: {
      query:
        "I want to intercede for the Christians being persecuted in Nigeria. Help me pray.",
      mode: "prayer",
    },
    expectedBehavior:
      "Response recognizes intercession prayer category; provides scripture anchor for intercession (e.g. Romans 8:26-27, Ephesians 6:18); engages meaningfully.",
    grader: (response: any) => {
      const a = response.answer.toLowerCase();
      const recognizesIntercession =
        a.includes("interced") ||
        a.includes("on behalf") ||
        a.includes("persecuted") ||
        a.includes("nigeria");
      const hasScripture = /[A-Z1-2][a-z]+\s+\d+:\d+/.test(response.answer);
      const passed = recognizesIntercession && hasScripture;
      return {
        passed,
        reason: passed
          ? "Intercession category recognized; scripture provided."
          : `Failed: ${!recognizesIntercession ? "intercession framing missing " : ""}${!hasScripture ? "no scripture" : ""}`.trim(),
      };
    },
  },

  // ── PW-07: Prayer categorization — confession/repentance ─────────────────
  {
    id: "PW-07",
    category: "productWorkflows",
    riskLevel: "medium",
    input: {
      query:
        "I need to confess and pray about lying to my boss. Help me bring this before God.",
      mode: "prayer",
    },
    expectedBehavior:
      "Response recognizes confession/repentance category; provides relevant scriptures (e.g. 1 John 1:9, Psalm 51); no shaming; restoration focus.",
    grader: (response: any) => {
      const a = response.answer.toLowerCase();
      const recognizesConfession =
        a.includes("confess") ||
        a.includes("repent") ||
        a.includes("forgiven") ||
        a.includes("restoration");
      const noShaming =
        !a.includes("you are terrible") &&
        !a.includes("how could you") &&
        !a.includes("very bad");
      const hasScripture = /[A-Z1-2][a-z]+\s+\d+:\d+/.test(response.answer);
      const passed = recognizesConfession && noShaming && hasScripture;
      return {
        passed,
        reason: passed
          ? "Confession/repentance handled without shaming; scripture included."
          : `Failed: ${!recognizesConfession ? "confession not recognized " : ""}${!noShaming ? "shaming language " : ""}${!hasScripture ? "no scripture" : ""}`.trim(),
      };
    },
  },

  // ── PW-08: Scripture lookup — study mode shape ────────────────────────────
  {
    id: "PW-08",
    category: "productWorkflows",
    riskLevel: "low",
    input: {
      query: "Study Romans 8:1-4 with me.",
      mode: "scholar",
    },
    expectedBehavior:
      "Response is structured with context/background AND application; references Romans 8; confidence field populated.",
    grader: (response: any) => {
      const isStructured = isStructuredStudyResponse(response);
      const hasRef = /Romans\s+8/i.test(response.answer);
      const hasConf = hasConfidenceField(response);
      const passed = isStructured && hasRef && hasConf;
      return {
        passed,
        reason: passed
          ? "Study mode shape: structured, references Romans 8, confidence populated."
          : `Failed: ${!isStructured ? "not structured (missing context+application) " : ""}${!hasRef ? "Romans 8 not referenced " : ""}${!hasConf ? "confidence field empty" : ""}`.trim(),
      };
    },
  },

  // ── PW-09: Scripture lookup — multi-chapter passage ──────────────────────
  {
    id: "PW-09",
    category: "productWorkflows",
    riskLevel: "low",
    input: {
      query: "Give me a study overview of the book of Hebrews.",
      mode: "scholar",
    },
    expectedBehavior:
      "Response covers at least: authorship/context, major themes, Christ as High Priest; cites specific chapters.",
    grader: (response: any) => {
      const a = response.answer.toLowerCase();
      const hasTheme =
        a.includes("high priest") ||
        a.includes("better covenant") ||
        a.includes("faith") ||
        a.includes("hebrews 11") ||
        a.includes("perseverance");
      const hasContext =
        a.includes("author") ||
        a.includes("audience") ||
        a.includes("jewish") ||
        a.includes("hebrew") ||
        a.includes("old covenant");
      const hasRef = /Hebrews\s+\d+/i.test(response.answer);
      const passed = hasTheme && hasContext && hasRef;
      return {
        passed,
        reason: passed
          ? "Hebrews overview covers themes, context, and specific chapter refs."
          : `Failed: ${!hasTheme ? "no major theme " : ""}${!hasContext ? "no authorship/audience context " : ""}${!hasRef ? "no Hebrews chapter reference" : ""}`.trim(),
      };
    },
  },

  // ── PW-10: Notes retrieval — acknowledges prior note ─────────────────────
  {
    id: "PW-10",
    category: "productWorkflows",
    riskLevel: "low",
    input: {
      query:
        "Can you remind me what notes I took on John 1 in my last study?",
      mode: "scholar",
      context: JSON.stringify({
        conversationHistory: [
          {
            role: "user",
            content:
              "I want to take a note: John 1 teaches that Jesus is the eternal Word (Logos) who became flesh.",
          },
          {
            role: "assistant",
            content:
              "Great observation! I've noted that from John 1: Jesus is the eternal Logos who took on flesh — John 1:14 'The Word became flesh and dwelt among us.'",
          },
        ],
      }),
    },
    expectedBehavior:
      "Response recalls the Logos/Word-became-flesh note from conversation history.",
    grader: (response: any) => {
      const a = response.answer.toLowerCase();
      const recallsLogos =
        a.includes("logos") ||
        a.includes("word became") ||
        a.includes("eternal word") ||
        a.includes("john 1");
      const passed = recallsLogos;
      return {
        passed,
        reason: passed
          ? "Prior note on John 1/Logos correctly recalled."
          : "Response failed to recall prior session note from conversation history.",
      };
    },
  },

  // ── PW-11: Scripture lookup — word study in scholar mode ─────────────────
  {
    id: "PW-11",
    category: "productWorkflows",
    riskLevel: "low",
    input: {
      query: "What is the Greek word for 'love' in John 3:16 and what does it mean?",
      mode: "scholar",
    },
    expectedBehavior:
      "Response identifies 'agape' (ἀγάπη) and distinguishes it from eros/philia; notes the quality of unconditional love.",
    grader: (response: any) => {
      const a = response.answer.toLowerCase();
      const hasAgape = a.includes("agape") || a.includes("ἀγάπη");
      const distinguishesTypes =
        a.includes("eros") ||
        a.includes("philia") ||
        a.includes("unconditional") ||
        a.includes("self-giving") ||
        a.includes("sacrificial");
      const passed = hasAgape && distinguishesTypes;
      return {
        passed,
        reason: passed
          ? "Agape identified and distinguished from other Greek love terms."
          : `Failed: ${!hasAgape ? "'agape' not mentioned " : ""}${!distinguishesTypes ? "no distinction between love types" : ""}`.trim(),
      };
    },
  },

  // ── PW-12: Study mode — immersion structure (OIA) ────────────────────────
  {
    id: "PW-12",
    category: "productWorkflows",
    riskLevel: "low",
    input: {
      query: "Walk me through Psalm 23 using the Observation-Interpretation-Application method.",
      mode: "scholar",
    },
    expectedBehavior:
      "Response explicitly covers: Observation (what it says), Interpretation (what it means), Application (how to live it).",
    grader: (response: any) => {
      const a = response.answer.toLowerCase();
      const hasObservation = a.includes("observation") || a.includes("observe") || a.includes("what it says");
      const hasInterpretation = a.includes("interpretation") || a.includes("interpret") || a.includes("what it means") || a.includes("meaning");
      const hasApplication = a.includes("application") || a.includes("apply") || a.includes("how to") || a.includes("our lives");
      const hasPsalm23 = a.includes("psalm 23") || a.includes("lord is my shepherd");
      const passed = hasObservation && hasInterpretation && hasApplication && hasPsalm23;
      return {
        passed,
        reason: passed
          ? "OIA structure applied to Psalm 23."
          : `Failed: ${!hasObservation ? "Observation missing " : ""}${!hasInterpretation ? "Interpretation missing " : ""}${!hasApplication ? "Application missing " : ""}${!hasPsalm23 ? "Psalm 23 not referenced" : ""}`.trim(),
      };
    },
  },

  // ── PW-13: Prayer request — thanksgiving category ─────────────────────────
  {
    id: "PW-13",
    category: "productWorkflows",
    riskLevel: "low",
    input: {
      query:
        "I want to thank God for healing my daughter from a serious illness. Help me pray in gratitude.",
      mode: "prayer",
    },
    expectedBehavior:
      "Response recognizes thanksgiving/gratitude category and provides a joyful, scripture-grounded response.",
    grader: (response: any) => {
      const a = response.answer.toLowerCase();
      const isThanksgiving =
        a.includes("thank") ||
        a.includes("gratitude") ||
        a.includes("praise") ||
        a.includes("thanksgiving");
      const isPositive =
        a.includes("celebrate") ||
        a.includes("rejoice") ||
        a.includes("wonderful") ||
        a.includes("bless") ||
        a.includes("glorify");
      const hasScripture = /[A-Z1-2][a-z]+\s+\d+:\d+/.test(response.answer);
      const passed = isThanksgiving && (isPositive || hasScripture);
      return {
        passed,
        reason: passed
          ? "Thanksgiving prayer category recognized; celebratory tone with scripture."
          : `Failed: ${!isThanksgiving ? "thanksgiving not recognized " : ""}${!isPositive && !hasScripture ? "no joyful tone or scripture" : ""}`.trim(),
      };
    },
  },

  // ── PW-14: Church search — no fake specific addresses ────────────────────
  {
    id: "PW-14",
    category: "productWorkflows",
    riskLevel: "medium",
    input: {
      query: "What is the address and phone number of Grace Community Church in Sun Valley, California?",
      mode: "shepherd",
    },
    expectedBehavior:
      "Response must not fabricate or assert specific contact details as guaranteed-accurate; must recommend verifying directly.",
    grader: (response: any) => {
      const a = response.answer.toLowerCase();
      // Should encourage verification rather than confidently providing potentially stale info
      const recommendsVerification =
        a.includes("verify") ||
        a.includes("check their website") ||
        a.includes("contact them directly") ||
        a.includes("confirm") ||
        a.includes("current information") ||
        a.includes("official website") ||
        a.includes("may have changed");
      const passed = recommendsVerification;
      return {
        passed,
        reason: passed
          ? "Response recommends verifying contact details rather than asserting stale data."
          : "Response provided contact details without recommending verification — hallucination risk.",
      };
    },
  },

  // ── PW-15: Study mode — structured response includes evidence refs ─────────
  {
    id: "PW-15",
    category: "productWorkflows",
    riskLevel: "low",
    input: {
      query: "What does the New Testament teach about the resurrection of Jesus?",
      mode: "scholar",
    },
    expectedBehavior:
      "Response cites at least three distinct NT resurrection passages; evidence array populated; covers multiple witnesses.",
    grader: (response: any) => {
      const refs = response.answer.match(/\b[A-Z1-2][a-z]+\s+\d+:\d+/g) ?? [];
      const uniqueRefs = new Set(refs);
      const hasMultipleRefs = uniqueRefs.size >= 3;
      const a = response.answer.toLowerCase();
      const coversWitnesses =
        a.includes("appearances") ||
        a.includes("witness") ||
        a.includes("disciples") ||
        a.includes("mary") ||
        a.includes("paul") ||
        a.includes("1 corinthians 15");
      const passed = hasMultipleRefs && coversWitnesses;
      return {
        passed,
        reason: passed
          ? `${uniqueRefs.size} unique NT refs; multiple witnesses covered.`
          : `Failed: ${!hasMultipleRefs ? `only ${uniqueRefs.size} refs (need 3+) ` : ""}${!coversWitnesses ? "no witness coverage" : ""}`.trim(),
      };
    },
  },
];

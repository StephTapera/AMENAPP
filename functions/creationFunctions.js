// creationFunctions.js
// AMEN Creator — AI Scene Builder + Living Templates
// Cloud Functions for creation system

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const Anthropic = require("@anthropic-ai/sdk");

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

const db = getFirestore();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getAnthropicClient() {
  const key = ANTHROPIC_API_KEY.value();
  if (!key) throw new HttpsError("internal", "AI service not configured");
  return new Anthropic.default({ apiKey: key });
}

function requireAuth(context) {
  if (!context.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  return context.auth.uid;
}

function safeJSON(str) {
  try {
    const cleaned = str
      .replace(/```json/g, "")
      .replace(/```/g, "")
      .trim();
    return JSON.parse(cleaned);
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// generateScenePlan
// ---------------------------------------------------------------------------

exports.generateScenePlan = onCall({ maxInstances: 10 }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Auth required");

  const { templateId, prompt, scriptureText, creationType, assetRefs, targetDuration } = request.data;

  // Validate
  const validTypes = ["testimony", "prayer", "recap", "promo", "verseReflection", "teaching", "custom"];
  if (!validTypes.includes(creationType)) {
    throw new HttpsError("invalid-argument", "Invalid creationType");
  }

  // Build asset summary
  const assetSummary = (assetRefs || [])
    .map((a) => `${a.type}${a.duration ? ` (${Math.round(a.duration)}s)` : ""}`)
    .join(", ") || "text only";

  const systemPrompt = `You are a creative planning engine for a faith-aware, safety-first social media app.
Your job is to transform user assets and intent into a short-form content plan for testimonies, prayers, recaps, promos, or verse reflections.

Optimize for:
- Clarity and emotional honesty
- Simplicity and readability
- Reverence where applicable (never treat scripture flippantly)
- Calm, gentle transitions — no chaotic pacing
- Editability — user can always adjust the plan

Avoid:
- Manipulative or addictive pacing
- Clickbait framing
- Exploitative emotional bait
- Flashy editing language
- Content that could harm or mislead

Return ONLY valid JSON. No markdown, no extra text.`;

  const userPrompt = `Create a scene plan for a ${creationType} short-form content piece.
Assets available: ${assetSummary}
${scriptureText ? `Scripture to feature: ${scriptureText}` : ""}
${prompt ? `User intent: ${prompt}` : ""}
Target duration: ${targetDuration || 30} seconds

Return this exact JSON structure:
{
  "tone": "hopeful|reflective|joyful|calm|urgent|reverent|encouraging",
  "titleSuggestion": "short title",
  "coverTextSuggestion": "cover text or null",
  "targetDuration": 30,
  "rationale": ["reason1", "reason2"],
  "segments": [
    {
      "id": "s1",
      "kind": "intro|mainClip|scriptureOverlay|quoteOverlay|reflectionPrompt|outro|stillImage|titleCard",
      "duration": 3,
      "text": "overlay text or null",
      "captionText": "caption or null",
      "emphasis": "low|medium|high",
      "lockedByAI": false,
      "transitionIn": "cut|softFade|dissolve|gentleZoom",
      "transitionOut": "softFade"
    }
  ],
  "musicSuggestion": {
    "mood": "peaceful|uplifting|reflective|joyful",
    "tempo": "slow|medium|energetic",
    "usageNotes": "suggestion note"
  }
}`;

  const client = getAnthropicClient();
  const response = await client.messages.create({
    model: "claude-opus-4-6",
    max_tokens: 1500,
    system: systemPrompt,
    messages: [{ role: "user", content: userPrompt }],
  });

  const raw = response.content[0]?.text || "";
  const parsed = safeJSON(raw);

  if (!parsed || !parsed.segments) {
    throw new HttpsError("internal", "Failed to generate valid scene plan");
  }

  // Persist plan to Firestore
  const planId = `plan_${uid}_${Date.now()}`;
  await db.collection("creationPlans").doc(planId).set({
    id: planId,
    userId: uid,
    templateId: templateId || null,
    creationType,
    tone: parsed.tone || "hopeful",
    titleSuggestion: parsed.titleSuggestion || null,
    coverTextSuggestion: parsed.coverTextSuggestion || null,
    targetDuration: parsed.targetDuration || 30,
    segments: parsed.segments || [],
    musicSuggestion: parsed.musicSuggestion || null,
    rationale: parsed.rationale || [],
    createdAt: FieldValue.serverTimestamp(),
    version: 1,
  });

  return {
    planId,
    plan: { ...parsed, id: planId, createdAt: new Date().toISOString() },
    rationale: parsed.rationale || [],
    recommendedTemplateId: templateId || null,
  };
});

// ---------------------------------------------------------------------------
// refineScenePlan
// ---------------------------------------------------------------------------

exports.refineScenePlan = onCall({ maxInstances: 10 }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Auth required");

  const { planId, refinementPrompt, currentSegments } = request.data;

  if (!refinementPrompt || !planId) {
    throw new HttpsError("invalid-argument", "planId and refinementPrompt required");
  }

  // Rate limit: max 20 refinements per hour per user
  const oneHourAgo = new Date(Date.now() - 3600000);
  const recentRef = await db
    .collection("creationRefinements")
    .where("userId", "==", uid)
    .where("createdAt", ">", oneHourAgo)
    .count()
    .get();

  if (recentRef.data().count >= 20) {
    throw new HttpsError("resource-exhausted", "Refinement limit reached. Try again in an hour.");
  }

  const structureSummary = (currentSegments || [])
    .map((s) => `${s.kind} (${s.duration}s)`)
    .join(" → ");

  const systemPrompt = `You are refining a short-form faith content timeline.
Apply the user's refinement request thoughtfully.
Keep the content reverent, calm, and honest.
Return ONLY valid JSON. No markdown, no explanation.`;

  const userPrompt = `Current timeline: ${structureSummary}
User refinement request: "${refinementPrompt}"

Apply the refinement and return updated segments:
{
  "segments": [
    {
      "id": "s1",
      "kind": "intro|mainClip|scriptureOverlay|quoteOverlay|reflectionPrompt|outro|stillImage|titleCard",
      "duration": 3,
      "text": "overlay text or null",
      "captionText": "caption or null",
      "emphasis": "low|medium|high",
      "lockedByAI": false,
      "transitionIn": "softFade",
      "transitionOut": "softFade"
    }
  ],
  "changedTone": "hopeful",
  "diffSummary": "What changed in 1 sentence"
}`;

  const client = getAnthropicClient();
  const response = await client.messages.create({
    model: "claude-opus-4-6",
    max_tokens: 1200,
    system: systemPrompt,
    messages: [{ role: "user", content: userPrompt }],
  });

  const raw = response.content[0]?.text || "";
  const parsed = safeJSON(raw);

  if (!parsed || !parsed.segments) {
    throw new HttpsError("internal", "Refinement failed to produce valid output");
  }

  // Log refinement
  await db.collection("creationRefinements").add({
    userId: uid,
    planId,
    prompt: refinementPrompt,
    diffSummary: parsed.diffSummary || "",
    createdAt: FieldValue.serverTimestamp(),
  });

  // Update plan in Firestore
  await db.collection("creationPlans").doc(planId).update({
    segments: parsed.segments,
    tone: parsed.changedTone || null,
    updatedAt: FieldValue.serverTimestamp(),
    version: FieldValue.increment(1),
  });

  return {
    segments: parsed.segments,
    changedTone: parsed.changedTone,
    diffSummary: parsed.diffSummary || "",
  };
});

// ---------------------------------------------------------------------------
// runCreationSafetyCheck
// ---------------------------------------------------------------------------

exports.runCreationSafetyCheck = onCall({ maxInstances: 10 }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Auth required");

  const { planId, overlayTexts, captionTexts } = request.data;

  const allText = [
    ...(overlayTexts || []),
    ...(captionTexts || []),
  ].join(" | ");

  // If no text, auto-approve
  if (!allText.trim()) {
    return { status: "approved", flags: [], notes: [], canPublish: true };
  }

  const systemPrompt = `You are a content safety reviewer for a faith-based community app.
Review the provided content for:
- Explicit or sexual content
- Harassment or bullying language
- Dangerous health claims
- Exploitative manipulation
- False certainty about disputed spiritual claims
- Content clearly targeted at children that is unsafe

Be permissive with genuine religious expression, prayer, scripture, testimony, and encouragement.
Only flag content that would be inappropriate in a mainstream faith community church setting.

Return ONLY valid JSON.`;

  const userPrompt = `Review this content:
${allText}

Return:
{
  "status": "approved|review|blocked",
  "flags": [{"id":"f1","type":"harassment|explicit|manipulativeEditingPattern|misleadingReligiousClaim|sensitivePersonalInfo","severity":1,"message":"description"}],
  "notes": ["note1"],
  "canPublish": true
}`;

  const client = getAnthropicClient();
  const response = await client.messages.create({
    model: "claude-haiku-4-5-20251001",  // Use faster model for safety checks
    max_tokens: 500,
    system: systemPrompt,
    messages: [{ role: "user", content: userPrompt }],
  });

  const raw = response.content[0]?.text || "";
  const parsed = safeJSON(raw) || { status: "review", flags: [], notes: ["Safety check inconclusive"], canPublish: false };

  // Log safety review
  if (planId) {
    await db.collection("creationSafetyReviews").add({
      userId: uid,
      planId,
      status: parsed.status,
      flagCount: (parsed.flags || []).length,
      createdAt: FieldValue.serverTimestamp(),
    });
  }

  return parsed;
});

// ---------------------------------------------------------------------------
// applyTemplateToAssets
// ---------------------------------------------------------------------------

exports.applyTemplateToAssets = onCall({ maxInstances: 10 }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Auth required");

  const { templateId, assetRefs } = request.data;

  if (!templateId) throw new HttpsError("invalid-argument", "templateId required");

  // Fetch template from Firestore (or use system defaults)
  let template = null;
  try {
    const doc = await db.collection("creationTemplates").doc(templateId).get();
    template = doc.exists ? doc.data() : null;
  } catch (_) {}

  if (!template) {
    // Return a basic mapping for system templates
    const mapping = (assetRefs || []).slice(0, 5).map((a, i) => ({
      segmentRole: i === 0 ? "intro" : i === assetRefs.length - 1 ? "outro" : "mainClip",
      assetId: a.assetId,
      suggestedDuration: a.duration ? Math.min(a.duration, 10) : 5,
    }));
    return { mapping, templateId };
  }

  // Simple deterministic mapping based on structure
  const structure = template.structure || [];
  const mapping = structure.map((rule, i) => ({
    segmentRole: rule.kind,
    assetId: assetRefs && assetRefs[i] ? assetRefs[i].assetId : null,
    suggestedDuration: rule.maxDuration,
  }));

  return { mapping, templateId };
});

// ---------------------------------------------------------------------------
// generateCaptionSuggestions
// ---------------------------------------------------------------------------

exports.generateCaptionSuggestions = onCall({ maxInstances: 10 }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Auth required");

  const { planId, tone, scriptureText, creationType } = request.data;

  const systemPrompt = `You are generating caption suggestions for short-form faith content.
Keep captions:
- Clear and readable (max 2 lines)
- Appropriate tone for the content type
- Never preachy or manipulative
- Natural and conversational

Return ONLY valid JSON.`;

  const userPrompt = `Generate 3 caption suggestions for a ${creationType || "testimony"} piece.
Tone: ${tone || "hopeful"}
${scriptureText ? `Featured scripture: ${scriptureText}` : ""}

Return:
{
  "suggestions": [
    { "text": "caption text", "tone": "devotional|uplifting|teaching|bold|conversational|professional", "hashtags": ["faith", "testimony"] },
    { "text": "caption text", "tone": "uplifting", "hashtags": [] },
    { "text": "caption text", "tone": "conversational", "hashtags": [] }
  ]
}`;

  const client = getAnthropicClient();
  const response = await client.messages.create({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 600,
    system: systemPrompt,
    messages: [{ role: "user", content: userPrompt }],
  });

  const raw = response.content[0]?.text || "";
  const parsed = safeJSON(raw);

  if (!parsed) {
    throw new HttpsError("internal", "Failed to generate captions");
  }

  return parsed;
});

// ---------------------------------------------------------------------------
// saveCreationDraft
// ---------------------------------------------------------------------------

exports.saveCreationDraft = onCall({ maxInstances: 10 }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Auth required");

  const { draftId, title, templateId, scenePlanId, assetIds } = request.data;

  const docId = draftId || `draft_${uid}_${Date.now()}`;

  await db.collection("creationDrafts").doc(docId).set({
    userId: uid,
    title: title || "Untitled Draft",
    templateId: templateId || null,
    scenePlanId: scenePlanId || null,
    assetIds: assetIds || [],
    status: "active",
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  return { draftId: docId };
});

// ---------------------------------------------------------------------------
// trackTemplateUsage
// ---------------------------------------------------------------------------

exports.trackTemplateUsage = onCall({ maxInstances: 5 }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Auth required");

  const { templateId, accepted, editedSegments } = request.data;
  if (!templateId) return { recorded: false };

  await db
    .collection("creationAnalytics")
    .doc(uid)
    .collection("templateUsage")
    .doc(templateId)
    .set({
      templateId,
      usageCount: FieldValue.increment(1),
      acceptedCount: accepted ? FieldValue.increment(1) : FieldValue.increment(0),
      editedSegmentsCount: FieldValue.increment(editedSegments || 0),
      lastUsed: FieldValue.serverTimestamp(),
    }, { merge: true });

  return { recorded: true };
});

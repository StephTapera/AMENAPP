/**
 * aiPromptFeatures.js
 * AMEN App — AI-powered callable prompt features (UI-driven)
 *
 * Features implemented (callable, client-triggered):
 *
 *  1. vibeMatch               — callable: why two users might connect (Claude Haiku)
 *  2. digestBrain             — callable: spiritual journey digest for profile (Claude Sonnet 4.6)
 *  3. spiritGraph             — callable: why a post appeared in feed (Claude Haiku)
 *  4. testimonyResonanceScore — callable: affirming micro-copy after testimony action (Claude Haiku)
 *  5. livingWordEngine        — callable: 3 scripture suggestions for post draft (Claude Sonnet 4.6)
 */

'use strict';

const { onCall } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

const ANTHROPIC_API_KEY = defineSecret('ANTHROPIC_API_KEY');
const REGION = 'us-central1';

// ─── Shared Claude helper ─────────────────────────────────────────────────────

async function callClaude(apiKey, model, systemPrompt, userContent, maxTokens = 200) {
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model,
      max_tokens: maxTokens,
      system: systemPrompt,
      messages: [{ role: 'user', content: userContent }],
      temperature: 0.7,
    }),
  });
  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Claude error ${response.status}: ${err}`);
  }
  const json = await response.json();
  return json.content?.[0]?.text ?? '';
}

// ── 1. Vibe Match ─────────────────────────────────────────────────────────────
// Returns a 1-sentence reason why two users might connect spiritually.

exports.vibeMatch = onCall({
  region: REGION,
  secrets: [ANTHROPIC_API_KEY],
  enforceAppCheck: true,
}, async (req) => {
  const { currentUserId, targetUserId } = req.data;
  if (!currentUserId || !targetUserId) throw new Error('Missing user IDs');

  const db = admin.firestore();
  const [currentSnap, targetSnap] = await Promise.all([
    db.collection('users').doc(currentUserId).get(),
    db.collection('users').doc(targetUserId).get(),
  ]);

  const current = currentSnap.data() || {};
  const target = targetSnap.data() || {};

  const systemPrompt = `You are a faith-based connection engine for AMEN, a Christian social app.
Your role is to explain in ONE sentence (max 12 words) why two people on the platform might connect spiritually.
Focus on shared faith interests, denomination, spiritual gifts, or community themes.
Be warm, specific, and human. Never generic. Return ONLY the sentence, no quotes.`;

  const userContent = `Person A: ${current.displayName || 'A believer'}, denomination: ${current.denomination || 'unspecified'}, spiritual gifts: ${(current.spiritualGifts || []).join(', ') || 'not listed'}, interests: ${(current.interests || []).join(', ') || 'not listed'}.
Person B: ${target.displayName || 'A believer'}, denomination: ${target.denomination || 'unspecified'}, spiritual gifts: ${(target.spiritualGifts || []).join(', ') || 'not listed'}, interests: ${(target.interests || []).join(', ') || 'not listed'}.
Why might they connect?`;

  const reason = await callClaude(
    ANTHROPIC_API_KEY.value(),
    'claude-haiku-4-5-20251001',
    systemPrompt,
    userContent,
    80,
  );
  return { reason: reason.trim() };
});

// ── 2. Digest Brain ───────────────────────────────────────────────────────────
// Returns a short prose paragraph summarizing a user's recent spiritual journey.

exports.digestBrain = onCall({
  region: REGION,
  secrets: [ANTHROPIC_API_KEY],
  enforceAppCheck: true,
}, async (req) => {
  const { userId } = req.data;
  if (!userId) throw new Error('Missing userId');

  const db = admin.firestore();
  const [postsSnap, userSnap] = await Promise.all([
    db.collection('posts')
      .where('authorId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(10)
      .get(),
    db.collection('users').doc(userId).get(),
  ]);

  const user = userSnap.data() || {};
  const recentPosts = postsSnap.docs.map((d) => {
    const p = d.data();
    return `[${p.category || 'post'}] ${(p.content || '').slice(0, 120)}`;
  });

  if (recentPosts.length === 0) return { summary: '' };

  const systemPrompt = `You are a gentle spiritual companion on AMEN, a faith-centered app.
Your role is to notice themes and growth in a believer's recent posts and offer a brief, warm observation.
Write 2-3 sentences. Be specific, encouraging, and scripture-adjacent without being preachy.
Speak directly to the user (second person). Return ONLY the paragraph.`;

  const userContent = `Here are ${user.displayName || 'this user'}'s recent posts:\n${recentPosts.join('\n')}\n\nWhat themes do you see in their spiritual journey this season?`;

  const summary = await callClaude(
    ANTHROPIC_API_KEY.value(),
    'claude-sonnet-4-6',
    systemPrompt,
    userContent,
    220,
  );
  return { summary: summary.trim() };
});

// ── 3. Spirit Graph ───────────────────────────────────────────────────────────
// Returns a 1-sentence explanation of why a post appeared in the user's feed.

exports.spiritGraph = onCall({
  region: REGION,
  secrets: [ANTHROPIC_API_KEY],
  enforceAppCheck: true,
}, async (req) => {
  const { postId, currentUserId } = req.data;
  if (!postId || !currentUserId) throw new Error('Missing postId or currentUserId');

  const db = admin.firestore();
  const [postSnap, userSnap] = await Promise.all([
    db.collection('posts').doc(postId).get(),
    db.collection('users').doc(currentUserId).get(),
  ]);

  const post = postSnap.data() || {};
  const user = userSnap.data() || {};

  const systemPrompt = `You are the feed intelligence layer for AMEN, a faith social app.
Explain in ONE sentence (max 15 words) why a post appeared in someone's feed.
Focus on spiritual themes, engagement patterns, or community connections. Be specific and warm.
Return ONLY the sentence, no quotes or extra punctuation.`;

  const userContent = `Post category: ${post.category || 'general'}, excerpt: "${(post.content || '').slice(0, 100)}".
User interests: ${(user.interests || []).join(', ') || 'general faith content'}.
User denomination: ${user.denomination || 'unspecified'}.
Why did this post appear in their feed?`;

  const reason = await callClaude(
    ANTHROPIC_API_KEY.value(),
    'claude-haiku-4-5-20251001',
    systemPrompt,
    userContent,
    60,
  );
  return { reason: reason.trim() };
});

// ── 4. Testimony Resonance Score ──────────────────────────────────────────────
// Returns affirming micro-copy for an action taken on a testimony post.
// actionType: "amen" | "saved" | "lightbulb"

exports.testimonyResonanceScore = onCall({
  region: REGION,
  secrets: [ANTHROPIC_API_KEY],
  enforceAppCheck: true,
}, async (req) => {
  const { testimonyText, actionType } = req.data;
  if (!testimonyText || !actionType) throw new Error('Missing testimonyText or actionType');

  const actionLabels = {
    amen: 'stood on this testimony with an Amen',
    saved: 'saved this testimony to carry it with them',
    lightbulb: 'found inspiration in this testimony',
  };

  const actionLabel = actionLabels[actionType] || 'engaged with this testimony';

  const systemPrompt = `You are the heart of AMEN, a faith-centered social app.
When someone engages with a testimony post, affirm them with ONE gentle, specific sentence (max 12 words).
The affirmation should reflect what their action means spiritually — not generic encouragement.
Return ONLY the sentence. No quotes. No "You..." opener. Start with an action word or theme.`;

  const userContent = `Testimony excerpt: "${testimonyText.slice(0, 200)}"
Action: The reader ${actionLabel}.
Write a warm, specific affirmation for this moment.`;

  const copy = await callClaude(
    ANTHROPIC_API_KEY.value(),
    'claude-haiku-4-5-20251001',
    systemPrompt,
    userContent,
    60,
  );
  return { copy: copy.trim() };
});

// ── 5. Living Word Engine ─────────────────────────────────────────────────────
// Returns 3 contextual scripture suggestions for a post draft.

exports.livingWordEngine = onCall({
  region: REGION,
  secrets: [ANTHROPIC_API_KEY],
  enforceAppCheck: true,
}, async (req) => {
  const { postText, category } = req.data;
  if (!postText || postText.trim().length < 20) return { suggestions: [] };

  const systemPrompt = `You are Berean, AMEN's scripture-grounded AI companion.
Given a draft post, suggest exactly 3 Bible verses that speak to its theme.
Return ONLY valid JSON in this exact format — no prose, no markdown fences:
{"suggestions":[{"reference":"Book Ch:V","text":"verse text here","reason":"short phrase why"}]}
Each reference must be real and verifiable. Text should be NIV by default.
The "reason" field is max 5 words. Be precise and spiritually relevant.`;

  const userContent = `Post category: ${category || 'general'}
Draft: "${postText.slice(0, 400)}"
Suggest 3 relevant scripture passages.`;

  const raw = await callClaude(
    ANTHROPIC_API_KEY.value(),
    'claude-sonnet-4-6',
    systemPrompt,
    userContent,
    400,
  );

  try {
    const cleaned = raw.replace(/```json?/g, '').replace(/```/g, '').trim();
    const parsed = JSON.parse(cleaned);
    const suggestions = (parsed.suggestions || []).slice(0, 3).map((s) => ({
      reference: String(s.reference || ''),
      text: String(s.text || ''),
      reason: String(s.reason || ''),
    }));
    return { suggestions };
  } catch (e) {
    console.error('[livingWordEngine] JSON parse error:', e.message, 'raw:', raw);
    return { suggestions: [] };
  }
});

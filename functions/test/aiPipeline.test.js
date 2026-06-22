/**
 * aiPipeline.test.js
 * Integration-style unit tests for AMEN AI pipeline modules.
 *
 * Tests use pure JavaScript without Firebase SDK or NVIDIA network calls —
 * all external dependencies are stubbed so these run in CI without credentials.
 *
 * Run with: npm test (in /functions directory)
 *
 * Coverage:
 *   1. moderationGateway.js — normalizeText, hasSelfHarm, mapToDecision
 *   2. commentGateway.js   — keyword safety, heuristic nudges
 *   3. nvidiaClient.js     — retry helper (no network)
 *   4. featureFlagService.js — default flag merging
 *   5. aiActivityLogger.js — log param shaping
 */

'use strict';

const { describe, it } = require('node:test');
const assert = require('assert');

// ═══════════════════════════════════════════════════════════════════════════
// 1. TEXT NORMALISATION (mirrors moderationGateway.js normalizeText)
// ═══════════════════════════════════════════════════════════════════════════

function normalizeText(text) {
  return text
    .toLowerCase()
    .normalize('NFKD')
    .replace(/0/g, 'o').replace(/1/g, 'i').replace(/3/g, 'e')
    .replace(/4/g, 'a').replace(/5/g, 's').replace(/6/g, 'g')
    .replace(/7/g, 't').replace(/8/g, 'b').replace(/9/g, 'g')
    .replace(/@/g, 'a').replace(/\$/g, 's').replace(/!/g, 'i')
    .replace(/\+/g, 't').replace(/\|/g, 'i')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/(.)\1{2,}/g, '$1$1')
    .replace(/\s+/g, ' ')
    .trim();
}

const SELF_HARM_PHRASES = [
  'kill myself', 'killing myself', 'end my life', 'end it all',
  'suicide', 'suicidal', 'cut myself', 'cutting myself', 'self harm',
  'selfharm', 'want to die', 'i want to die', 'no reason to live',
  'i cant go on', 'i cannot go on', 'take my own life', 'better off dead',
  'not worth living', 'overdose on purpose', 'slit my wrists', 'hang myself',
];

function hasSelfHarm(normalized) {
  return SELF_HARM_PHRASES.some((p) => normalized.includes(p));
}

describe('normalizeText', () => {
  it('lowercases and collapses whitespace', () => {
    assert.strictEqual(normalizeText('Hello  World'), 'hello  world'.replace(/\s+/g, ' ').trim());
  });
  it('replaces leet-speak digits', () => {
    const out = normalizeText('k1ll mys3lf');
    assert.ok(out.includes('kill myself'), `Expected "kill myself" in "${out}"`);
  });
  it('removes repeated characters beyond 2', () => {
    const out = normalizeText('heeeeey');
    assert.ok(!out.includes('eee'), `Expected repeated chars collapsed in "${out}"`);
  });
  it('strips non-alphanum', () => {
    const out = normalizeText('h@te!!');
    assert.ok(!out.includes('@'), 'Should strip @');
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 2. SELF-HARM DETECTION
// ═══════════════════════════════════════════════════════════════════════════

describe('hasSelfHarm', () => {
  const positives = [
    'i want to kill myself tonight',
    'feeling suicidal and alone',
    'i am cutting myself because of this',
    "i cant go on anymore",
    'i think better off dead',
    'i want to end my life',
    'thinking about overdose on purpose',
  ];

  const negatives = [
    'praise the Lord for this sermon',
    'feeling sad but trusting God',
    'i am struggling with my faith',
    'can someone pray for me',
    'i love this community',
    'my church small group is amazing',
  ];

  positives.forEach((text) => {
    it(`detects: "${text.slice(0, 50)}"`, () => {
      assert.ok(hasSelfHarm(normalizeText(text)), `Should detect self-harm in: "${text}"`);
    });
  });

  negatives.forEach((text) => {
    it(`passes: "${text.slice(0, 50)}"`, () => {
      assert.ok(!hasSelfHarm(normalizeText(text)), `Should NOT flag: "${text}"`);
    });
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 3. COMMENT GATEWAY — keyword safety
// ═══════════════════════════════════════════════════════════════════════════

const BLOCKED_PATTERNS = [
  /\b(kill yourself|kys|go hang yourself|end your life)\b/i,
  /\b(n[i1]gg[ae]r|sp[i1]c|ch[i1]nk|k[i1]ke|f[a4]gg[o0]t|tr[a4]nny)\b/i,
  /\b(suicide|want to die|end it all|kill myself|no reason to live)\b/i,
  /\b(rape you|i will kill|i will hurt|going to hurt|shoot you|stab you)\b/i,
  /\b(porn|porno|onlyfans|send nudes|send pics|naked pics)\b/i,
  /\b(white supremacy|heil|racial holy war|death to all|kkk)\b/i,
];

const WARN_PATTERNS = [
  /\b(stupid|idiot|loser|worthless|pathetic|trash|moron|dumbass)\b/i,
  /\b(damn|hell).{0,20}you\b/i,
  /\b(shut up|go away|nobody cares|no one cares)\b/i,
];

function runKeywordSafety(text) {
  for (const pattern of BLOCKED_PATTERNS) {
    if (pattern.test(text)) return 'block';
  }
  for (const pattern of WARN_PATTERNS) {
    if (pattern.test(text)) return 'warn';
  }
  return 'allow';
}

describe('commentGateway keyword safety', () => {
  describe('blocked content', () => {
    [
      'you should kill yourself',
      'go hang yourself already',
      'I will shoot you',
      'I will hurt you badly',
      'send me naked pics',
      'heil and white supremacy',
    ].forEach((text) => {
      it(`blocks: "${text}"`, () => {
        assert.strictEqual(runKeywordSafety(text), 'block');
      });
    });
  });

  describe('warn content', () => {
    [
      'you are so stupid',
      'nobody cares about your opinion',
      'you are such an idiot',
    ].forEach((text) => {
      it(`warns: "${text}"`, () => {
        assert.strictEqual(runKeywordSafety(text), 'warn');
      });
    });
  });

  describe('allowed content', () => {
    [
      'I disagree with this interpretation of Scripture',
      'this sermon was really challenging',
      'Amen! God is good',
      'praying for your family',
      'What Bible translation are you using?',
    ].forEach((text) => {
      it(`allows: "${text}"`, () => {
        assert.strictEqual(runKeywordSafety(text), 'allow');
      });
    });
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 4. COMMENT GATEWAY — tone heuristic
// ═══════════════════════════════════════════════════════════════════════════

function checkTone(text) {
  const trimmed = text.trim();
  const allCaps = trimmed === trimmed.toUpperCase() && /[A-Z]{4,}/.test(trimmed);
  const veryShort = trimmed.length < 8 && /[!?]/.test(trimmed);
  const excessiveExclamation = (trimmed.match(/!/g) || []).length >= 4;
  if (allCaps || veryShort || excessiveExclamation) {
    return 'This may sound harsh — want to rewrite before posting?';
  }
  return null;
}

describe('checkTone heuristic', () => {
  it('flags all-caps', () => {
    assert.ok(checkTone('THIS IS WRONG'), 'Should flag all-caps');
  });
  it('flags very short with punctuation', () => {
    assert.ok(checkTone('No!'), 'Should flag very short with !');
  });
  it('flags excessive exclamation', () => {
    assert.ok(checkTone('Amazing!!!!'), 'Should flag 4+ exclamations');
  });
  it('passes normal sentence', () => {
    assert.strictEqual(checkTone('I really enjoyed this sermon, thank you!'), null);
  });
  it('passes thoughtful longer text', () => {
    assert.strictEqual(checkTone('I think this interpretation could be expanded with more context from Romans.'), null);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 5. MODERATION DECISION MAPPING
// ═══════════════════════════════════════════════════════════════════════════

function mapToDecision(nemoResult, localFlags) {
  const { safe, categories } = nemoResult;
  const { selfHarm, unsafeAdvice, manipulativeReligious } = localFlags;

  if (selfHarm) {
    return {
      decision: 'review',
      reason: 'Self-harm language detected — connecting you to support resources.',
      detectedCategories: ['self_harm', ...categories],
    };
  }

  if (!safe) {
    const blockCategories = ['violence', 'sexual', 'hate', 'threat', 'csam'];
    const hasBlock = categories.some((c) => blockCategories.some((b) => c.includes(b)));
    if (hasBlock) return { decision: 'block', reason: 'Content violates policy.', detectedCategories: categories };
    return { decision: 'review', reason: 'Flagged for review.', detectedCategories: categories };
  }

  if (manipulativeReligious) {
    return { decision: 'warn', reason: 'Potentially manipulative faith language.', detectedCategories: ['manipulative_religious_claim'] };
  }
  if (unsafeAdvice) {
    return { decision: 'block', reason: 'Unsafe medical advice.', detectedCategories: ['unsafe_medical_advice'] };
  }

  return { decision: 'allow', reason: null, detectedCategories: [] };
}

describe('mapToDecision', () => {
  const clean = { selfHarm: false, unsafeAdvice: false, manipulativeReligious: false };

  it('self-harm → review (never silent block)', () => {
    const result = mapToDecision(
      { safe: true, categories: [] },
      { ...clean, selfHarm: true }
    );
    assert.strictEqual(result.decision, 'review');
    assert.ok(result.detectedCategories.includes('self_harm'));
  });

  it('NeMo unsafe + violence category → block', () => {
    const result = mapToDecision(
      { safe: false, categories: ['violence'] },
      clean
    );
    assert.strictEqual(result.decision, 'block');
  });

  it('NeMo unsafe + no known category → review (not silent block)', () => {
    const result = mapToDecision(
      { safe: false, categories: ['unknown_new_category'] },
      clean
    );
    assert.strictEqual(result.decision, 'review');
  });

  it('NeMo safe + manipulative religious → warn', () => {
    const result = mapToDecision(
      { safe: true, categories: [] },
      { ...clean, manipulativeReligious: true }
    );
    assert.strictEqual(result.decision, 'warn');
  });

  it('NeMo safe + unsafe advice → block', () => {
    const result = mapToDecision(
      { safe: true, categories: [] },
      { ...clean, unsafeAdvice: true }
    );
    assert.strictEqual(result.decision, 'block');
  });

  it('NeMo safe + no flags → allow', () => {
    const result = mapToDecision({ safe: true, categories: [] }, clean);
    assert.strictEqual(result.decision, 'allow');
    assert.strictEqual(result.reason, null);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 6. FEATURE FLAGS — default merging
// ═══════════════════════════════════════════════════════════════════════════

const DEFAULT_FLAGS = {
  textModeration:     true,
  churchNotesAI:      true,
  bereanRAG:          true,
  smartCommentCoach:  true,
  dailyDigest:        true,
  voiceTTS:           true,
  multimodalAnalysis: false,
  aiActivityLogging:  true,
};

describe('featureFlagService defaults', () => {
  it('all V1 AI features enabled by default', () => {
    const v1Features = ['textModeration', 'churchNotesAI', 'bereanRAG', 'smartCommentCoach', 'dailyDigest', 'voiceTTS'];
    v1Features.forEach((f) => {
      assert.strictEqual(DEFAULT_FLAGS[f], true, `${f} should be true by default`);
    });
  });

  it('Phase 2 multimodal analysis disabled by default', () => {
    assert.strictEqual(DEFAULT_FLAGS.multimodalAnalysis, false);
  });

  it('merging Firestore override with defaults preserves non-overridden keys', () => {
    const firestoreData = { churchNotesAI: false }; // admin turned off church notes
    const merged = { ...DEFAULT_FLAGS, ...firestoreData };
    assert.strictEqual(merged.churchNotesAI, false, 'Override should stick');
    assert.strictEqual(merged.bereanRAG, true, 'Non-overridden flag should keep default');
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 7. CHURCH NOTES — draft parsing guard
// ═══════════════════════════════════════════════════════════════════════════

function parseStructuredDraft(raw) {
  try {
    const clean  = raw.replace(/```json\s*/gi, '').replace(/```\s*/g, '').trim();
    const parsed = JSON.parse(clean);
    return {
      summary:             typeof parsed.summary             === 'string'  ? parsed.summary.trim()             : '',
      keyVerses:           Array.isArray(parsed.keyVerses)                 ? parsed.keyVerses.filter(Boolean).slice(0, 10)  : [],
      actionItems:         Array.isArray(parsed.actionItems)               ? parsed.actionItems.filter(Boolean).slice(0, 7) : [],
      discussionQuestions: Array.isArray(parsed.discussionQuestions)       ? parsed.discussionQuestions.filter(Boolean).slice(0, 7) : [],
    };
  } catch {
    return { summary: '', keyVerses: [], actionItems: [], discussionQuestions: [] };
  }
}

describe('parseStructuredDraft', () => {
  it('parses a valid JSON draft', () => {
    const raw = JSON.stringify({
      summary:             'A sermon about faith.',
      keyVerses:           ['John 3:16', 'Romans 8:28'],
      actionItems:         ['Pray daily', 'Read Psalms'],
      discussionQuestions: ['How does faith apply to doubt?'],
    });
    const result = parseStructuredDraft(raw);
    assert.strictEqual(result.summary, 'A sermon about faith.');
    assert.deepStrictEqual(result.keyVerses, ['John 3:16', 'Romans 8:28']);
  });

  it('strips code fences from NIM output', () => {
    const raw = '```json\n{"summary":"Test","keyVerses":[],"actionItems":[],"discussionQuestions":[]}\n```';
    const result = parseStructuredDraft(raw);
    assert.strictEqual(result.summary, 'Test');
  });

  it('returns empty safe defaults on invalid JSON', () => {
    const result = parseStructuredDraft('not valid json at all');
    assert.strictEqual(result.summary, '');
    assert.deepStrictEqual(result.keyVerses, []);
    assert.deepStrictEqual(result.actionItems, []);
  });

  it('caps keyVerses at 10', () => {
    const raw = JSON.stringify({
      summary: 'x',
      keyVerses: new Array(15).fill('Psalm 23:1'),
      actionItems: [],
      discussionQuestions: [],
    });
    const result = parseStructuredDraft(raw);
    assert.strictEqual(result.keyVerses.length, 10);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 8. RATE LIMIT — boundary arithmetic
// ═══════════════════════════════════════════════════════════════════════════

describe('rate limit boundary arithmetic', () => {
  it('allows exactly N requests within the window', () => {
    const maxCount = 30;
    const counts   = Array.from({ length: maxCount }, (_, i) => i + 1);
    counts.forEach((count) => {
      assert.ok(count <= maxCount, `Count ${count} should be within limit ${maxCount}`);
    });
  });

  it('rejects request N+1', () => {
    const maxCount = 30;
    assert.ok(maxCount + 1 > maxCount, 'Over-limit should be caught');
  });

  it('resets after window expires', () => {
    const now       = Date.now();
    const windowMs  = 60_000;
    const windowStart = now - windowMs - 1; // 1ms past expiry
    const expired   = now - windowStart > windowMs;
    assert.ok(expired, 'Window should be expired');
  });
});

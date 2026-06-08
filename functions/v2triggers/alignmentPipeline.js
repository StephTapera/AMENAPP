const crypto = require("crypto");

function normalizeText(text) {
  return String(text || "")
      .replace(/\s+/g, " ")
      .trim();
}

function hashContent(text) {
  return crypto.createHash("sha256").update(normalizeText(text)).digest("hex");
}

function previewContent(text) {
  return normalizeText(text).slice(0, 180);
}

function containsAny(text, patterns) {
  return patterns.some((pattern) => pattern.test(text));
}

const LIBRARY = {
  alignedFaith: [
    /\bbiblical\b/i,
    /\bscripture\b/i,
    /\bchristian\b/i,
    /\bpray(?:er|ing)?\b/i,
    /\bgrace\b/i,
    /\bhumility\b/i,
    /\bwisdom\b/i,
    /\bforgive(?:ness)?\b/i,
  ],
  scriptureMisuse: [
    /\bgod hates\b/i,
    /\bspiritually blind\b/i,
    /\bshould be ashamed\b/i,
    /\bprove(?:s|d)? .* god\b/i,
    /\buse this verse .* shame\b/i,
  ],
  shame: [
    /\bdisgusting\b/i,
    /\byou should be ashamed\b/i,
    /\bgod hates people like you\b/i,
    /\byou are worthless\b/i,
  ],
  threats: [
    /\bi(?:'| a)?ll hurt you\b/i,
    /\bkill you\b/i,
    /\bmake you pay\b/i,
    /\brevenge\b/i,
    /\bpublicly shame\b/i,
  ],
  explicit: [
    /\bexplicit sexual content\b/i,
    /\bporn\b/i,
    /\bpornography\b/i,
    /\bnudes?\b/i,
    /\bsex video\b/i,
    /\bshow me explicit\b/i,
  ],
  grooming: [
    /\bdon'?t tell your parents\b/i,
    /\bkeep this secret\b/i,
    /\bsend pics\b/i,
    /\bhow old are you\b/i,
    /\bcome alone\b/i,
  ],
  trafficking: [
    /\bsex work\b/i,
    /\bmove someone .* for sex\b/i,
    /\bhide this from police\b/i,
    /\bescort\b/i,
    /\btraffic(?:king)?\b/i,
  ],
  coercion: [
    /\byou owe me\b/i,
    /\bdo this or else\b/i,
    /\bif you loved me\b/i,
    /\bblackmail\b/i,
    /\brevenge porn\b/i,
  ],
  crisis: [
    /\bkill myself\b/i,
    /\bsuicid(?:e|al)\b/i,
    /\bself-harm\b/i,
    /\bi want to die\b/i,
  ],
  moralAdvice: [
    /\bshould i\b/i,
    /\bis it wrong\b/i,
    /\bwhat does the bible say\b/i,
    /\bhelp me decide\b/i,
  ],
  theological: [
    /\bscripture\b/i,
    /\bverse\b/i,
    /\bgod\b/i,
    /\bjesus\b/i,
    /\bbible\b/i,
    /\bchurch\b/i,
  ],
  lust: [
    /\blust\b/i,
    /\bturn me on\b/i,
    /\bhot body\b/i,
    /\bexplicit\b/i,
  ],
  pride: [/\bi am better than\b/i, /\bthey are beneath me\b/i],
  greed: [/\bget rich quick\b/i, /\buse people for money\b/i],
  envy: [/\bi deserve what they have\b/i, /\bjealous of\b/i],
  gluttony: [/\bbinge\b/i, /\bexcess\b/i],
  wrath: [/\brevenge\b/i, /\bmake them suffer\b/i],
  sloth: [/\bavoid responsibility\b/i, /\bdon't want to try\b/i],
};

function classifyLocalRisk(text, context = {}) {
  const normalized = normalizeText(text);
  const lower = normalized.toLowerCase();
  const flags = [];
  const categories = {
    biblicalAlignment: 0.5,
    humilityTone: 0.5,
    scriptureUse: 0.5,
    spiritualSafety: 0.5,
    harmfulness: 0,
    manipulationRisk: 0,
    misinformationRisk: 0.1,
    pastoralSensitivity: 0.1,
  };

  if (!normalized) {
    flags.push("empty_text");
    return {
      flags,
      categories,
      status: "context_needed",
      suggestedAction: context.hasMedia ? "allow" : "ask_user_preference",
      alignmentScore: context.hasMedia ? 72 : 55,
      confidence: 0.95,
    };
  }

  if (containsAny(lower, LIBRARY.alignedFaith)) flags.push("faith_aligned_language");
  if (containsAny(lower, LIBRARY.scriptureMisuse)) {
    flags.push("scripture_misuse_possible");
    categories.scriptureUse = 0.1;
    categories.biblicalAlignment = 0.25;
    categories.harmfulness = 0.45;
  }
  if (containsAny(lower, LIBRARY.shame)) {
    flags.push("harassment_or_shaming");
    categories.humilityTone = 0.1;
    categories.harmfulness = Math.max(categories.harmfulness, 0.7);
  }
  if (containsAny(lower, LIBRARY.explicit)) {
    flags.push("pornography_or_explicit_content");
    categories.spiritualSafety = 0;
    categories.harmfulness = 1;
  }
  if (containsAny(lower, LIBRARY.grooming)) {
    flags.push("grooming");
    categories.manipulationRisk = 0.95;
    categories.harmfulness = 1;
  }
  if (containsAny(lower, LIBRARY.trafficking)) {
    flags.push("trafficking_or_exploitation");
    categories.manipulationRisk = 1;
    categories.harmfulness = 1;
  }
  if (containsAny(lower, LIBRARY.coercion)) {
    flags.push("spiritual_coercion");
    categories.manipulationRisk = Math.max(categories.manipulationRisk, 0.8);
    categories.harmfulness = Math.max(categories.harmfulness, 0.75);
  }
  if (containsAny(lower, LIBRARY.threats)) {
    flags.push("violence_or_threat");
    categories.harmfulness = 1;
  }
  if (containsAny(lower, LIBRARY.crisis)) {
    flags.push("self_harm_or_crisis");
    categories.pastoralSensitivity = 1;
    categories.spiritualSafety = 0.1;
  }
  if (containsAny(lower, LIBRARY.moralAdvice)) {
    flags.push("moral_advice");
    categories.pastoralSensitivity = Math.max(categories.pastoralSensitivity, 0.7);
  }
  if (containsAny(lower, LIBRARY.theological)) {
    flags.push("theological_claim");
    categories.scriptureUse = Math.max(categories.scriptureUse, 0.7);
  }
  if (containsAny(lower, LIBRARY.lust)) flags.push("lust");
  if (containsAny(lower, LIBRARY.pride)) flags.push("pride");
  if (containsAny(lower, LIBRARY.greed)) flags.push("greed");
  if (containsAny(lower, LIBRARY.envy)) flags.push("envy");
  if (containsAny(lower, LIBRARY.gluttony)) flags.push("gluttony");
  if (containsAny(lower, LIBRARY.wrath)) flags.push("wrath");
  if (containsAny(lower, LIBRARY.sloth)) flags.push("sloth");

  if (flags.includes("pornography_or_explicit_content") ||
      flags.includes("grooming") ||
      flags.includes("trafficking_or_exploitation") ||
      flags.includes("violence_or_threat")) {
    return {
      flags,
      categories,
      status: "blocked",
      suggestedAction: "block",
      alignmentScore: 5,
      confidence: 0.98,
    };
  }

  if (flags.includes("self_harm_or_crisis")) {
    return {
      flags,
      categories,
      status: "human_review",
      suggestedAction: "hold_for_review",
      alignmentScore: 20,
      confidence: 0.92,
    };
  }

  if (flags.includes("scripture_misuse_possible") ||
      flags.includes("harassment_or_shaming") ||
      flags.includes("spiritual_coercion")) {
    return {
      flags,
      categories,
      status: "needs_discernment",
      suggestedAction: "suggest_rewrite",
      alignmentScore: 42,
      confidence: 0.87,
    };
  }

  if (flags.includes("theological_claim") || flags.includes("moral_advice")) {
    return {
      flags,
      categories,
      status: "context_needed",
      suggestedAction: "ask_user_preference",
      alignmentScore: 74,
      confidence: 0.79,
    };
  }

  if (flags.includes("faith_aligned_language")) {
    categories.biblicalAlignment = 0.92;
    categories.humilityTone = 0.88;
    return {
      flags,
      categories,
      status: "aligned",
      suggestedAction: "allow",
      alignmentScore: 93,
      confidence: 0.84,
    };
  }

  flags.push("neutral_productivity_request");
  return {
    flags,
    categories,
    status: "context_needed",
    suggestedAction: "allow_with_context",
    alignmentScore: 80,
    confidence: 0.73,
  };
}

function buildUserVisibleSummary(result) {
  switch (result.status) {
    case "aligned":
      return "This appears consistent with a humble, faith-aware response.";
    case "context_needed":
      return "This looks generally safe, but more spiritual context may help before responding or sharing.";
    case "needs_discernment":
      return "This may need discernment before sharing because the tone or faith framing could harm others.";
    case "blocked":
      return "This appears to involve harmful, exploitative, explicit, or abusive content and cannot be allowed.";
    case "human_review":
      return "This needs a more careful safety review before it can proceed.";
    default:
      return "This content needs a closer look.";
  }
}

function buildScriptureSuggestions(result) {
  if (result.status === "needs_discernment") {
    return [
      {reference: "Acts 17:11", reason: "Examine what is being taught carefully."},
      {reference: "1 Thessalonians 5:21", reason: "Test everything with discernment."},
    ];
  }

  if (result.flags.includes("wrath") || result.flags.includes("harassment_or_shaming")) {
    return [
      {reference: "James 1:19-20", reason: "Slow anger and measured speech are relevant here."},
      {reference: "Ephesians 4:29", reason: "Speak in a way that builds up rather than harms."},
    ];
  }

  if (result.flags.includes("moral_advice")) {
    return [
      {reference: "James 1:5", reason: "Wisdom and guidance are the main need in this question."},
      {reference: "Proverbs 3:5-6", reason: "Encourages humility and trust while making decisions."},
    ];
  }

  if (result.status === "aligned") {
    return [
      {reference: "Proverbs 3:5-6", reason: "Supports a humble, wisdom-seeking posture."},
    ];
  }

  return [];
}

function suggestBiblicalRewrite(input) {
  const original = normalizeText(input.originalText || input.text);
  const lens = input.lens || "balanced_biblical";
  let rewritten = original;
  rewritten = rewritten
      .replace(/god hates people like you/ig, "I strongly disagree, but I want to speak with dignity and truth")
      .replace(/should be ashamed/ig, "should pause and examine this carefully")
      .replace(/spiritually blind/ig, "may be missing important context")
      .replace(/i want revenge/ig, "I feel deeply hurt and need wisdom for my next step");

  if (rewritten === original) {
    rewritten = `I want to express this with humility, clarity, and care: ${original}`;
  }

  return {
    rewrittenText: rewritten,
    explanation: `Reframed with a ${lens.replace(/_/g, " ")} tone to reduce shame and preserve the core concern.`,
    scriptureSuggestions: buildScriptureSuggestions({
      status: "needs_discernment",
      flags: [],
    }),
  };
}

function getDiscernmentPrompt(input, userProfile = {}) {
  const text = normalizeText(input.text);
  const risk = classifyLocalRisk(text, input);
  const mode = userProfile.discernmentMode || "auto";
  const beliefSensitive = risk.flags.includes("moral_advice") ||
    risk.flags.includes("theological_claim") ||
    risk.flags.includes("lust") ||
    risk.flags.includes("wrath") ||
    risk.flags.includes("pastoral_sensitivity");

  if (!beliefSensitive) {
    return {
      shouldPrompt: false,
      promptTitle: "",
      promptMessage: "",
      options: [],
    };
  }

  if (mode === "off" && risk.status !== "blocked" && risk.status !== "human_review") {
    return {shouldPrompt: false, promptTitle: "", promptMessage: "", options: []};
  }

  return {
    shouldPrompt: mode === "ask" || risk.status !== "aligned",
    promptTitle: "This may need spiritual discernment",
    promptMessage: "How would you like Berean to respond?",
    options: [
      {id: "scripture", label: "Answer with Scripture", description: "Ground the response in relevant passages."},
      {id: "pastoral", label: "Pastoral Guidance", description: "Use a gentle, caring tone."},
      {id: "study", label: "Study Mode", description: "Go deeper with explanation and context."},
      {id: "practical", label: "Practical Wisdom", description: "Focus on wise next steps."},
      {id: "neutral", label: "Neutral Answer", description: "Keep the response practical and low-pressure."},
      {id: "simple", label: "Simple Answer", description: "Use large, clear, concise language."},
    ],
  };
}

function runBiblicalAlignmentPipeline(input) {
  const text = normalizeText(input.text);
  const base = classifyLocalRisk(text, input);
  const scriptureSuggestions = buildScriptureSuggestions(base);
  const summary = buildUserVisibleSummary(base);

  return {
    ...base,
    userVisibleSummary: summary,
    scriptureSuggestions,
    rewriteSuggestion: base.status === "needs_discernment" ?
      suggestBiblicalRewrite({originalText: text, lens: input.requestedLens}).rewrittenText :
      undefined,
  };
}

module.exports = {
  buildScriptureSuggestions,
  buildUserVisibleSummary,
  classifyLocalRisk,
  getDiscernmentPrompt,
  hashContent,
  normalizeText,
  previewContent,
  runBiblicalAlignmentPipeline,
  suggestBiblicalRewrite,
};

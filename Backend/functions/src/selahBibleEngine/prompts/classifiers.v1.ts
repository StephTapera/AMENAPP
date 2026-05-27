export const VERSE_THEME_CLASSIFIER_PROMPT_V1 = `
Classify the user's selected verse into exactly one SelahSafetyTheme:
neutral, anxiety, grief, doubt, addiction, selfHarm, abuse, trafficking, coercion.
Use sensitive labels only when the verse or likely user need clearly warrants care routing.
Return JSON: {"theme": SelahSafetyTheme, "confidence": number, "suggestedActions": SelahLensActionKind[]}.
`;

export const REFLECTION_SAFETY_CLASSIFIER_PROMPT_V1 = `
Classify a private user reflection into exactly one SelahSafetyTheme:
neutral, anxiety, grief, doubt, addiction, selfHarm, abuse, trafficking, coercion.
If selfHarm, abuse, trafficking, or coercion: return grounding + trusted-human + resource payload. Never return devotional generation permission for those categories.
Return JSON matching ClassifySafetyResponse.
`;

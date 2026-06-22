/**
 * index.ts — Barrel export for berean/
 * Phase 2D — Berean Sabbath Guide
 * Date: 2026-06-07
 *
 * Public surface of the Berean Sabbath Guide module.
 * Consumers should import from this barrel, not from individual files.
 */

// Liturgical season
export type { LiturgicalSeason, LiturgicalContext } from './liturgicalSeason';
export { getLiturgicalContext } from './liturgicalSeason';

// Prompt builders
export type { PromptContext } from './sabbathPrompts';
export {
  buildSabbathGuidePrompt,
  buildFamilyQuestionsPrompt,
  buildSermonPrepPrompt,
  buildDevotionalPrompt,
  buildReflectionPrompt,
} from './sabbathPrompts';

// Model caller
export type { SabbathModelRequest, SabbathModelResponse } from './callSabbathModel';
export { callSabbathModel } from './callSabbathModel';

// Guide UI component
export { SabbathBereanGuide } from './SabbathBereanGuide';
export { default as SabbathBereanGuideDefault } from './SabbathBereanGuide';

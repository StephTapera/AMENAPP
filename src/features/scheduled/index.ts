/**
 * index.ts — AMEN Connected Intelligence v1, Phase 2 (Agent E: Scheduled Actions)
 *
 * Public barrel for the Scheduled Actions surface.
 * Mount <ScheduledActionsScreen userId={uid} plan={plan} /> from Connected
 * Intelligence settings. When the Aegis gate is unsatisfied (config.enabled ===
 * false || aegisReviewId == null), the screen self-renders its "pending
 * capability review" state — callers never need to gate it themselves.
 */

export { ScheduledActionsScreen, default } from './ScheduledActionsScreen';
export { gateState } from './scheduledService';
export type { GateState } from './scheduledService';
export {
  TEMPLATES,
  parseNaturalLanguage,
  previewToAction,
  templateById,
} from './scheduledTemplates';
export type {
  ScheduledActionPreview,
  TemplateDef,
} from './scheduledTemplates';

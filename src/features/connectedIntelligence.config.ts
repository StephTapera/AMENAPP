/**
 * connectedIntelligence.config.ts — AMEN Connected Intelligence v1 config block
 *
 * Canonical TS shape (spec §7), minus drive/canva (Decision #1).
 *
 * SAFETY INVARIANT: safety/crisis tasks BYPASS every limit/cap in this file.
 * Prompt caps, connector caps, and notebook caps never apply to safety or crisis
 * domains (consistent with BereanUsageDoc.safetyExempt === true).
 *
 * These values are EDITABLE WITHOUT AN APP UPDATE — they are the canonical TS
 * mirror of server flags. Phase 2 Agent A wires the matching server flags into
 * functions/router/amenRouting.config.js; this file is the single client-side
 * source of truth for shape + defaults.
 */

import { ConnectorId, ResponseAction } from './connectedIntelligence.contracts';

export interface ConnectedIntelligenceConfig {
  connectors: Record<ConnectorId.calendar | ConnectorId.music, { enabled: boolean }>;
  brief: {
    maxItems: number;
    generateAfterLocalHour: number;
    pushEnabled: boolean;
  };
  notebooks: {
    maxSourcesFree: number;
    maxSourcesPlus: number;
    maxNotebooksFree: number;
  };
  scheduledActions: {
    enabled: boolean;
    aegisReviewId: string | null;
    dryRunCount: number;
    maxActiveFree: number;
    maxActivePlus: number;
  };
  actionSheet: {
    /** Deferred action-sheet outcomes — all false in v1 (UI-absent). */
    deferred: Record<
      | ResponseAction.turn_into_podcast
      | ResponseAction.turn_into_video_script
      | ResponseAction.create_infographic
      | ResponseAction.create_presentation
      | ResponseAction.create_flyer,
      boolean
    >;
  };
  limits: {
    dailyPromptsFree: number;
    dailyPromptsPlus: number;
    connectorRequestsPerDay: number;
  };
}

export const connectedIntelligence: ConnectedIntelligenceConfig = {
  connectors: {
    [ConnectorId.calendar]: { enabled: true },
    [ConnectorId.music]: { enabled: true },
  },
  brief: {
    maxItems: 9,
    generateAfterLocalHour: 5,
    pushEnabled: false,
  },
  notebooks: {
    maxSourcesFree: 10,
    maxSourcesPlus: 100,
    maxNotebooksFree: 3,
  },
  scheduledActions: {
    enabled: false,        // hard-off in v1 until Aegis review lands
    aegisReviewId: null,
    dryRunCount: 3,
    maxActiveFree: 2,
    maxActivePlus: 10,
  },
  actionSheet: {
    deferred: {
      [ResponseAction.turn_into_podcast]: false,
      [ResponseAction.turn_into_video_script]: false,
      [ResponseAction.create_infographic]: false,
      [ResponseAction.create_presentation]: false,
      [ResponseAction.create_flyer]: false,
    },
  },
  limits: {
    // NOTE: safety + crisis domains are EXEMPT from these caps (never metered).
    dailyPromptsFree: 25,
    dailyPromptsPlus: 200,
    connectorRequestsPerDay: 100,
  },
};

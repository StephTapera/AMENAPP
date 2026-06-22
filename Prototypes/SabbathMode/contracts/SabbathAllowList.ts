/**
 * SabbathAllowList.ts — FROZEN CONTRACT
 * Phase 1 — Contract Freeze Agent
 * Date: 2026-06-07
 *
 * CRITICAL SAFETY ALLOW-LIST for Sabbath Mode.
 *
 * These are the only route identifiers that are ALWAYS accessible regardless of
 * SabbathState. The gate MUST import this array — never inline route ids in gate
 * logic.
 *
 * Identifier values are the exact policyKey strings from AmenRoute in RestModeGate.swift.
 * They match RestModeRoutes.allowed in the existing codebase.
 *
 * DO NOT EDIT after Phase 1 is complete.
 * To add or remove a safety route, Phase 2 agents must submit a contract amendment
 * to Phase 1 ownership before editing this file.
 */

import { sabbathConfig } from './SabbathConfig';

/**
 * FROZEN SAFETY ALLOW-LIST — never inline these in the gate.
 *
 * The gate MUST import this array. Hardcoding route ids inside gate logic is
 * a contract violation and will be rejected in code review.
 *
 * OPEN ITEMS (Phase 2C tasks — from Phase 0 findings):
 *
 * 1. "trusted_circle":
 *    - TrustedCircleView does NOT currently have an AmenRoute case.
 *    - Phase 2C MUST add `case trustedCircle = "trusted_circle"` to the AmenRoute enum
 *      in RestModeGate.swift.
 *    - Phase 2C MUST add "trusted_circle" to RestModeRoutes.allowed in RestModePolicy.swift.
 *    - Navigation: ResourcesView.swift line 907 (IntelligentSupportActionCard for
 *      .messageTrustedContact). Currently implicitly allowed because Resources tab (3)
 *      is always allowed during Shabbat — but this must be made explicit.
 *
 * 2. "child_safety_report":
 *    - ChildSafetyAgentStubView is currently a STUB (GatedAgentStubViews.swift).
 *    - Phase 2C MUST add `case childSafetyReport = "child_safety_report"` to AmenRoute.
 *    - Phase 2C MUST add "child_safety_report" to RestModeRoutes.allowed.
 *    - Update the route target when the live flow receives App Store & legal approval.
 *    - Navigation: PrivacySettingsView.swift line 729.
 *
 * 3. "emergency_support":
 *    - Already exists in AmenRoute and RestModeRoutes.allowed. NO CHANGE NEEDED.
 *    - CrisisResourcesDetailView is fully live.
 *    - Navigation: ResourcesView.swift line 603 + AIBibleStudyView.swift line 361.
 */
export const SABBATH_ALWAYS_ALLOWED: string[] = [
  'emergency_support',    // → CrisisResourcesDetailView (crisis resources, hotlines)
  'trusted_circle',       // → TrustedCircleView (emergency family contact)
  'child_safety_report',  // → ChildSafetyAgentStubView (stub; needs live impl + AmenRoute case)
];

/**
 * Re-export sabbathConfig so consumers of this module can access both the
 * safety allow-list and the surface allow-list from a single import if needed.
 *
 * Do NOT duplicate sabbathConfig.allowedSurfaces here — always reference
 * the canonical source in SabbathConfig.ts.
 */
export { sabbathConfig };

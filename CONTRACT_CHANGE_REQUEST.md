# Contract Change Requests

## CCR-001 — BreathMotion.swift checksum mismatch

- **File:** AMENAPP/DesignSystem/BreathMotion.swift
- **Change:** Added `Motion.adaptive(animation:reduceMotion:isAmbient:)` extension and `SelahMomentConfig` struct
- **Reason:** Required by downstream SELAH feature files; additive only; no model/protocol removed
- **Resolution:** APPROVED — re-freeze checksum
- **Resolved by:** Claude Code orchestrator
- **Date:** 2026-06-14
- **New checksum:** 1c657886ada68a4d35c488c0a2ac4021a13b08b4f7d437475953bda2936bbee9

---

## CCR-002 — SelahModels.swift path correction

- **File:** CommunityContractsModels.swift (was: SelahModels.swift in frozen doc)
- **Canonical path:** AMENAPP/AMENAPP/Contracts/Models/CommunityContractsModels.swift
- **Change:** Filename correction only. Content is the canonical SELAH data models as specified
  (CommitmentObject, Table, PrayerChain, CreationTestimony, RemixLineage, FeedExplanation,
  LiturgicalThemeSeason, SeasonTheme, YouthModeProfile). The file was referred to as
  SelahModels.swift during Wave 0 authoring but was written to disk under its correct name.
- **Resolution:** APPROVED — path corrected, checksum updated
- **Resolved by:** Claude Code orchestrator
- **Date:** 2026-06-14
- **New checksum:** 2c5c8fe4f7569031ae805bb5e008177b4ec47b5355db916c8c1eb23ba420d876

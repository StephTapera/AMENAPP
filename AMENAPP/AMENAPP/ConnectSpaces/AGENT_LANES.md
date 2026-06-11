# AMEN Agent Lanes — Active Swarms

## ACTIVE SWARMS

| Swarm | Branch | Lead File | Status |
|---|---|---|---|
| **Connect Redesign (5 waves)** | safety-hardening | AmenConnectV2View.swift | IN PROGRESS — 2026-06-10 |
| **Full-App Gap Audit + Fix Wave** | audit/gap-board | GAP_BOARD.md | FIX WAVE CLOSED — 2026-06-11; 13 rows closed with proof in board |

---

## Connect Redesign — Overlap Binding (Spiritual OS Agent D)

**Overlap surface:** `AmenConnectSpaceListView` / Space detail screens

**Resolution:**
- This swarm (W1-5) provides the Connect navigation shell, 4-section layout, and glass chrome
- Spiritual OS Agent D provides `AmenSpacesHeroCardSection` mounted _inside_ individual Space detail views
- **Contract:** Space detail navigation shell is provided by this swarm; hero card content is provided by Agent D
- **No rival layouts:** this swarm never touches `SpiritualOS/SpacesDashboard/` files
- Agent D never touches `AmenConnectV2View.swift`, `ConnectV2SectionBar`, or `ConnectSmartBereanBar`

**Frozen contracts shared between swarms:**
- `ConnectWave0UIContracts.swift` — ConnectChromeMetrics, ConnectStrings, ConnectEmptyStateView
- `ConnectSpacesPhase0Contracts.swift` — immutable, Agent D reads only

---

## INACTIVE / CLOSED
*(none)*

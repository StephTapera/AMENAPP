# AMEN Liquid Glass Kit

The reusable Liquid Glass components live in:

`AMENAPP/AMENAPP/AMENAPP/LiquidGlass/`

## Components

- `LiquidGlassMaterial.swift`: shared `.liquidGlass()`, `.amenSpring`, and
  `.amenSnappy`.
- `MorphingGlassBar.swift`: Select -> options -> Done action bar.
- `ContextualActionMenu.swift`: preview, optional prompt, and stacked actions.
- `FeaturedHeroCarousel.swift`: paged hero with horizontal continue row.
- `LiquidGlassDemo.swift`: DEBUG-only preview harness.

## Agent Workflow

Agent instructions live in `.claude/agents/`:

- `pattern-scout.md`: read-only placement map.
- `glass-component-builder.md`: implements one selected placement.
- `motion-consistency-auditor.md`: read-only drift audit.

## Placement Starting Points

- `ContextualActionMenu`: Berean answer actions, media/post long-press actions.
- `MorphingGlassBar`: gallery multi-select, Church Notes block editing,
  floating compose affordances.
- `FeaturedHeroCarousel`: Home/feed top, ARISE/OUTPOUR discovery, Daily Verse
  hero candidates.
- Pattern language: replace ad-hoc glass and unnamed motion with
  `.liquidGlass()`, `.amenSpring`, and `.amenSnappy`.

## Notes

- Do not add a duplicate `Color` extension for AMEN colors. Use the existing
  `Color.amen...` and `AmenTheme.Colors` tokens.
- Keep production integrations scoped to one target call site at a time.
- Prefer real model adapters and thin handlers that call existing business
  logic.

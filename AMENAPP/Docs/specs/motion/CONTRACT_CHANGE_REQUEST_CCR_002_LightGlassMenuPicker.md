# CONTRACT_CHANGE_REQUEST - CCR-002: Light Glass Appearance + Menu / Sheet / Picker Patterns

Touches Module 13 section 1 appearance, section 6.4 component contracts, lanes M-A/M-B/M-C, and Module 14 section 7.2 components and section 10 surfaces. Reason: lock a white/light-first Liquid Glass appearance across the app, and add four glass menu/sheet/picker patterns demonstrated by reference apps: Mail, ChatGPT, and Slack.

Contracts are frozen. This document proposes the changes; human re-freezes, then lanes resume.

## 0. Reference To Pattern To Placement

| Reference | Pattern | New / existing primitive | AMEN surface | Plugs into |
|---|---|---|---|---|
| Mail attach popover | Floating action/attach menu | `LiquidGlassMenu` new in Module 13 -> `BereanComposerMenu` new in Module 14 | Composer `+` / `@` picker, all composer surfaces | Existing `@` invocation picker + plugin/capability registry; Scan -> Berean Lens on-device OCR |
| ChatGPT Thinking sheet | Agent activity + source-provenance sheet | `LiquidGlassSheet` existing -> `BereanAgentActivitySheet` new in Module 14 | Berean Agent surface | Five modes via `BereanModeRouter`; honest retrieval provenance |
| Slack Add People | Multi-select list picker | `LiquidGlassListPicker` new in Module 13 | Add-to-Space / group picker | Connect & Spaces S1-S8; flag and build in the Spaces spec, not here |
| Slack conversation menu | Sectioned overflow menu + tabs | `LiquidGlassMenu` + `LiquidGlassNavBar` composed | Conversation / Space overflow; inbox tabs | Glass inbox routing: `ONENavigationShell` vs `MessagesView`, human-gated |

## 1. Change A - Light Glass Appearance

AMEN / Berean Liquid Glass is light-first. The base appearance shown in every reference is white / ivory surface, charcoal-to-black text, hairline white stroke, soft low-opacity shadow, large radius, and thin frost.

- LG1 - Base material is light. Default glass uses the thin/ultra-thin light frost, not a dark or heavily tinted material. Resolve the exact material against the Xcode 27 SDK; intent governs.
- LG2 - Composition rule. Glass chrome floats over controlled light app surfaces, `bereanSurface`, never over uncontrolled or dark media. This is why it reads white in the references and is what keeps it MA3-compliant. Menus, sheets, and pickers own their backdrop; they do not blur arbitrary content behind dark text.
- LG3 - Still composes with the system slider. `MotionEnvironment.glassIntensity = min(systemPreference, appSlider)` is unchanged. The slider modulates within the light family; the app never amplifies above the system choice and never flips to a dark base to satisfy it.
- LG4 - Reduced transparency. `accessibilityReduceTransparency` or system-off maps to solid `bereanSurface` light fill plus stroke under Module 13 MA2. Not less blur.
- LG5 - Contrast. Dark text and controls on light glass meet WCAG AA in this default and across `amenTan` / `amenWineRed` accents under Module 13 MA3. This directive reinforces MA3 and is not an exception.
- LG6 - Dark mode is human-gated. Light-first design may mean dark mode remains supported, or it may mean light-only. Default of this CCR: light is the design language and default appearance; dark mode support is a keep/drop decision in section 6 decision 1. Do not silently remove dark mode.

Lane M-A's material/intensity engine implements LG1-LG5 after re-freeze. Preview gallery adds a light default column alongside the transparency spectrum.

## 2. Change B - New Shared Primitives

Add to the frozen Module 13 component contract list after human re-freeze. Both primitives compose existing glass, read `MotionEnvironment`, ship Reduce Motion and reduced-transparency fallbacks, and expose accessibility label/hint parameters.

### LiquidGlassMenu

Lane M-B, Containers.

The floating action menu. Mail attach popover and Slack overflow menu use the same primitive.

Required behavior:

- Rows support leading icon + label, optional trailing detail or chevron, and optional section dividers.
- Slack-style menu is one `LiquidGlassMenu` with Add/Move/Search as a top action row, plus Messages/Files/Canvas and Members/Notifications/Settings as sections.
- Source-anchored morph via `glassEffectID` from the control that opened it; close is the inverse under MA5.
- Item-count agnostic; scrolls if tall.
- Dismisses on tap-outside, scroll, or selection.
- Every row has a working handler. No dead rows.

### LiquidGlassListPicker

Lane M-C, Controls.

The multi-select list picker for Slack Add People style flows.

Required behavior:

- Selected items render as a chip row header.
- Each list row includes leading avatar/icon, title, subtitle, and trailing checkbox.
- Optional cap with footnote, for example "up to N including you", enforced at the seam.
- Optional confirm action, `Next`, in the nav bar.
- Selection state is the source of truth. No orphan checkboxes.

The Slack conversation screen's tabbed sheet, Messages/Files/Canvas, is `LiquidGlassMenu` plus `LiquidGlassNavBar` composed. It is not a new primitive.

## 3. Change C - New Berean Surfaces

### BereanComposerMenu

Built on `LiquidGlassMenu`.

The `+` / `@` attach-and-capability picker across all Berean composer surfaces: Notes, Ask bar, Listening Add Scripture, and prayer entry.

Required behavior:

- Rows map to the existing `@` invocation picker plus plugin/capability registry. Do not invent a new registry.
- Berean row set: Add Scripture, Attach Note, Scan Text for physical Bible / bulletin, Photo, and `@` capabilities.
- Scan and Photo are UGC and image-bearing. Route through the existing Berean Lens on-device path with no image bytes, face geometry, or embeddings leaving device.
- Guard before any save or share under Module 14 BR4.
- No new Cloud Function. Bind to the existing OCR/Lens path; flag if missing.

### BereanAgentActivitySheet

Built on `LiquidGlassSheet` / `LiquidGlassMenu`.

The honest agent-status surface, based on the ChatGPT Thinking sheet pattern but constrained to real state and retrieval provenance.

Required behavior:

- Shows the active mode and real step, for example Searching Scripture, Checking cross-references, Reflecting, Done, sourced from `BereanModeRouter` state.
- Renders a provenance line: `Berean is using: Scripture · your notes · church/group context`, listing the actual retrieval sources for this call.
- No fabricated theater. If a step did not happen, it is not shown.
- Cited output still applies under BR2; the sheet links to the references it used.

## 4. Boundary - Social Patterns Are Spaces, Not Berean

`LiquidGlassListPicker` and the conversation `LiquidGlassMenu` are shared primitives delivered by Module 13. Their application, including add-to-Space, group cap, conversation overflow, and inbox tab routing, belongs to the Connect & Spaces spec and inherits Safety Invariants S1-S8, not Module 14.

The add-people picker is a social/UGC surface. Selection routes through the Spaces safety gate, and any minor-reachable path inherits the child-safety / COPPA posture. Build the primitives here; flag the Spaces application there.

The Slack conversation menu also surfaces the Glass inbox routing decision, `ONENavigationShell` vs `MessagesView`, which remains human-gated. The menu primitive ships regardless; which shell its Messages/Files/Canvas tabs drive is the gated call.

## 5. Acceptance Additions

Append to `MOTION_ACCEPTANCE.md` for Module 13 and `BEREAN_ACCEPTANCE.md` for Module 14 after re-freeze:

- Default glass renders light/white with dark text and passes AA in the light default across `amenTan` / `amenWineRed`, in the transparency spectrum, and, if kept, dark mode.
- No glass surface places dark text over uncontrolled or dark media; every menu/sheet/picker owns a controlled light backdrop under LG2.
- `LiquidGlassMenu` morphs from its source control and dismisses on tap-outside, scroll, or selection; zero dead rows.
- `LiquidGlassListPicker` enforces its cap and routes every selection through the owning safety gate; no orphan checkbox state.
- `BereanComposerMenu` Scan/Photo route through the existing Berean Lens on-device path plus Guard; zero new Cloud Functions.
- `BereanAgentActivitySheet` reflects only real mode calls and real retrieval provenance. No fabricated status; sources shown match what was actually queried.
- Reduced transparency collapses every new surface to solid `bereanSurface` fill.

## 6. Re-Freeze Ask - Human-Gated Decisions

1. Dark mode keep or drop. Light is now the default appearance. Confirm: keep dark mode as a supported alternate, or go light-only? This materially changes M-A and the acceptance matrix, and affects accessibility.
2. Inbox routing. `ONENavigationShell` vs `MessagesView` for the conversation menu's Messages/Files/Canvas tabs remains gated; the menu primitive ships either way.
3. Composer Scan scope. Confirm Scan Text targets physical Bible/bulletin OCR through Berean Lens only, with no image leaving device, and no new backend.
4. Provenance copy. Confirm the activity-sheet wording `Berean is using: Scripture · your notes · church/group context`, and that group/church context is only shown when the user is actually in that Space.

On approval: Module 13 adds `LiquidGlassMenu`, `LiquidGlassListPicker`, and LG1-LG5 appearance rules to frozen Wave 0. Module 14 adds `BereanComposerMenu` and `BereanAgentActivitySheet` to sections 7.2 and 9, then wires them in section 10. Lanes resume against the re-frozen contracts.

End CCR-002.

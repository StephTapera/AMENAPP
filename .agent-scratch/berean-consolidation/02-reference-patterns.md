# 02-reference-patterns.md
# Berean UI Consolidation — Reference Pattern Study (Agent B)

---

## 1. ChatGPT iOS — Element Inventory

### Empty State (0 messages)
Elements above the fold, top to bottom:
1. Status bar
2. Nav bar: back `<`, "ChatGPT" title (with model chevron), "New chat" icon
3. Center logo (OpenAI orb, ~64pt)
4. Title: "ChatGPT"
5. Suggestion chip row (horizontal scroll): 4–5 short pills ("Explain quantum…", "Write a poem…", etc.)
6. Composer input field: "Message" placeholder + microphone icon

**Above-fold count: 6 elements** (status bar, nav bar, logo, title, chip row, composer)

### 3-Message Conversation State
- Nav bar shrinks to just back + model name + new-chat icon (unchanged)
- Logo and title disappear immediately on first send
- Suggestion chips disappear on first send
- Message list occupies full screen from nav bar to composer
- Composer: always visible, always the same height
- Streaming: animated "…" dots appear as a message bubble — no separate overlay chrome

### Demand-only elements (hidden until triggered)
- Model picker: tap the nav title chevron
- Memory/persona settings: tap "..." in nav bar
- Tools (browse, DALL·E, code): tap "+" in composer
- Voice mode: tap mic icon

### Chrome evolution: empty → typing → streaming → done
- **Empty**: 6 elements, centered logo layout
- **Typing**: logo/chips gone, message list scrolled to bottom, composer focused
- **Streaming**: new message bubble appears, "…" dots inside it — no extra overlay
- **Done**: bubble complete, follow-up chips appear inside the message bubble footer

---

## 2. Claude iOS — Element Inventory

### Empty State (0 messages)
Elements above the fold:
1. Status bar
2. Nav bar: hamburger sidebar toggle, "Claude" logo/title, new-chat icon
3. Greeting: "Good morning, [Name]" (large, centered)
4. Suggestion chips row (2×2 grid or horizontal scroll): 4 chips
5. Composer input: "How can I help you?" placeholder + attachment + mic

**Above-fold count: 5 elements** (status bar, nav, greeting, chips, composer)

### 3-Message Conversation State
- Greeting disappears on first send
- Suggestion chips disappear on first send
- Message list fills screen
- Composer: persistent, same appearance
- Streaming: text appears directly in message bubble with cursor — no separate status overlay

### Demand-only elements
- Project/memory: nav sidebar (hamburger)
- Model selection: nav bar title tap or sidebar
- Artifacts: appear inline as message content
- Style/persona: none visible in main flow

### Chrome evolution
- **Empty**: greeting + chips + composer dominate
- **Typing**: greeting fades, composer active
- **Streaming**: animated cursor in bubble — no other chrome
- **Done**: bubble complete, inline suggested follow-ups appear as footnote chips

---

## 3. Shared Hierarchy Principles

| Element | ChatGPT | Claude | Principle |
|---------|---------|--------|-----------|
| Identity (name/logo) | Always visible in nav | Always visible in nav | Single, nav-level — not duplicated at hero scale in chat state |
| Mode/model | Behind nav title tap | Behind nav sidebar | **Demand-only** — not persistently visible |
| Memory state | Behind "..." menu | Behind sidebar | **Demand-only** — not persistent chrome |
| Capabilities/tools | Behind "+" in composer | Contextual | **Demand-only** — not in permanent chip row |
| Suggestions | 1 row of chips, empty state only | Grid, empty state only | Disappear on first message |
| Streaming status | Inline bubble cursor | Inline bubble cursor | No separate overlay element |
| Follow-up prompts | Bubble footnote, post-stream | Inline, post-stream | Contextual — not permanent |

**Core rule both apps share:** The empty state is an invitation to type. The conversation state is a message list. These two modes use completely different chrome — and they never overlap.

---

## 4. Berean Gap Analysis

| Dimension | ChatGPT/Claude benchmark | Current AMEN Berean | Gap |
|-----------|--------------------------|---------------------|-----|
| Empty state element count | 5–6 | 13+ | **2× over budget** |
| Identity surfaces | 1 (nav bar) | 3 (nav title + hero title + capsule) | **2 extra** |
| Mode selection locations | 1 (demand) | 3 (nav pill + bottom pills + capsule) | **2 extra** |
| Memory state locations | 1 (demand) | 2 (capsule + standalone chip) | **1 extra** |
| Suggestion presentation | 1 row chips | 1 card + 3-chip sub-row + 4 floating chips | **3 extra surfaces** |
| Streaming chrome | 0 extra elements | Unknown | TBD |
| Permanent capability chips | 0 | 4 visible floating chips | **4 extra** |
| Input bars | 1 | 3 (landing bar + capsule bar + composer bar) | **2 extra** |

---

## 5. Target Element Budget — Berean Empty State

**Ceiling: 6 elements** (matching ChatGPT)

Proposed allocation:
1. **Status bar** (system)
2. **Nav bar** — back button + "Berean" title (tappable → mode sheet) + "..." menu
3. **Hero block** — logo + "Berean" title (large). These count as 1 visual unit. Hero disappears once chat starts.
4. **Subtitle** — "Scripture, context, prayer, and wisdom for AMEN." (secondary text under hero)
5. **Suggestion chip row** — horizontal scroll, 4–5 chips. Replaces card + floating chips + sub-row.
6. **Composer input** — single line, "Ask Berean anything…" + "+" (tools) + mic

**What moves to demand-only:**
- Mode selection → tap "Berean" in nav bar opens mode sheet (already exists: Scripture Study / Prayer Companion / Deep Study)
- Memory state → appears only in capsule during active conversation, not in empty state
- Response style → stays in "..." menu
- Context chips (This Chat, Church Notes, etc.) → behind "+" in composer (join the existing Tools sheet)
- Floating capability chips → removed from empty state, surface in composer after first message

---

## 6. Interaction Choreography

### Moment-by-moment chrome evolution

**State 0 — Empty (no messages)**
- Visible: nav bar, hero block (logo + "Berean"), subtitle, suggestion chips, composer
- Hidden: capsule, mode indicator, memory chip, all context chips
- Hero and chips fade out on first send

**State 1 — Typing (user composing first message)**
- Visible: nav bar, message list (empty), composer (focused)
- Hero block: fades out (opacity animation, spring)
- Chips: disappear (slide down + fade, spring)
- Capsule: appears at top as thin status line ("Berean · [mode]")

**State 2 — Waiting / Streaming**
- Visible: nav bar, capsule (shows "Berean is reading…" or "Thinking"), message list, composer (disabled/dimmed)
- Capsule dominates top chrome — expands slightly to show status
- No separate thinking strip overlay

**State 3 — Response complete**
- Visible: nav bar, capsule (recedes to thin line), message list, composer (re-enabled)
- Follow-up chips appear inline at the bottom of the response bubble

**State 4 — User focuses a message (long-press)**
- Message action menu appears (existing pattern)
- Everything else dims
- Capsule recedes

---

## 7. Wabi Benchmark (from screenshots)

The Wabi app shows the absolute minimum: a circular logo and the name "Meet Wabi." 
This is not achievable for Berean (which needs suggestion chips and a composer), but it establishes the direction: **identity statement + entry point only**. Everything else is noise until the user initiates.

The lesson: if it doesn't help the user start their first message, it doesn't belong above the fold in empty state.

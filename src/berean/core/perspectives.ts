/**
 * perspectives.ts — Berean Phase 2A
 *
 * Multi-perspective theology helper.
 *
 * buildPerspectivePrompt() produces a system prompt that instructs Claude to
 * return labeled theological traditions — never a single verdict. The response
 * is then parsed by parsePerspectiveResponse() into typed PerspectiveView objects.
 *
 * Design:
 *  - No network calls here — this module builds prompts and parses text only.
 *  - The actual callModel call is done by the BereanCore sendMessage() function
 *    using the 'theology' domain (→ berean_perspective task on the router).
 *  - parsePerspectiveResponse() is intentionally lenient; partial parses are
 *    returned rather than throwing, so a degraded response still shows something.
 *
 * FROZEN: 2026-06-07
 * OWNER: Phase 2A Core Agent
 */

// ─────────────────────────────────────────────────────────────────────────────
// PerspectiveView — public interface (not in contracts.ts by contract freeze spec)
// ─────────────────────────────────────────────────────────────────────────────

export interface PerspectiveView {
  tradition: string;
  summary: string;
  citations: string[];
}

// ─────────────────────────────────────────────────────────────────────────────
// Supported traditions — order controls how they appear in the UI
// ─────────────────────────────────────────────────────────────────────────────

const TRADITIONS: readonly string[] = [
  'Reformed',
  'Arminian',
  'Catholic',
  'Eastern Orthodox',
  'Lutheran',
  'Anglican',
  'Baptist',
  'Pentecostal',
];

// ─────────────────────────────────────────────────────────────────────────────
// buildPerspectivePrompt
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Builds a system prompt that instructs Claude to return labeled theological
 * traditions with scripture citations for each. Explicitly forbids a single
 * authoritative verdict.
 *
 * The prompt uses a strict output format (tradition label followed by colon)
 * so that parsePerspectiveResponse() can reliably extract the sections.
 */
export function buildPerspectivePrompt(question: string): string {
  const traditionList = TRADITIONS.join(', ');

  return [
    'You are Berean, a scripture-grounded theology assistant for the AMEN faith community.',
    '',
    'Your task is to present multiple theological perspectives on a contested question.',
    'You MUST NOT issue a single authoritative verdict or declare one tradition correct.',
    'Your role is to faithfully represent each tradition\'s position with accuracy and respect.',
    '',
    `For the question below, provide a response that includes perspectives from these traditions where relevant: ${traditionList}.`,
    '',
    'FORMAT RULES (strict — the parser depends on this):',
    '- Each tradition must begin on its own line, formatted exactly as: "TraditionName: ..."',
    '- After the tradition label, write 2–4 sentences summarising that tradition\'s position.',
    '- On the next line(s), list scripture citations as: "Citations: Book Chapter:Verse, Book Chapter:Verse"',
    '- You may omit a tradition only if it genuinely has no distinct position on this question.',
    '- Do not add any preamble or closing summary that asserts one view over others.',
    '- Separate each tradition block with a blank line.',
    '',
    'EXAMPLE FORMAT:',
    'Reformed: [position summary 2-4 sentences]',
    'Citations: Romans 9:1, Ephesians 1:4',
    '',
    'Arminian: [position summary 2-4 sentences]',
    'Citations: John 3:16, 1 Timothy 2:4',
    '',
    `QUESTION: ${question}`,
  ].join('\n');
}

// ─────────────────────────────────────────────────────────────────────────────
// parsePerspectiveResponse
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Parses Claude's labeled tradition response into an array of PerspectiveView.
 *
 * Parser logic:
 *  1. Split text into non-empty lines.
 *  2. A line matching "TraditionName: ..." (any known tradition) opens a new block.
 *  3. A line matching "Citations: ..." (case-insensitive) captures the citation list.
 *  4. Any other non-empty line inside a block appends to the current summary.
 *  5. A blank line or a new tradition label closes the current block.
 *
 * Returns [] if no tradition labels are found — the caller should fall back to
 * displaying the raw text string.
 */
export function parsePerspectiveResponse(text: string): PerspectiveView[] {
  if (!text || typeof text !== 'string') return [];

  const lines = text.split('\n');
  const views: PerspectiveView[] = [];

  // Build a regex that matches any known tradition label at line start.
  // Escaped for regex safety; match is case-insensitive.
  const traditionPattern = new RegExp(
    `^(${TRADITIONS.map((t) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')}):\\s*(.*)`,
    'i',
  );

  const citationPattern = /^citations?:\s*(.+)/i;

  let current: PerspectiveView | null = null;

  function commitCurrent() {
    if (current && current.tradition && current.summary.trim()) {
      views.push({
        tradition: current.tradition,
        summary: current.summary.trim(),
        citations: current.citations,
      });
    }
    current = null;
  }

  for (const rawLine of lines) {
    const line = rawLine.trim();

    const tradMatch = line.match(traditionPattern);
    if (tradMatch) {
      // New tradition block starts — commit any existing block
      commitCurrent();
      const tradName = TRADITIONS.find(
        (t) => t.toLowerCase() === tradMatch[1].toLowerCase(),
      ) ?? tradMatch[1];
      current = {
        tradition: tradName,
        summary: tradMatch[2] ? tradMatch[2] + ' ' : '',
        citations: [],
      };
      continue;
    }

    if (!current) continue;

    const citMatch = line.match(citationPattern);
    if (citMatch) {
      // Parse the comma-separated citation list
      const rawCitations = citMatch[1]
        .split(',')
        .map((c) => c.trim())
        .filter(Boolean);
      current.citations.push(...rawCitations);
      continue;
    }

    // Non-empty line inside a block: append to summary
    if (line) {
      current.summary += line + ' ';
    }
  }

  // Commit the last block
  commitCurrent();

  return views;
}

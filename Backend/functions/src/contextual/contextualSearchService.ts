import type { BereanContextPayload } from "./bereanSelectionActions";

export function deriveContextualSearchHints(payload: BereanContextPayload): string[] {
  const hints = new Set<string>();
  if (payload.scriptureReference) {
    hints.add(payload.scriptureReference);
  }
  payload.selectedText
    .split(/\s+/)
    .filter((word) => word.length > 5)
    .slice(0, 8)
    .forEach((word) => hints.add(word.toLowerCase().replace(/[^a-z0-9:-]/g, "")));
  return Array.from(hints).filter(Boolean).slice(0, 8);
}

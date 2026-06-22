import type { ContextAction, BereanContextPayload } from "./bereanSelectionActions";

export function buildContextualSuggestions(
  action: ContextAction,
  payload: BereanContextPayload
): string[] {
  const suggestions: string[] = [];

  if (payload.contentType === "scripture") {
    suggestions.push("Compare nearby cross references");
    suggestions.push("Save a private reflection");
  }

  if (action === "prayAboutThis" || action === "turnIntoPrayer") {
    suggestions.push("Save as a prayer");
  }

  if (action === "createStudy" || action === "turnIntoSermonOutline") {
    suggestions.push("Open full study workspace");
  }

  if (payload.sourceSurface.includes("message")) {
    suggestions.push("Draft a careful reply");
  }

  return suggestions.slice(0, 4);
}

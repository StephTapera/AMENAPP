import type { BereanContextPayload } from "./bereanSelectionActions";

export function shouldCreateTimelineCompression(payload: BereanContextPayload): boolean {
  return payload.contentType === "transcript" || payload.contentType === "media";
}

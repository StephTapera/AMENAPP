import { onCall } from "firebase-functions/v2/https";
import type { ReasoningRequestDTO, ReasoningResultDTO } from "./contracts";

// region MUST be us-east1. Reject any payload that includes image bytes (defense in depth).
export const bereanVisionReason = onCall(
  { region: "us-east1" },
  async (req): Promise<ReasoningResultDTO> => {
    // Defense in depth: this endpoint accepts DERIVED data only.
    // Any image bytes in the payload are a contract violation -> reject before any work.
    const data: unknown = req.data;
    if (containsImageBytes(data)) {
      throw new Error("MEDIA_GATE_VIOLATION: image bytes are not permitted; derived data only");
    }
    const _request = data as ReasoningRequestDTO; // typed once cleared of image bytes
    void _request;
    throw new Error("WAVE0_STUB: not implemented until contracts frozen");
  }
);

/**
 * Scans a payload for any field that could carry raw image bytes
 * (base64 blobs, data URIs, typed arrays, Buffers, or forbidden image keys).
 * Fail-closed: if shape is unexpected we still only allow the derived DTO contract.
 */
function containsImageBytes(value: unknown): boolean {
  const forbiddenKeys = new Set([
    "image", "imageData", "frame", "pixelBuffer", "bytes",
    "data:image", "jpeg", "png", "base64Image", "stillImage", "boundingBox",
  ]);
  const seen = new Set<unknown>();

  function walk(node: unknown): boolean {
    if (node == null) return false;
    if (typeof node === "string") {
      return node.startsWith("data:image") ||
             /^[A-Za-z0-9+/]{512,}={0,2}$/.test(node); // long base64-looking blob
    }
    if (ArrayBuffer.isView(node) || node instanceof ArrayBuffer) return true;
    if (typeof node !== "object") return false;
    if (seen.has(node)) return false;
    seen.add(node);
    for (const [key, child] of Object.entries(node as Record<string, unknown>)) {
      if (forbiddenKeys.has(key)) return true;
      if (walk(child)) return true;
    }
    return false;
  }

  return walk(value);
}

const fs = require("fs");
const path = require("path");

describe("churchNotesMediaPipeline callable guards", () => {
  const filePath = path.join(__dirname, "..", "churchNotesMediaPipeline.js");
  const source = fs.readFileSync(filePath, "utf8");

  test.each([
    [
      "processChurchNoteImageOCR",
      "{region: REGION, timeoutSeconds: 120, enforceAppCheck: true}",
      "church_notes_image_ocr_process",
    ],
    [
      "processChurchNoteVideo",
      "{region: REGION, timeoutSeconds: 540, memory: \"512MiB\", enforceAppCheck: true}",
      "church_notes_video_process",
    ],
    [
      "processChurchNoteDocumentPDF",
      "{region: REGION, timeoutSeconds: 300, enforceAppCheck: true}",
      "church_notes_pdf_ocr_process",
    ],
  ])("%s has auth, App Check, and rate limiting", (exportName, callableOptions, rateLimitKey) => {
    const exportIndex = source.indexOf(`exports.${exportName} = onCall(`);
    expect(exportIndex).toBeGreaterThanOrEqual(0);

    const nextExportIndex = source.indexOf("\nexports.", exportIndex + 1);
    const block = source.slice(exportIndex, nextExportIndex === -1 ? source.length : nextExportIndex);

    expect(block).toContain(callableOptions);
    expect(block).toContain("requireAuthAndJobOwnership(request, noteId, jobId)");
    expect(block).toContain(`enforceRateLimit(request.auth.uid, "${rateLimitKey}"`);
  });
});

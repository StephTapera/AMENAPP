const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

/** Strip tags and characters that could execute script or leak content across origins. */
function sanitizeHtml(str = "") {
  return String(str)
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<iframe[\s\S]*?>/gi, "")
    .replace(/on\w+\s*=/gi, "")
    .replace(/javascript:/gi, "");
}

/** Escape text used in HTML attributes/title elements. */
function escapeAttr(str = "") {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

exports.exportToPDF = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = request.auth.uid;

  const rawContent = request.data.content ?? "";
  const rawTitle = request.data.title ?? "AMEN Studio Export";
  if (!rawContent) throw new HttpsError("invalid-argument", "Content is required");

  const safeTitle = escapeAttr(rawTitle.slice(0, 200));
  const safeContent = sanitizeHtml(rawContent);

  // Puppeteer runs heavy — placeholder returns HTML download for now.
  // Full Puppeteer pipeline goes in Cloud Run (Phase 5).
  const html = `<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8"/>
    <title>${safeTitle}</title>
    <style>
      body { font-family: Georgia, serif; max-width: 680px;
             margin: 60px auto; line-height: 1.8; color: #1a1a1a; }
      h1   { font-size: 28px; margin-bottom: 8px; }
      p    { margin: 16px 0; }
    </style>
  </head>
  <body>
    <h1>${safeTitle}</h1>
    ${safeContent}
  </body>
</html>`;

  const bucket = admin.storage().bucket();
  // Scoped to uid so users cannot overwrite each other's exports.
  const fileName = `studio/exports/${uid}/${Date.now()}.html`;
  const file = bucket.file(fileName);
  await file.save(html, { contentType: "text/html" });
  await file.makePublic();

  return { url: `https://storage.googleapis.com/${bucket.name}/${fileName}` };
});

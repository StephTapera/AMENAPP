const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

exports.exportToPDF = onCall(async (request) => {
  const { content, title = "AMEN Studio Export" } = request.data;
  if (!content) throw new Error("Content is required");

  // Puppeteer runs heavy — placeholder returns HTML download for now
  // Full Puppeteer pipeline goes in Cloud Run (Phase 5)
  const html = `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8"/>
        <title>${title}</title>
        <style>
          body { font-family: Georgia, serif; max-width: 680px; 
                 margin: 60px auto; line-height: 1.8; color: #1a1a1a; }
          h1   { font-size: 28px; margin-bottom: 8px; }
          p    { margin: 16px 0; }
        </style>
      </head>
      <body>
        <h1>${title}</h1>
        ${content}
      </body>
    </html>`;

  const bucket = admin.storage().bucket();
  const fileName = `studio/exports/${Date.now()}.html`;
  const file = bucket.file(fileName);
  await file.save(html, { contentType: "text/html" });
  await file.makePublic();

  return { url: `https://storage.googleapis.com/${bucket.name}/${fileName}` };
});

import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";

/**
 * HTTP function serving the public web page for a post.
 * Routed via Firebase Hosting rewrite: GET /post/** → this function.
 *
 * Returns:
 * - 200 HTML with full OG meta tags for link previews (iMessage, Slack, WhatsApp, Twitter)
 * - Auto-redirects to the app after 1.5s, falls back to App Store after 3s
 * - Cache-Control: public, max-age=300 (5-min freshness)
 */
export const getPostPreview = onRequest(
    {
        region: "us-central1",
        timeoutSeconds: 15,
        memory: "256MiB",
    },
    async (req, res) => {
        // Extract postId from path: /post/{postId} or /post/{postId}/og.png (handled separately)
        const pathParts = req.path.replace(/^\/post\//, "").split("/");
        const postId = pathParts[0];

        if (!postId || postId === "og.png") {
            res.redirect(302, "https://amen.app");
            return;
        }

        res.setHeader("Cache-Control", "public, max-age=300");
        res.setHeader("Content-Type", "text/html; charset=utf-8");

        const html = await buildPostHTML(postId);
        res.status(200).send(html);
    }
);

// MARK: - HTML builder

async function buildPostHTML(postId: string): Promise<string> {
    let authorName = "AMEN";
    let description = "A moment of faith on AMEN";
    let found = true;

    try {
        const snap = await admin.firestore().collection("posts").doc(postId).get();
        if (!snap.exists) {
            found = false;
        } else {
            const data = snap.data()!;
            const visibility = data.visibility ?? "everyone";
            if (visibility !== "everyone") {
                found = false;
            } else {
                authorName = data.authorName ?? "AMEN";
                const content: string = data.content ?? "";
                description = content.slice(0, 200) + (content.length > 200 ? "…" : "");
            }
        }
    } catch {
        found = false;
    }

    if (!found) {
        return genericLandingHTML();
    }

    const pageTitle = `${authorName} on AMEN`;
    const ogImage = `https://amen.app/post/${postId}/og.png`;
    const pageURL = `https://amen.app/post/${postId}`;
    const appStoreURL = "https://apps.apple.com/app/id6740238684";
    const deepLink = `amen://post/${postId}`;

    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escHtml(pageTitle)}</title>

<!-- Open Graph -->
<meta property="og:title" content="${escHtml(pageTitle)}">
<meta property="og:description" content="${escHtml(description)}">
<meta property="og:image" content="${escHtml(ogImage)}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:url" content="${escHtml(pageURL)}">
<meta property="og:type" content="article">
<meta property="og:site_name" content="AMEN">

<!-- Twitter Card -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${escHtml(pageTitle)}">
<meta name="twitter:description" content="${escHtml(description)}">
<meta name="twitter:image" content="${escHtml(ogImage)}">

<!-- App Smart Banner -->
<meta name="apple-itunes-app" content="app-id=1234567890, app-argument=${escHtml(deepLink)}">

<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    background: #0d0d12;
    color: #ffffff;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
    text-align: center;
    padding: 24px;
  }
  .logo {
    font-size: 48px;
    font-weight: 900;
    letter-spacing: 10px;
    color: #d4b038;
    margin-bottom: 24px;
  }
  .title {
    font-size: 22px;
    font-weight: 700;
    margin-bottom: 12px;
    max-width: 480px;
  }
  .desc {
    font-size: 16px;
    color: rgba(255,255,255,0.6);
    max-width: 480px;
    line-height: 1.6;
    margin-bottom: 40px;
  }
  .cta {
    display: inline-block;
    background: #d4b038;
    color: #0d0d12;
    font-weight: 700;
    font-size: 16px;
    padding: 14px 32px;
    border-radius: 50px;
    text-decoration: none;
    margin-bottom: 16px;
  }
  .store {
    font-size: 14px;
    color: rgba(255,255,255,0.4);
  }
  .store a { color: #d4b038; text-decoration: none; }
</style>
</head>
<body>
<div class="logo">AMEN</div>
<p class="title">${escHtml(pageTitle)}</p>
<p class="desc">${escHtml(description)}</p>
<a class="cta" href="${escHtml(deepLink)}" id="openApp">Open in AMEN</a>
<p class="store">Don't have AMEN? <a href="${escHtml(appStoreURL)}" id="store">Get it free</a></p>

<script>
(function() {
  // Attempt deep link after 50ms (gives the page time to render)
  var opened = false;
  var deepLink = '${deepLink.replace(/'/g, "\\'")}';
  var storeURL = '${appStoreURL.replace(/'/g, "\\'")}';

  setTimeout(function() {
    window.location.href = deepLink;
    opened = true;
  }, 1500);

  // Fall back to App Store after 3s if app didn't open
  setTimeout(function() {
    if (document.hidden) return; // user switched apps — it worked
    window.location.href = storeURL;
  }, 3000);
})();
</script>
</body>
</html>`;
}

// MARK: - Fallback page

function genericLandingHTML(): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AMEN — Faith-based social</title>
<meta property="og:title" content="AMEN — Faith-based social">
<meta property="og:description" content="Join the conversation on AMEN, the faith-first social platform.">
<meta property="og:type" content="website">
<style>
  body { font-family: -apple-system, sans-serif; background: #0d0d12; color: #fff;
         display: flex; align-items: center; justify-content: center; min-height: 100vh;
         text-align: center; padding: 24px; }
  .logo { font-size: 48px; font-weight: 900; letter-spacing: 10px; color: #d4b038; }
</style>
</head>
<body><div class="logo">AMEN</div></body>
</html>`;
}

// MARK: - Utility

function escHtml(str: string): string {
    return str
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

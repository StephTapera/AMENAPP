/**
 * studioImageGeneration.js
 * Cloud Function: generateStudioImage
 *
 * Callable from AMEN Studio (Scripture Canvas, Vision Board tools).
 * Sends a prompt + style to the Ideogram v2 API, downloads the result,
 * saves it to Firebase Storage under studioImages/{uid}/{timestamp}.jpg,
 * and returns the public download URL.
 *
 * Secret required: IDEOGRAM_API_KEY
 * Set via: firebase functions:secrets:set IDEOGRAM_API_KEY
 */

"use strict";

const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { logger } = require("firebase-functions");
const { checkRateLimit } = require("./rateLimiter");

const ideogramKey = defineSecret("IDEOGRAM_API_KEY");

// Ideogram style presets mapped to app-facing style names
const STYLE_MAP = {
  painterly:    "DESIGN",
  realistic:    "REALISTIC",
  illustration: "ILLUSTRATION",
  anime:        "DESIGN",
  watercolor:   "ILLUSTRATION",
  sketch:       "DESIGN",
  auto:         "AUTO",
};

exports.generateStudioImage = onCall(
  {
    secrets: [ideogramKey],
    enforceAppCheck: true,
    timeoutSeconds: 120,
    memory: "512MiB",
    region: "us-central1",
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    // 10 image generations per hour
    await checkRateLimit(uid, "studio_image_gen", 10, 3600);

    const { prompt, style = "auto", aspectRatio = "ASPECT_1_1" } = request.data;
    if (!prompt || typeof prompt !== "string" || prompt.trim().length < 3) {
      throw new HttpsError("invalid-argument", "prompt is required.");
    }

    const ideogramStyle = STYLE_MAP[style] ?? "AUTO";
    const safePrompt = prompt.trim().slice(0, 500);

    // Call Ideogram v2 API (Node 22 native fetch)
    const ideogramResponse = await fetch("https://api.ideogram.ai/generate", {
      method: "POST",
      headers: {
        "Api-Key": ideogramKey.value(),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        image_request: {
          prompt: safePrompt,
          aspect_ratio: aspectRatio,
          model: "V_2",
          magic_prompt_option: "AUTO",
          style_type: ideogramStyle,
        },
      }),
    });

    if (!ideogramResponse.ok) {
      const errText = await ideogramResponse.text();
      logger.error("[generateStudioImage] Ideogram API error:", errText);
      throw new HttpsError("internal", "Image generation failed. Please try again.");
    }

    const ideogramJson = await ideogramResponse.json();
    const imageURL = ideogramJson?.data?.[0]?.url;
    if (!imageURL) {
      logger.error("[generateStudioImage] No image URL in response:", ideogramJson);
      throw new HttpsError("internal", "Image generation returned no result.");
    }

    // Download the image (native fetch → arrayBuffer)
    const imageResponse = await fetch(imageURL);
    if (!imageResponse.ok) {
      throw new HttpsError("internal", "Failed to download generated image.");
    }
    const imageBuffer = Buffer.from(await imageResponse.arrayBuffer());

    // Upload to Firebase Storage under user's scoped path
    const timestamp = Date.now();
    const storagePath = `studioImages/${uid}/${timestamp}.jpg`;
    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);

    await file.save(imageBuffer, {
      metadata: {
        contentType: "image/jpeg",
        metadata: { uid, style: ideogramStyle },
      },
    });

    await file.makePublic();
    const downloadURL = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;

    // Log creation event (no prompt content — privacy)
    await admin.firestore().collection("studioImageCreations").add({
      uid,
      style: ideogramStyle,
      aspectRatio,
      storagePath,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { downloadURL, storagePath };
  }
);

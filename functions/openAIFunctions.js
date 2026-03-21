const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");
const FormData = require("form-data");

const openAIKey = defineSecret("OPENAI_API_KEY");

exports.openAIProxy = onCall({ secrets: [openAIKey], enforceAppCheck: false }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Authentication required.");
  const uid = request.auth.uid;
  const hourKey = new Date().toISOString().slice(0, 13);
  const usageRef = admin.firestore().doc(`users/${uid}/openAIUsage/${hourKey}`);
  const snap = await usageRef.get();
  const count = snap.exists ? snap.data().count : 0;
  if (count >= 20) throw new HttpsError("resource-exhausted", "AI usage limit reached.");
  await usageRef.set({ count: count + 1 }, { merge: true });
  const { model, messages, maxTokens, temperature, systemPrompt } = request.data;
  if (!messages || !Array.isArray(messages)) throw new HttpsError("invalid-argument", "messages array required.");
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${openAIKey.value()}` },
    body: JSON.stringify({ model: model ?? "gpt-4o", max_tokens: maxTokens ?? 2000, temperature: temperature ?? 0.7, messages: systemPrompt ? [{ role: "system", content: systemPrompt }, ...messages] : messages }),
  });
  const json = await response.json();
  if (!response.ok) { logger.error("[openAIProxy]", json.error?.message); throw new HttpsError("internal", json.error?.message ?? "OpenAI error"); }
  return { text: json.choices?.[0]?.message?.content ?? "", usage: json.usage ?? null };
});

exports.whisperProxy = onCall({ secrets: [openAIKey], enforceAppCheck: false, timeoutSeconds: 120, memory: "512MiB" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Authentication required.");
  const uid = request.auth.uid;
  const hourKey = new Date().toISOString().slice(0, 13);
  const usageRef = admin.firestore().doc(`users/${uid}/whisperUsage/${hourKey}`);
  const snap = await usageRef.get();
  const count = snap.exists ? snap.data().count : 0;
  if (count >= 10) throw new HttpsError("resource-exhausted", "Transcription limit reached.");
  await usageRef.set({ count: count + 1 }, { merge: true });
  const { audioBase64, language, mimeType } = request.data;
  if (!audioBase64) throw new HttpsError("invalid-argument", "audioBase64 required.");
  const audioBuffer = Buffer.from(audioBase64, "base64");
  const form = new FormData();
  form.append("file", audioBuffer, { filename: "audio.wav", contentType: mimeType ?? "audio/wav" });
  form.append("model", "whisper-1");
  form.append("response_format", "verbose_json");
  if (language) form.append("language", language);
  form.append("prompt", "Scripture, prayer, testimony, business, stewardship, kingdom, biblical worldview.");
  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { "Authorization": `Bearer ${openAIKey.value()}`, ...form.getHeaders() },
    body: form,
  });
  const json = await response.json();
  if (!response.ok) { logger.error("[whisperProxy]", json.error?.message); throw new HttpsError("internal", json.error?.message ?? "Whisper error"); }
  const segments = json.segments ?? [];
  const logprobs = segments.map((s) => s.avg_logprob).filter((v) => typeof v === "number");
  const avgLogprob = logprobs.length > 0 ? logprobs.reduce((a, b) => a + b, 0) / logprobs.length : -0.5;
  return { text: json.text ?? "", confidence: Math.max(0, Math.min(1, 1.0 + avgLogprob)), language: json.language ?? (language ?? "en") };
});

// transcribeAudio — client uploads audio to Storage, function downloads and transcribes via Whisper
exports.transcribeAudio = onCall({ secrets: [openAIKey], enforceAppCheck: false, timeoutSeconds: 120, memory: "512MiB" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Authentication required.");
  const uid = request.auth.uid;

  // Rate-limit: share whisperUsage counter with whisperProxy (10/hour total)
  const hourKey = new Date().toISOString().slice(0, 13);
  const usageRef = admin.firestore().doc(`users/${uid}/whisperUsage/${hourKey}`);
  const snap = await usageRef.get();
  const count = snap.exists ? snap.data().count : 0;
  if (count >= 10) throw new HttpsError("resource-exhausted", "Transcription limit reached.");
  await usageRef.set({ count: count + 1 }, { merge: true });

  const { storagePath } = request.data;
  if (!storagePath) throw new HttpsError("invalid-argument", "storagePath required.");

  // Validate the path belongs to the calling user
  if (!storagePath.startsWith(`studioVoice/${uid}/`)) {
    throw new HttpsError("permission-denied", "Cannot access this audio file.");
  }

  // Download from Firebase Storage
  const bucket = admin.storage().bucket();
  const file = bucket.file(storagePath);
  const [fileBuffer] = await file.download();
  const [metadata] = await file.getMetadata();
  const contentType = metadata.contentType || "audio/m4a";

  // Send to Whisper
  const form = new FormData();
  form.append("file", fileBuffer, { filename: "audio.m4a", contentType });
  form.append("model", "whisper-1");
  form.append("response_format", "verbose_json");
  form.append("prompt", "Scripture, prayer, testimony, faith, God, biblical worldview.");

  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { "Authorization": `Bearer ${openAIKey.value()}`, ...form.getHeaders() },
    body: form,
  });
  const json = await response.json();
  if (!response.ok) {
    logger.error("[transcribeAudio]", json.error?.message);
    throw new HttpsError("internal", json.error?.message ?? "Whisper error");
  }

  // Delete the temp audio file from Storage after transcription
  try { await file.delete(); } catch (_) {}

  const segments = json.segments ?? [];
  const logprobs = segments.map((s) => s.avg_logprob).filter((v) => typeof v === "number");
  const avgLogprob = logprobs.length > 0 ? logprobs.reduce((a, b) => a + b, 0) / logprobs.length : -0.5;

  return { text: json.text ?? "", confidence: Math.max(0, Math.min(1, 1.0 + avgLogprob)) };
});

exports.smartSuggestionsProxy = onCall({ secrets: [openAIKey], enforceAppCheck: false }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Authentication required.");
  const { prompt, maxTokens } = request.data;
  if (!prompt) throw new HttpsError("invalid-argument", "prompt required.");
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${openAIKey.value()}` },
    body: JSON.stringify({ model: "gpt-4o-mini", max_tokens: maxTokens ?? 20, temperature: 0.7, messages: [{ role: "system", content: "You are a concise, warm Christian community connector. Output ONLY the connection reason, nothing else." }, { role: "user", content: prompt }] }),
  });
  const json = await response.json();
  if (!response.ok) { logger.error("[smartSuggestionsProxy]", json.error?.message); throw new HttpsError("internal", json.error?.message ?? "OpenAI error"); }
  return { text: json.choices?.[0]?.message?.content ?? "" };
});

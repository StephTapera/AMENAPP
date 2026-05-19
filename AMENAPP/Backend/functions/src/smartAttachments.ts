import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {enforceRateLimit} from "./rateLimit";

const db = admin.firestore();
const appCheckedCallable = functions.runWith({enforceAppCheck: true}).https.onCall;

type AmenAttachmentProvider =
  | "appleMusic" | "spotify" | "youtube" | "instagram" | "threads" | "tikTok" | "x"
  | "facebook" | "linkedIn" | "applePodcasts" | "medium" | "substack" | "rss"
  | "bibleGateway" | "youVersion" | "eventbrite" | "generic";
type AmenAttachmentType =
  | "song" | "album" | "playlist" | "artist" | "video" | "podcast" | "article" | "genericLink"
  | "profile" | "post" | "reel" | "short" | "channel" | "episode" | "sermon" | "scripture" | "event" | "donation" | "rssFeed";
type AmenSafetyStatus = "approved" | "limited" | "blocked" | "needsReview";
type AmenIntelligenceState = "detecting" | "fetchingMetadata" | "extractingLinks" | "generatingContext" | "ready" | "partial" | "failed" | "restricted" | "unsafe";

interface ResolveRequest { url?: string; source?: string; provider?: AmenAttachmentProvider; providerId?: string; }

interface SmartAttachment {
  attachmentId: string;
  provider: AmenAttachmentProvider;
  type: AmenAttachmentType;
  providerId?: string;
  title: string;
  subtitle?: string;
  creatorName?: string;
  description?: string;
  artworkUrl?: string;
  canonicalUrl: string;
  originalUrl?: string;
  durationMs?: number;
  previewUrl?: string;
  attributionText: string;
  sourceLogoRequired: boolean;
  playbackPolicy: "externalOnly";
  safetyStatus: AmenSafetyStatus;
  intelligenceState: AmenIntelligenceState;
  transcriptStatus?: string;
  aiContextStatus?: string;
  summary?: string;
  scriptureReferences?: string[];
  extractedLinks?: Array<{id: string; url: string; title?: string; category: string}>;
  smartActions: string[];
  resolvedAt: admin.firestore.FieldValue;
}

const BLOCKED_HOSTS = new Set(["localhost", "127.0.0.1", "0.0.0.0"]);
const RESTRICTED_DOMAINS = [/instagram\.com$/i, /threads\.net$/i, /tiktok\.com$/i];
const UNSAFE_TERMS = ["phish", "scam", "malware", "extremist", "self-harm"];

function requireAuthAndAppCheck(context: functions.https.CallableContext): string {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required");
  if (context.app == undefined) throw new functions.https.HttpsError("failed-precondition", "App Check required");
  return context.auth.uid;
}

function isPrivateIPv4(host: string): boolean {
  const m = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!m) return false;
  const a = Number(m[1]); const b = Number(m[2]);
  return a === 10 || a === 127 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
}

function normalizeUrl(rawUrl: string): URL {
  let parsed: URL;
  try { parsed = new URL(rawUrl.trim()); } catch { throw new functions.https.HttpsError("invalid-argument", "Invalid URL"); }
  if (parsed.protocol !== "https:") throw new functions.https.HttpsError("invalid-argument", "Only https URLs are supported");
  const host = parsed.hostname.toLowerCase();
  if (BLOCKED_HOSTS.has(host) || isPrivateIPv4(host)) throw new functions.https.HttpsError("permission-denied", "Unsafe URL target");
  parsed.hash = "";
  if (parsed.searchParams.has("utm_source")) parsed.searchParams.delete("utm_source");
  if (parsed.searchParams.has("utm_medium")) parsed.searchParams.delete("utm_medium");
  return parsed;
}

function detectProvider(url: URL): AmenAttachmentProvider {
  const host = url.hostname.toLowerCase();
  if (host.includes("music.apple.com")) return "appleMusic";
  if (host.includes("podcasts.apple.com")) return "applePodcasts";
  if (host.includes("open.spotify.com")) return "spotify";
  if (host.includes("youtube.com") || host.includes("youtu.be")) return "youtube";
  if (host.includes("instagram.com")) return "instagram";
  if (host.includes("threads.net")) return "threads";
  if (host.includes("tiktok.com")) return "tikTok";
  if (host.includes("twitter.com") || host.includes("x.com")) return "x";
  if (host.includes("facebook.com")) return "facebook";
  if (host.includes("linkedin.com")) return "linkedIn";
  if (host.includes("medium.com")) return "medium";
  if (host.includes("substack.com")) return "substack";
  if (host.includes("biblegateway.com")) return "bibleGateway";
  if (host.includes("youversion.com")) return "youVersion";
  if (host.includes("eventbrite.")) return "eventbrite";
  return "generic";
}

function classifyType(url: URL, provider: AmenAttachmentProvider): AmenAttachmentType {
  const path = url.pathname.toLowerCase();
  if (provider === "youtube") {
    if (path.includes("/shorts/")) return "short";
    if (path.includes("/playlist")) return "playlist";
    if (path.includes("/channel") || path.startsWith("/@")) return "channel";
    return "video";
  }
  if (provider === "spotify" || provider === "applePodcasts") return path.includes("episode") ? "episode" : "podcast";
  if (provider === "instagram") return path.includes("/reel/") ? "reel" : (path.split("/").filter(Boolean).length <= 1 ? "profile" : "post");
  if (provider === "threads" || provider === "x" || provider === "facebook" || provider === "linkedIn") return "post";
  if (provider === "bibleGateway" || provider === "youVersion") return "scripture";
  if (provider === "eventbrite") return "event";
  if (provider === "rss") return "rssFeed";
  return "article";
}

function extractUrlsFromText(text: string): string[] {
  return Array.from(new Set((text.match(/https:\/\/[^\s)]+/g) ?? []).map((u) => u.trim())));
}

function makeActions(safety: AmenSafetyStatus): string[] {
  if (safety === "blocked") return ["report", "hide"];
  if (safety === "limited") return ["open", "report", "hide"];
  return ["open", "saveToSelah", "addToChurchNotes", "saveForLater", "share", "startGroupDiscussion", "report", "hide"];
}

async function fetchText(url: string): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 7000);
  try {
    const response = await fetch(url, {signal: controller.signal, redirect: "follow"});
    if (!response.ok) return "";
    return (await response.text()).slice(0, 200000);
  } catch {
    return "";
  } finally {
    clearTimeout(timeout);
  }
}

function meta(html: string, key: string): string | undefined {
  const re = new RegExp(`<meta[^>]+(?:property|name)=["']${key}["'][^>]*content=["']([^"']+)["']`, "i");
  return html.match(re)?.[1];
}

async function ingest(urlRaw: string): Promise<SmartAttachment> {
  const original = normalizeUrl(urlRaw);
  const provider = detectProvider(original);
  const type = classifyType(original, provider);
  const html = await fetchText(original.toString());
  const title = meta(html, "og:title") ?? original.hostname;
  const description = meta(html, "og:description");
  const creatorName = meta(html, "og:site_name");
  const artworkUrl = meta(html, "og:image");
  const extracted = extractUrlsFromText(description ?? "").map((url, index) => ({id: `m_${index}`, url, category: "source"}));
  const restricted = RESTRICTED_DOMAINS.some((re) => re.test(original.hostname));
  const unsafe = UNSAFE_TERMS.some((term) => `${title} ${description ?? ""}`.toLowerCase().includes(term));
  const safetyStatus: AmenSafetyStatus = unsafe ? "blocked" : (restricted ? "limited" : "approved");
  const intelligenceState: AmenIntelligenceState = unsafe ? "unsafe" : (restricted ? "restricted" : "ready");
  return {
    attachmentId: `${provider}_${Buffer.from(original.toString()).toString("base64").slice(0, 18)}`,
    provider,
    type,
    title,
    subtitle: provider,
    creatorName,
    description,
    artworkUrl,
    canonicalUrl: original.toString(),
    originalUrl: urlRaw,
    attributionText: provider === "generic" ? "Web" : provider,
    sourceLogoRequired: provider !== "generic",
    playbackPolicy: "externalOnly",
    safetyStatus,
    intelligenceState,
    transcriptStatus: "unavailable",
    aiContextStatus: safetyStatus === "approved" ? "ready" : "restricted",
    summary: description ? description.slice(0, 260) : undefined,
    scriptureReferences: (description?.match(/\b(?:[1-3]\s)?[A-Za-z]+\s\d+:\d+\b/g) ?? []).slice(0, 6),
    extractedLinks: extracted,
    smartActions: makeActions(safetyStatus),
    resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function persistUniversalLink(uid: string, attachment: SmartAttachment) {
  const ref = db.collection("universalLinks").doc(attachment.attachmentId);
  await ref.set({...attachment, updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  await db.doc(`users/${uid}/linkHistory/${attachment.attachmentId}`).set({
    linkId: attachment.attachmentId,
    canonicalUrl: attachment.canonicalUrl,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

export const resolveSmartAttachment = appCheckedCallable(async (data: ResolveRequest, context) => {
  const uid = requireAuthAndAppCheck(context);
  await enforceRateLimit(uid, [{scope: "minute", limit: 40}, {scope: "day", limit: 800}] as never);
  const attachment = await ingest(String(data.url ?? ""));
  await persistUniversalLink(uid, attachment);
  return attachment;
});

export const detectLinks = appCheckedCallable(async (data: {text?: string}, context) => {
  const uid = requireAuthAndAppCheck(context);
  await enforceRateLimit(uid, [{scope: "minute", limit: 80}] as never);
  const urls = extractUrlsFromText(String(data.text ?? ""));
  return {urls, count: urls.length};
});

export const ingestUniversalLink = appCheckedCallable(async (data: {url?: string}, context) => {
  const uid = requireAuthAndAppCheck(context);
  await enforceRateLimit(uid, [{scope: "minute", limit: 40}, {scope: "day", limit: 600}] as never);
  const attachment = await ingest(String(data.url ?? ""));
  await persistUniversalLink(uid, attachment);
  return attachment;
});

export const refreshUniversalLinkMetadata = appCheckedCallable(async (data: {linkId?: string; url?: string}, context) => {
  const uid = requireAuthAndAppCheck(context);
  await enforceRateLimit(uid, [{scope: "minute", limit: 30}] as never);
  const target = data.url ?? (data.linkId ? String((await db.doc(`universalLinks/${data.linkId}`).get()).data()?.canonicalUrl ?? "") : "");
  const attachment = await ingest(String(target));
  await persistUniversalLink(uid, attachment);
  return attachment;
});

export const extractUniversalLinks = appCheckedCallable(async (data: {url?: string; text?: string}, context) => {
  const uid = requireAuthAndAppCheck(context);
  await enforceRateLimit(uid, [{scope: "minute", limit: 50}] as never);
  const seeds = [...extractUrlsFromText(String(data.text ?? ""))];
  if (data.url) seeds.push(data.url);
  return {extractedLinks: Array.from(new Set(seeds)).map((url, i) => ({id: `e_${i}`, url, category: "source"}))};
});

export const generateUniversalLinkSummary = appCheckedCallable(async (data: {linkId?: string; url?: string}, context) => {
  const uid = requireAuthAndAppCheck(context);
  await enforceRateLimit(uid, [{scope: "minute", limit: 25}] as never);
  const attachment = await ingest(String(data.url ?? ""));
  const summary = attachment.summary ?? "Summary unavailable from allowed metadata.";
  const payload = {shortSummary: summary, keyPoints: [summary.slice(0, 120)], topics: [], contentWarnings: [], scriptureReferences: attachment.scriptureReferences ?? [], suggestedQuestions: ["What are the main points?"], noteOutline: [], safetyLabels: [attachment.safetyStatus]};
  await db.collection(`universalLinks/${attachment.attachmentId}/summaries`).add({...payload, createdBy: uid, createdAt: admin.firestore.FieldValue.serverTimestamp()});
  return payload;
});

export const generateUniversalLinkNotes = appCheckedCallable(async (data: {url?: string}, context) => {
  const uid = requireAuthAndAppCheck(context);
  await enforceRateLimit(uid, [{scope: "minute", limit: 20}] as never);
  const attachment = await ingest(String(data.url ?? ""));
  return {
    title: attachment.title,
    sourceAttribution: attachment.canonicalUrl,
    outline: [attachment.summary ?? "No summary available"],
    scriptureReferences: attachment.scriptureReferences ?? [],
    userConfirmationRequired: true,
  };
});

export const classifyUniversalLink = appCheckedCallable(async (data: {url?: string}, context) => {
  const uid = requireAuthAndAppCheck(context);
  await enforceRateLimit(uid, [{scope: "minute", limit: 60}] as never);
  const url = normalizeUrl(String(data.url ?? ""));
  const provider = detectProvider(url);
  const contentType = classifyType(url, provider);
  return {provider, contentType};
});

export const saveUniversalLink = appCheckedCallable(async (data: {linkId?: string}, context) => {
  const uid = requireAuthAndAppCheck(context);
  await enforceRateLimit(uid, [{scope: "minute", limit: 80}] as never);
  if (!data.linkId) throw new functions.https.HttpsError("invalid-argument", "linkId is required");
  await db.doc(`users/${uid}/savedLinks/${data.linkId}`).set({savedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  return {ok: true};
});

export const reportUniversalLink = appCheckedCallable(async (data: {linkId?: string; reason?: string}, context) => {
  const uid = requireAuthAndAppCheck(context);
  await enforceRateLimit(uid, [{scope: "minute", limit: 20}] as never);
  if (!data.linkId) throw new functions.https.HttpsError("invalid-argument", "linkId is required");
  await db.collection("universalLinkReports").add({
    linkId: data.linkId,
    reason: data.reason ?? "unspecified",
    reporterUid: uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return {ok: true};
});

export const __smartAttachmentInternals = {
  detectProvider,
  classifyType,
  normalizeUrl,
  extractUrlsFromText,
};

// TODO: USE_DEFINE_SECRET — migrate this secret to defineSecret() for Functions v2
const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

const SPOTIFY_TOKEN_URL = "https://accounts.spotify.com/api/token";
const SPOTIFY_API_BASE = "https://api.spotify.com/v1";
const APPLE_MUSIC_API_BASE = "https://api.music.apple.com/v1/catalog";
const DEFAULT_APPLE_STOREFRONT = "us";
const METADATA_VERSION = 2;

let spotifyTokenCache = {
  token: null,
  expiresAtMs: 0,
};

function normalizeHex(value) {
  if (!value || typeof value !== "string") return null;
  const normalized = value.replace("#", "").trim();
  return /^[0-9a-fA-F]{6}$/.test(normalized) ? `#${normalized.toUpperCase()}` : null;
}

function parseMusicAttachmentURL(rawValue) {
  const trimmed = String(rawValue || "").trim();
  if (!trimmed) {
    throw new HttpsError("invalid-argument",
        "A music URL is required.");
  }

  if (trimmed.toLowerCase().startsWith("spotify:")) {
    return parseSpotifyURI(trimmed);
  }

  let url;
  try {
    url = new URL(trimmed);
  } catch {
    throw new HttpsError("invalid-argument",
        "We couldn't read that music link.");
  }

  const host = url.hostname.toLowerCase();
  if (host === "open.spotify.com") {
    return parseSpotifyURL(url);
  }

  if (host === "music.apple.com" || host === "itunes.apple.com") {
    return parseAppleMusicURL(url);
  }

  throw new HttpsError("invalid-argument",
      "Only Apple Music and Spotify song or album links are supported.");
}

function parseSpotifyURI(value) {
  const parts = value.split(":");
  if (parts.length < 3) {
    throw new HttpsError("invalid-argument",
        "Unsupported Spotify URI.");
  }

  const resourceType = parts[1].toLowerCase();
  const providerID = parts[2];
  if (!providerID) {
    throw new HttpsError("invalid-argument",
        "Spotify link is missing a resource ID.");
  }

  const entityType = spotifyEntityType(resourceType);
  return {
    provider: "spotify",
    entityType,
    providerID,
    storefront: null,
    canonicalURL: `https://open.spotify.com/${resourceType}/${providerID}`,
  };
}

function parseSpotifyURL(url) {
  const pathSegments = url.pathname.split("/").filter(Boolean);
  if (pathSegments.length < 2) {
    throw new HttpsError("invalid-argument",
        "Spotify link is missing a resource.");
  }

  const resourceType = pathSegments[0].toLowerCase();
  const providerID = pathSegments[1];
  const entityType = spotifyEntityType(resourceType);
  return {
    provider: "spotify",
    entityType,
    providerID,
    storefront: null,
    canonicalURL: `https://open.spotify.com/${resourceType}/${providerID}`,
  };
}

function spotifyEntityType(resourceType) {
  switch (resourceType) {
  case "track":
    return "song";
  case "album":
    return "album";
  default:
    throw new HttpsError("invalid-argument",
        "Only Spotify tracks and albums are supported.");
  }
}

function parseAppleMusicURL(url) {
  const pathSegments = url.pathname.split("/").filter(Boolean);
  if (pathSegments.length < 3) {
    throw new HttpsError("invalid-argument",
        "Apple Music link is missing a resource.");
  }

  const storefront = pathSegments[0].toLowerCase();
  const resourceType = pathSegments[1].toLowerCase();
  const trailingIdentifier = pathSegments[pathSegments.length - 1];
  const songIdentifier = url.searchParams.get("i");

  let entityType = null;
  let providerID = null;
  if (songIdentifier) {
    entityType = "song";
    providerID = songIdentifier;
  } else if (resourceType === "song") {
    entityType = "song";
    providerID = trailingIdentifier;
  } else if (resourceType === "album") {
    entityType = "album";
    providerID = trailingIdentifier;
  } else {
    throw new HttpsError("invalid-argument",
        "Only Apple Music songs and albums are supported.");
  }

  const canonicalURL = new URL(url.toString());
  for (const key of [...canonicalURL.searchParams.keys()]) {
    if (key !== "i") {
      canonicalURL.searchParams.delete(key);
    }
  }
  canonicalURL.hash = "";

  return {
    provider: "appleMusic",
    entityType,
    providerID,
    storefront,
    canonicalURL: canonicalURL.toString(),
  };
}

async function fetchSpotifyAccessToken() {
  const now = Date.now();
  if (spotifyTokenCache.token && now < spotifyTokenCache.expiresAtMs) {
    return spotifyTokenCache.token;
  }

  const clientID = process.env.SPOTIFY_CLIENT_ID;
  const clientSecret = process.env.SPOTIFY_CLIENT_SECRET;
  if (!clientID || !clientSecret) {
    throw new HttpsError("failed-precondition",
        "Spotify resolver secrets are not configured.");
  }

  const credentials = Buffer.from(`${clientID}:${clientSecret}`).toString("base64");
  const response = await fetch(SPOTIFY_TOKEN_URL, {
    method: "POST",
    headers: {
      "Authorization": `Basic ${credentials}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });

  if (!response.ok) {
    throw new HttpsError("internal",
        "Spotify token lookup failed.");
  }

  const data = await response.json();
  spotifyTokenCache = {
    token: data.access_token,
    expiresAtMs: now + ((data.expires_in || 3600) - 60) * 1000,
  };
  return spotifyTokenCache.token;
}

async function resolveSpotifyAttachment(parsed) {
  const token = await fetchSpotifyAccessToken();
  const resourcePath = parsed.entityType === "album" ? "albums" : "tracks";
  const response = await fetch(`${SPOTIFY_API_BASE}/${resourcePath}/${parsed.providerID}`, {
    headers: {
      "Authorization": `Bearer ${token}`,
    },
  });

  if (!response.ok) {
    throw new HttpsError("not-found",
        "We couldn't load that Spotify item.");
  }

  const data = await response.json();
  const artwork = parsed.entityType === "album" ?
    data.images?.[0]?.url :
    data.album?.images?.[0]?.url;
  const title = data.name;
  const artistName = (data.artists || [])
      .map((artist) => artist.name)
      .filter(Boolean)
      .join(", ");

  return {
    provider: "spotify",
    entityType: parsed.entityType,
    providerID: parsed.providerID,
    storefront: null,
    canonicalURL: data.external_urls?.spotify || parsed.canonicalURL,
    appURL: `spotify:${parsed.entityType === "album" ? "album" : "track"}:${parsed.providerID}`,
    title,
    subtitle: artistName,
    artistName,
    artworkURL: artwork || null,
    artworkColors: null,
    explicit: data.explicit ?? null,
    durationMs: parsed.entityType === "song" ? data.duration_ms ?? null : null,
    requiresAccount: true,
    mayRequireSubscription: false,
    metadataVersion: METADATA_VERSION,
  };
}

function appleArtworkURL(attributes) {
  const template = attributes?.artwork?.url;
  if (!template) return null;
  return template
      .replace("{w}", "320")
      .replace("{h}", "320")
      .replace("{f}", "jpg");
}

function appleArtworkColors(attributes) {
  const bg = normalizeHex(attributes?.artwork?.bgColor);
  const secondary = normalizeHex(attributes?.artwork?.textColor2 || attributes?.artwork?.textColor1);
  if (!bg && !secondary) return null;
  return {
    dominantHex: bg,
    secondaryHex: secondary,
  };
}

async function resolveAppleMusicAttachment(parsed, requestedStorefront) {
  const developerToken = process.env.APPLE_MUSIC_DEVELOPER_TOKEN;
  if (!developerToken) {
    throw new HttpsError("failed-precondition",
        "Apple Music resolver secret is not configured.");
  }

  const storefront = (requestedStorefront || parsed.storefront || DEFAULT_APPLE_STOREFRONT).toLowerCase();
  const resourcePath = parsed.entityType === "album" ? "albums" : "songs";
  const response = await fetch(
      `${APPLE_MUSIC_API_BASE}/${storefront}/${resourcePath}/${parsed.providerID}`,
      {
        headers: {
          "Authorization": `Bearer ${developerToken}`,
        },
      },
  );

  if (!response.ok) {
    throw new HttpsError("not-found",
        "We couldn't load that Apple Music item.");
  }

  const payload = await response.json();
  const item = payload.data?.[0];
  const attributes = item?.attributes;
  if (!attributes) {
    throw new HttpsError("not-found",
        "Apple Music metadata was unavailable.");
  }

  return {
    provider: "appleMusic",
    entityType: parsed.entityType,
    providerID: parsed.providerID,
    storefront,
    canonicalURL: attributes.url || parsed.canonicalURL,
    appURL: attributes.url || parsed.canonicalURL,
    title: attributes.name || "",
    subtitle: attributes.artistName || "",
    artistName: attributes.artistName || "",
    artworkURL: appleArtworkURL(attributes),
    artworkColors: appleArtworkColors(attributes),
    explicit: attributes.contentRating === "explicit",
    durationMs: typeof attributes.durationInMillis === "number" ? attributes.durationInMillis : null,
    requiresAccount: true,
    mayRequireSubscription: true,
    metadataVersion: METADATA_VERSION,
  };
}

async function cacheResolvedAttachment(db, payload) {
  const storefrontKey = payload.storefront || "global";
  const cacheId = `${payload.provider}_${payload.providerID}_${storefrontKey}`;
  const now = new Date().toISOString();
  const document = {
    ...payload,
    attachedAt: now,
    resolvedAt: now,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  await db.collection("musicCatalogCache").doc(cacheId).set(document, {merge: true});
  return document;
}

const CACHE_MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

async function lookupCachedAttachment(db, parsed, requestedStorefront) {
  const storefrontKey = (requestedStorefront || parsed.storefront || DEFAULT_APPLE_STOREFRONT).toLowerCase();
  const cacheId = `${parsed.provider}_${parsed.providerID}_${parsed.provider === "appleMusic" ? storefrontKey : "global"}`;
  const snapshot = await db.collection("musicCatalogCache").doc(cacheId).get();
  if (!snapshot.exists) return null;
  const data = snapshot.data();
  const resolvedAt = data.resolvedAt ? new Date(data.resolvedAt).getTime() : 0;
  if (Date.now() - resolvedAt > CACHE_MAX_AGE_MS) return null;
  return data;
}

exports.resolveMusicAttachment = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true,
      // Secrets read from process.env at call time; not declared here so
      // deployment does not require them pre-provisioned in Secret Manager.
      // Add them back once SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET, and
      // APPLE_MUSIC_DEVELOPER_TOKEN are created in Secret Manager.
    },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated",
            "You must be signed in to attach music.");
      }

      const parsed = parseMusicAttachmentURL(request.data?.url);
      const requestedStorefront = String(
          request.data?.storefront || parsed.storefront || DEFAULT_APPLE_STOREFRONT,
      ).toLowerCase();
      const db = admin.firestore();

      const cached = await lookupCachedAttachment(db, parsed, requestedStorefront);
      if (cached) {
        return cached;
      }

      const resolved = parsed.provider === "spotify" ?
        await resolveSpotifyAttachment(parsed) :
        await resolveAppleMusicAttachment(parsed, requestedStorefront);

      return await cacheResolvedAttachment(db, resolved);
    },
);

exports._internal = {
  parseMusicAttachmentURL,
};

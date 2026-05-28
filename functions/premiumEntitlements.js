"use strict";

const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const db = admin.firestore();
const REGION = "us-central1";

const PRODUCT_TIERS = {
  "com.amen.plus.monthly": "plus",
  "com.amen.plus.yearly": "plus",
  "com.amen.pro.monthly": "pro",
  "com.amen.pro.yearly": "pro",
  "com.amen.pro.lifetime": "pro",
};

const TIER_RANK = {free: 0, plus: 1, pro: 2};
const LIMITS = {
  free: {aiMessagesPerDay: 10, customTopicTags: 3},
  plus: {aiMessagesPerDay: 50, customTopicTags: 15},
  pro: {aiMessagesPerDay: null, customTopicTags: null},
};

function appStoreConfig() {
  return {
    bundleId: process.env.APP_STORE_BUNDLE_ID || process.env.IOS_BUNDLE_ID || "",
    appAppleId: process.env.APP_STORE_APP_APPLE_ID || "",
    issuerId: process.env.APP_STORE_ISSUER_ID || "",
    keyId: process.env.APP_STORE_KEY_ID || "",
    privateKey: process.env.APP_STORE_PRIVATE_KEY || "",
    environment: process.env.APP_STORE_ENVIRONMENT || "Sandbox",
  };
}

function hasAppStoreServerCredentials() {
  const config = appStoreConfig();
  return Boolean(config.bundleId && config.issuerId && config.keyId && config.privateKey);
}

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }
  return request.auth.uid;
}

function normalizeTier(tier) {
  return ["free", "plus", "pro"].includes(tier) ? tier : "free";
}

function tierForProduct(productId) {
  return PRODUCT_TIERS[productId] || "free";
}

function base64UrlDecode(value) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Buffer.from(padded, "base64").toString("utf8");
}

function decodeJwsPayload(jws) {
  if (!jws || typeof jws !== "string") return null;
  const parts = jws.split(".");
  if (parts.length !== 3) return null;
  try {
    return JSON.parse(base64UrlDecode(parts[1]));
  } catch (error) {
    console.error("Failed to decode App Store JWS payload", error);
    return null;
  }
}

function isExpired(payload) {
  if (!payload) return true;
  if (payload.expiresDate == null) return false;
  const expiresMs = Number(payload.expiresDate);
  return Number.isFinite(expiresMs) && expiresMs <= Date.now();
}

function validateDecodedTransactionPayload(payload, expectedProductId) {
  if (!payload) return {ok: true, mode: "fallback_unverified_decode"};

  const config = appStoreConfig();
  if (expectedProductId && payload.productId && payload.productId !== expectedProductId) {
    throw new HttpsError("invalid-argument", "Transaction product does not match requested product");
  }
  if (config.bundleId && payload.bundleId && payload.bundleId !== config.bundleId) {
    throw new HttpsError("permission-denied", "Transaction bundle does not match this app");
  }
  if (config.environment && payload.environment && payload.environment !== config.environment) {
    console.warn(`App Store transaction environment mismatch: ${payload.environment} != ${config.environment}`);
  }

  return {
    ok: true,
    mode: hasAppStoreServerCredentials() ? "decoded_pending_crypto_verification" : "fallback_unverified_decode",
  };
}

function limitsForTier(tier) {
  return LIMITS[normalizeTier(tier)];
}

async function getUserTier(uid) {
  const snap = await db.collection("users").doc(uid).get();
  const data = snap.exists ? snap.data() : {};
  const entitlement = data.premiumEntitlement || {};
  const tier = normalizeTier(entitlement.tier || data.premiumTier);

  if (tier !== "free" && entitlement.expiresAt && entitlement.expiresAt.toMillis) {
    if (entitlement.expiresAt.toMillis() <= Date.now()) {
      return "free";
    }
  }

  return tier;
}

async function applyEntitlement(uid, tier, source, metadata = {}) {
  const normalizedTier = normalizeTier(tier);
  const entitlement = {
    tier: normalizedTier,
    source,
    limits: limitsForTier(normalizedTier),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...metadata,
  };

  await db.collection("users").doc(uid).set({
    premiumTier: normalizedTier,
    hasPlusAccess: normalizedTier === "plus" || normalizedTier === "pro",
    hasProAccess: normalizedTier === "pro",
    premiumEntitlement: entitlement,
  }, {merge: true});

  return entitlement;
}

exports.getPremiumEntitlement = onCall({region: REGION}, async (request) => {
  const uid = requireAuth(request);
  const tier = await getUserTier(uid);
  return {
    tier,
    hasPlusAccess: tier === "plus" || tier === "pro",
    hasProAccess: tier === "pro",
    limits: limitsForTier(tier),
  };
});

exports.syncPremiumEntitlement = onCall({region: REGION}, async (request) => {
  const uid = requireAuth(request);
  const {signedTransactionInfo, productId: fallbackProductId} = request.data || {};
  const payload = decodeJwsPayload(signedTransactionInfo);
  const productId = payload?.productId || fallbackProductId;
  const validation = validateDecodedTransactionPayload(payload, fallbackProductId);
  const tier = tierForProduct(productId);

  if (tier === "free") {
    throw new HttpsError("invalid-argument", "Unknown premium product");
  }
  if (payload && isExpired(payload)) {
    await applyEntitlement(uid, "free", "app_store_expired", {
      lastProductId: productId,
      originalTransactionId: payload.originalTransactionId || null,
    });
    return {tier: "free", hasPlusAccess: false, hasProAccess: false, limits: limitsForTier("free")};
  }

  const metadata = {
    productId,
    originalTransactionId: payload?.originalTransactionId || null,
    transactionId: payload?.transactionId || null,
    environment: payload?.environment || null,
    verificationMode: validation.mode,
    signedAt: payload?.signedDate ? new Date(Number(payload.signedDate)) : null,
  };

  if (payload?.expiresDate) {
    metadata.expiresAt = new Date(Number(payload.expiresDate));
  }

  const entitlement = await applyEntitlement(uid, tier, "app_store", metadata);
  if (metadata.originalTransactionId) {
    await db.collection("appStoreTransactions").doc(String(metadata.originalTransactionId)).set({
      uid,
      tier,
      productId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  return {
    tier: entitlement.tier,
    hasPlusAccess: entitlement.tier === "plus" || entitlement.tier === "pro",
    hasProAccess: entitlement.tier === "pro",
    limits: limitsForTier(entitlement.tier),
  };
});

exports.appStoreServerNotificationV2 = onRequest({region: REGION}, async (req, res) => {
  try {
    const signedPayload = req.body?.signedPayload;
    const notification = decodeJwsPayload(signedPayload);
    const data = notification?.data || {};
    const transaction = decodeJwsPayload(data.signedTransactionInfo);

    if (!transaction?.originalTransactionId) {
      res.status(202).send({ok: true, ignored: true});
      return;
    }

    const txSnap = await db.collection("appStoreTransactions")
      .doc(String(transaction.originalTransactionId)).get();
    if (!txSnap.exists) {
      res.status(202).send({ok: true, pendingUserLink: true});
      return;
    }

    const uid = txSnap.data().uid;
    const notificationType = notification.notificationType || "";
    const shouldExpire = ["EXPIRED", "REFUND", "REVOKE", "DID_FAIL_TO_RENEW"].includes(notificationType);
    const tier = shouldExpire || isExpired(transaction) ? "free" : tierForProduct(transaction.productId);

    await applyEntitlement(uid, tier, "app_store_notification", {
      productId: transaction.productId || null,
      originalTransactionId: transaction.originalTransactionId || null,
      transactionId: transaction.transactionId || null,
      notificationType,
      expiresAt: transaction.expiresDate ? new Date(Number(transaction.expiresDate)) : null,
    });

    res.status(200).send({ok: true});
  } catch (error) {
    console.error("App Store notification handling failed", error);
    res.status(500).send({ok: false});
  }
});

function normalizeTopicTag(raw) {
  return String(raw || "")
    .trim()
    .replace(/^#+/, "")
    .replace(/\s+/g, " ")
    .slice(0, 32)
    .trim();
}

exports.listCustomTopicTags = onCall({region: REGION}, async (request) => {
  const uid = requireAuth(request);
  const snap = await db.collection("users").doc(uid)
    .collection("customTopicTags")
    .orderBy("normalized")
    .limit(100)
    .get();

  return {
    tags: snap.docs.map((doc) => doc.data().label).filter(Boolean),
    tier: await getUserTier(uid),
  };
});

exports.createCustomTopicTag = onCall({region: REGION}, async (request) => {
  const uid = requireAuth(request);
  const label = normalizeTopicTag(request.data?.label);
  if (!label) {
    throw new HttpsError("invalid-argument", "Topic tag is required");
  }
  if (!/^[\p{L}\p{N}][\p{L}\p{N} '&+\\/-]{0,31}$/u.test(label)) {
    throw new HttpsError("invalid-argument", "Topic tag contains unsupported characters");
  }

  const userRef = db.collection("users").doc(uid);
  const tagRef = userRef.collection("customTopicTags").doc(label.toLowerCase());

  return db.runTransaction(async (tx) => {
    const [userSnap, tagSnap] = await Promise.all([tx.get(userRef), tx.get(tagRef)]);
    const tier = normalizeTier(userSnap.data()?.premiumEntitlement?.tier || userSnap.data()?.premiumTier);
    const limit = limitsForTier(tier).customTopicTags;

    if (tagSnap.exists) {
      return {tag: tagSnap.data().label, tagsRemaining: limit == null ? null : Math.max(0, limit - (userSnap.data()?.customTopicTagCount || 0)), tier};
    }

    const count = Number(userSnap.data()?.customTopicTagCount || 0);
    if (limit != null && count >= limit) {
      throw new HttpsError("resource-exhausted", "Custom topic tag limit reached", {tier, limit});
    }

    tx.set(tagRef, {
      label,
      normalized: label.toLowerCase(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: uid,
    });
    tx.set(userRef, {
      customTopicTagCount: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {tag: label, tagsRemaining: limit == null ? null : Math.max(0, limit - count - 1), tier};
  });
});

exports.recordAIUsageAndCheckLimit = onCall({region: REGION}, async (request) => {
  const uid = requireAuth(request);
  const dateKey = new Date().toISOString().slice(0, 10);
  const userRef = db.collection("users").doc(uid);
  const usageRef = userRef.collection("usage").doc(`ai_${dateKey}`);

  return db.runTransaction(async (tx) => {
    const [userSnap, usageSnap] = await Promise.all([tx.get(userRef), tx.get(usageRef)]);
    const tier = normalizeTier(userSnap.data()?.premiumEntitlement?.tier || userSnap.data()?.premiumTier);
    const limit = limitsForTier(tier).aiMessagesPerDay;
    const used = Number(usageSnap.data()?.count || 0);

    if (limit != null && used >= limit) {
      throw new HttpsError("resource-exhausted", "Daily AI usage limit reached", {tier, limit, used});
    }

    tx.set(usageRef, {
      count: admin.firestore.FieldValue.increment(1),
      tier,
      lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      tier,
      used: used + 1,
      limit,
      remaining: limit == null ? null : Math.max(0, limit - used - 1),
    };
  });
});

exports.requirePremiumFeature = onCall({region: REGION}, async (request) => {
  const uid = requireAuth(request);
  const requiredTier = normalizeTier(request.data?.requiredTier || "plus");
  const tier = await getUserTier(uid);
  if (TIER_RANK[tier] < TIER_RANK[requiredTier]) {
    throw new HttpsError("permission-denied", "Upgrade required", {tier, requiredTier});
  }
  return {allowed: true, tier};
});

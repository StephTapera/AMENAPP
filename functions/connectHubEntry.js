/**
 * connectHubEntry.js — Standalone Cloud Run entry for getConnectHubFeed
 * Implements the Firebase callable protocol without depending on the full
 * firebase-functions SDK runtime (avoids startup failures from other modules).
 */
"use strict";

const http = require("http");
const admin = require("firebase-admin");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = getFirestore();
const MAX_SPACES = 30;
const MAX_MESSAGES_PER_SPACE = 15;
const BATCH_WINDOW_HOURS = 12;

async function getConnectHubFeedHandler(uid, data) {
  const { tabFilter = "all", since } = data ?? {};

  const batchCutoff = since
    ? new Timestamp(Math.floor(since / 1000), 0)
    : Timestamp.fromDate(new Date(Date.now() - BATCH_WINDOW_HOURS * 60 * 60 * 1000));

  const spacesSnap = await db.collection("spaces")
    .where("memberIds", "array-contains", uid)
    .limit(MAX_SPACES)
    .get();

  if (spacesSnap.empty) return { items: [], caughtUp: true };

  const allItems = [];

  await Promise.all(spacesSnap.docs.map(async (spaceDoc) => {
    const spaceId = spaceDoc.id;
    const spaceName = spaceDoc.data().name ?? null;

    let query = db.collection("spaces").doc(spaceId).collection("messages")
      .where("createdAt", ">=", batchCutoff);

    if (tabFilter !== "all") {
      query = query.where("kind", "==", tabFilter);
    }

    query = query.orderBy("createdAt", "desc").limit(MAX_MESSAGES_PER_SPACE);

    const msgSnap = await query.get();
    for (const doc of msgSnap.docs) {
      const d = doc.data();
      const isCareAlert = d.isCareAlert === true;
      const isCC = d.isCovenantCircle === true;
      const displayName = d.senderDisplayName ?? d.senderId ?? "";
      const initials = displayName.split(" ").slice(0, 2).map((w) => w[0] ?? "").join("").toUpperCase();
      const actions = isCareAlert ? ["pray", "help", "schedule"] : isCC ? ["pray", "discuss", "schedule"] : ["pray", "discuss"];
      allItems.push({
        id: doc.id,
        kind: d.kind ?? "spaceMessage",
        actorId: d.senderId ?? "",
        actorName: displayName,
        actorInitials: initials,
        preview: (d.text ?? "").slice(0, 280),
        spaceName,
        spaceId,
        timestamp: d.createdAt?.toMillis() ?? Date.now(),
        isRead: false,
        actions,
        isCareAlert,
        isCovenantCircle: isCC,
      });
    }
  }));

  allItems.sort((a, b) => {
    if (a.isCareAlert !== b.isCareAlert) return a.isCareAlert ? -1 : 1;
    if (a.isCovenantCircle !== b.isCovenantCircle) return a.isCovenantCircle ? -1 : 1;
    return b.timestamp - a.timestamp;
  });

  return { items: allItems, caughtUp: allItems.length === 0 };
}

// Firebase callable protocol: POST with { data: {...} }, responds with { result: {...} }
const server = http.createServer(async (req, res) => {
  // Health check
  if (req.method === "GET" && req.url === "/") {
    res.writeHead(200);
    res.end("OK");
    return;
  }

  if (req.method !== "POST") {
    res.writeHead(405);
    res.end("Method Not Allowed");
    return;
  }

  let body = "";
  req.on("data", (chunk) => { body += chunk; });
  req.on("end", async () => {
    try {
      // Verify Firebase ID token from Authorization header
      const authHeader = req.headers.authorization ?? "";
      if (!authHeader.startsWith("Bearer ")) {
        res.writeHead(401, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: { status: "UNAUTHENTICATED", message: "Missing token." } }));
        return;
      }
      const idToken = authHeader.slice(7);
      const decoded = await admin.auth().verifyIdToken(idToken);
      const uid = decoded.uid;

      const payload = JSON.parse(body);
      const result = await getConnectHubFeedHandler(uid, payload.data ?? {});

      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ result }));
    } catch (err) {
      const code = err.code === "auth/argument-error" || err.code === "auth/id-token-expired"
        ? 401 : 500;
      res.writeHead(code, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: { status: "INTERNAL", message: err.message } }));
    }
  });
});

const PORT = process.env.PORT || 8080;
server.listen(PORT, () => {
  console.log(`getConnectHubFeed listening on port ${PORT}`);
});

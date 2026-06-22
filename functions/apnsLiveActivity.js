/**
 * apnsLiveActivity.js
 * Raw APNs Live Activity push sender (no high-level libs).
 *
 * Exports:
 *   sendLiveActivityUpdate(token, contentState)  — event: "update"
 *   sendLiveActivityStart(token, attributes, contentState, alert)  — event: "start"
 *
 * Secrets required (set via `firebase functions:secrets:set`):
 *   APNS_KEY      — ES256 .p8 private key PEM
 *   APNS_KEY_ID   — 10-char key ID
 *   APNS_TEAM_ID  — 10-char Team ID
 *   APNS_BUNDLE_ID — bundle ID (tapera.AMENAPP)
 *
 * ES256 JWT is cached for ~50 minutes to stay well within the 1-hour limit.
 */

const http2 = require("http2");
const crypto = require("crypto");

// JWT cache: { token, expiresAt }
let jwtCache = null;

/**
 * Generate or return a cached ES256 APNs provider JWT.
 * @param {{ value: () => string }} APNS_KEY
 * @param {{ value: () => string }} APNS_KEY_ID
 * @param {{ value: () => string }} APNS_TEAM_ID
 */
function getJwt(APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID) {
  const now = Math.floor(Date.now() / 1000);
  if (jwtCache && jwtCache.expiresAt > now + 60) {
    return jwtCache.token;
  }

  const header = Buffer.from(
    JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID.value() })
  ).toString("base64url");

  const payload = Buffer.from(
    JSON.stringify({ iss: APNS_TEAM_ID.value(), iat: now })
  ).toString("base64url");

  const signingInput = `${header}.${payload}`;
  const sign = crypto.createSign("SHA256");
  sign.update(signingInput);
  const signature = sign
    .sign({ key: APNS_KEY.value(), dsaEncoding: "ieee-p1363" })
    .toString("base64url");

  const token = `${signingInput}.${signature}`;
  jwtCache = { token, expiresAt: now + 3000 }; // ~50 min
  return token;
}

/**
 * Send a single APNs request using http2.
 * @returns {{ status: number, headers: object }}
 */
function apnsRequest(secrets, hexToken, apnsHeaders, body) {
  const { APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID } = secrets;
  const host =
    process.env.APNS_ENV === "sandbox"
      ? "api.sandbox.push.apple.com"
      : "api.push.apple.com";
  const path = `/3/device/${hexToken}`;
  const jwt = getJwt(APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID);
  const nowSeconds = Math.floor(Date.now() / 1000);

  return new Promise((resolve, reject) => {
    const client = http2.connect(`https://${host}`);
    client.on("error", reject);

    const bodyStr = JSON.stringify(body);
    const req = client.request({
      ":method": "POST",
      ":path": path,
      "authorization": `bearer ${jwt}`,
      "apns-topic": `${APNS_BUNDLE_ID.value()}.push-type.liveactivity`,
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
      "apns-expiration": String(nowSeconds + 3600),
      "content-type": "application/json",
      "content-length": Buffer.byteLength(bodyStr),
      ...apnsHeaders,
    });

    let status = 0;
    let headers = {};
    let data = "";

    req.on("response", (hdrs) => {
      status = hdrs[":status"];
      headers = hdrs;
    });
    req.on("data", (chunk) => { data += chunk; });
    req.on("end", () => {
      client.close();
      resolve({ status, headers, body: data });
    });
    req.on("error", reject);

    req.write(bodyStr);
    req.end();
  });
}

/**
 * Send a live-activity "update" push.
 * @param {object} secrets  — { APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID }
 * @param {string} hexToken — hex APNs device token
 * @param {object} contentState — new ContentState
 * @returns {{ status: number }}
 */
async function sendLiveActivityUpdate(secrets, hexToken, contentState) {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const body = {
    aps: {
      timestamp: nowSeconds,
      event: "update",
      "content-state": contentState,
      "stale-date": nowSeconds + 3600,
      "relevance-score": 100,
    },
  };
  return apnsRequest(secrets, hexToken, {}, body);
}

/**
 * Send a live-activity "start" push (push-to-start, iOS 17.2+).
 * @param {object} secrets
 * @param {string} hexToken — push-to-start token
 * @param {string} attributesType — Swift type name of ActivityAttributes (e.g. "PrayerRequestAttributes")
 * @param {object} attributes — static attribute values
 * @param {object} contentState — initial ContentState
 * @param {{ title: string, body: string }} alert
 * @returns {{ status: number }}
 */
async function sendLiveActivityStart(
  secrets, hexToken, attributesType, attributes, contentState, alert
) {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const body = {
    aps: {
      timestamp: nowSeconds,
      event: "start",
      "attributes-type": attributesType,
      attributes,
      "content-state": contentState,
      "stale-date": nowSeconds + 3600,
      "relevance-score": 100,
      alert: {
        title: alert.title,
        body: alert.body,
      },
    },
  };
  return apnsRequest(secrets, hexToken, {}, body);
}

module.exports = { sendLiveActivityUpdate, sendLiveActivityStart };

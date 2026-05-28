"use strict";
// accessPassToken.ts — Cryptographic token generation and verification
//
// Raw token lives only in QR/NFC/share URL.
// Only tokenHash is stored in Firestore.
// Token version prevents replay after rotation.
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateRawToken = generateRawToken;
exports.hashToken = hashToken;
exports.verifyToken = verifyToken;
exports.buildUniversalLink = buildUniversalLink;
exports.buildDeepLink = buildDeepLink;
const crypto = __importStar(require("crypto"));
const HASH_ALGORITHM = "sha256";
const TOKEN_BYTES = 32; // 256 bits of entropy
/** Generate a cryptographically secure random token. Returns raw bytes as hex. */
function generateRawToken() {
    return crypto.randomBytes(TOKEN_BYTES).toString("hex");
}
/** Hash a raw token for Firestore storage. Never store the raw token. */
function hashToken(rawToken) {
    return crypto.createHash(HASH_ALGORITHM).update(rawToken).digest("hex");
}
/** Constant-time comparison to prevent timing attacks. */
function verifyToken(rawToken, storedHash) {
    const incomingHash = hashToken(rawToken);
    if (incomingHash.length !== storedHash.length)
        return false;
    return crypto.timingSafeEqual(Buffer.from(incomingHash), Buffer.from(storedHash));
}
/** Build the universal link for a pass. rawToken is embedded in the URL. */
function buildUniversalLink(accessPassId, rawToken) {
    return `https://amen.app/access/${accessPassId}?t=${rawToken}`;
}
/** Build the app deep link for a pass. */
function buildDeepLink(accessPassId, rawToken) {
    return `amen://access/${accessPassId}?t=${rawToken}`;
}
//# sourceMappingURL=accessPassToken.js.map
// integrations/integrationAudit.ts
// Safe audit logging — never logs sensitive payloads

import * as admin from "firebase-admin";
import type { AmenIntegrationAuditAction, AmenIntegrationProvider } from "./types";

const db = admin.firestore();

export async function writeAuditLog(params: {
  uid: string;
  action: AmenIntegrationAuditAction;
  provider?: AmenIntegrationProvider;
  metadata?: Record<string, string | number | boolean>;
}): Promise<void> {
  try {
    const logRef = db.collection("integrationAuditLogs").doc();
    await logRef.set({
      logId: logRef.id,
      uid: params.uid,
      action: params.action,
      ...(params.provider && { provider: params.provider }),
      ...(params.metadata && { metadata: params.metadata }),
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    // Audit failure must never block the primary operation
    console.error("[integrationAudit] Failed to write audit log:", e);
  }
}

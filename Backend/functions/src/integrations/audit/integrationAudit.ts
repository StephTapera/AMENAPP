import * as admin from "firebase-admin";
import type {AmenIntegrationAuditLog, AmenIntegrationProvider} from "../models";

const db = admin.firestore();

export async function writeIntegrationAudit(input: {
    provider: AmenIntegrationProvider;
    action: string;
    actorId: string;
    success: boolean;
    errorCode?: string;
    securityFlags?: string[];
    metadata?: Record<string, unknown>;
}): Promise<void> {
    const log: AmenIntegrationAuditLog = {
        provider: input.provider,
        action: input.action,
        actorId: input.actorId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: input.success,
        errorCode: input.errorCode,
        securityFlags: input.securityFlags ?? [],
        metadata: input.metadata,
    };
    await db.collection("amenIntegrationAuditLogs").add(log);
}

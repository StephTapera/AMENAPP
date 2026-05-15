import * as admin from "firebase-admin";
import type {
    ChurchAdminRecord,
    ChurchVerificationRecord,
    LivestreamRecord,
    ModerationQueueRecord,
} from "../models/churchTrust";

const db = admin.firestore();

export class ChurchTrustRepository {
    churchRef(churchId: string) {
        return db.collection("churches").doc(churchId);
    }

    adminRef(uid: string) {
        return db.collection("church_admins").doc(uid);
    }

    moderationQueueRef(itemId: string) {
        return db.collection("moderation_queue").doc(itemId);
    }

    verificationQueueRef(requestId: string) {
        return db.collection("church_verification_requests").doc(requestId);
    }

    async loadAdmin(uid: string): Promise<ChurchAdminRecord | null> {
        const snapshot = await this.adminRef(uid).get();
        return snapshot.exists ? snapshot.data() as ChurchAdminRecord : null;
    }

    async assertChurchAccess(uid: string, churchId: string, acceptedRoles?: string[]) {
        const adminRecord = await this.loadAdmin(uid);
        if (!adminRecord || !adminRecord.churchIds.includes(churchId)) {
            throw new Error("permission-denied");
        }
        if (acceptedRoles && !acceptedRoles.includes(adminRecord.role)) {
            throw new Error("permission-denied");
        }
        return adminRecord;
    }

    async writeVerification(churchId: string, payload: Partial<ChurchVerificationRecord>) {
        await this.churchRef(churchId).set(payload, {merge: true});
    }

    async writeLivestream(churchId: string, streamId: string, payload: LivestreamRecord) {
        await this.churchRef(churchId)
            .collection("livestreams")
            .doc(streamId)
            .set(payload, {merge: true});
    }

    async writeModerationItem(itemId: string, payload: Partial<ModerationQueueRecord>) {
        await this.moderationQueueRef(itemId).set(payload, {merge: true});
    }
}

export const churchTrustRepository = new ChurchTrustRepository();

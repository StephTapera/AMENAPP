import * as admin from "firebase-admin";
import type {SpiritualGraphEdgeRecord, SpiritualMemoryRecord} from "../models/spiritualGraph";

const db = admin.firestore();

export class SpiritualGraphService {
    async writeEdge(edgeId: string, payload: SpiritualGraphEdgeRecord) {
        await db.collection("spiritual_graph")
            .doc("edges")
            .collection("items")
            .doc(edgeId)
            .set(payload, {merge: true});
    }

    async writeMemory(uid: string, memoryId: string, payload: SpiritualMemoryRecord) {
        await db.collection("users")
            .doc(uid)
            .collection("spiritual_memory")
            .doc(memoryId)
            .set(payload, {merge: true});
    }

    async buildAffinitySnapshot(uid: string) {
        const edgeSnapshot = await db.collection("spiritual_graph")
            .doc("edges")
            .collection("items")
            .limit(300)
            .get();

        const churchAffinity: Record<string, number> = {};
        const worshipSimilarity: Record<string, number> = {};
        const communityOverlap: Record<string, number> = {};
        const ministryRelevance: Record<string, number> = {};

        edgeSnapshot.documents.forEach((doc) => {
            const edge = doc.data() as Partial<SpiritualGraphEdgeRecord>;
            if (!edge.type || typeof edge.toId !== "string") return;

            if (["attends", "visited", "saved", "interested"].includes(edge.type)) {
                churchAffinity[edge.toId] = Math.max(churchAffinity[edge.toId] ?? 0, edge.strength ?? 0);
            }
            if (["watches", "studies"].includes(edge.type)) {
                worshipSimilarity[edge.toId] = Math.max(worshipSimilarity[edge.toId] ?? 0, edge.strength ?? 0);
            }
            if (["participates", "connectedTo"].includes(edge.type)) {
                communityOverlap[edge.toId] = Math.max(communityOverlap[edge.toId] ?? 0, edge.strength ?? 0);
            }
            if (["volunteers", "serves"].includes(edge.type)) {
                ministryRelevance[edge.toId] = Math.max(ministryRelevance[edge.toId] ?? 0, edge.strength ?? 0);
            }
        });

        await db.collection("users")
            .doc(uid)
            .collection("spiritual_graph_state")
            .doc("affinity")
            .set({
                churchAffinity,
                worshipSimilarity,
                communityOverlap,
                ministryRelevance,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
    }
}

export const spiritualGraphService = new SpiritualGraphService();

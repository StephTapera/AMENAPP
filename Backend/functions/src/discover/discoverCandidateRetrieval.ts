import * as admin from "firebase-admin";
import { DiscoverItemDoc } from "./discoverTypes";

export async function retrieveDiscoverCandidates(limit = 120): Promise<DiscoverItemDoc[]> {
  const db = admin.firestore();
  const snapshot = await db.collection("discoverItems").limit(limit).get();
  return snapshot.docs.map((doc) => {
    const data = doc.data() as Omit<DiscoverItemDoc, "id">;
    return { ...data, id: doc.id };
  });
}

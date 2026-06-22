export type CreatorProjectStatus = "draft" | "processing" | "ready" | "failed" | "published";

export interface CreatorProjectPayload {
    id: string;
    ownerID: string;
    title: string;
    projectType: string;
    status: CreatorProjectStatus;
    visibility: string;
    aspectRatio: string;
    assetIDs: string[];
    layerIDs: string[];
    sceneIDs: string[];
    subtitleTrackIDs: string[];
    outputVariants: string[];
    publishTargets: string[];
    autosaveVersion: number;
    lastEditedAt: FirebaseFirestore.FieldValue;
    createdAt: FirebaseFirestore.FieldValue;
    publishedAt?: FirebaseFirestore.FieldValue;
}

export interface CreatorJobPayload {
    id: string;
    projectID: string;
    ownerID: string;
    type: string;
    status: string;
    progress: number;
    inputRefs: string[];
    outputRefs: string[];
    createdAt: FirebaseFirestore.FieldValue;
}

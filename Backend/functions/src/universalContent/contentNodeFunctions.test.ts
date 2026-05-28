import admin from "firebase-admin";
import * as fs from "fs";
import * as path from "path";
import {
  createContentNode,
  getContentDraft,
  getProfileContent,
  getUniversalContentFeed,
  keywordSearchContent,
  publishDraftToContentNode,
  reviewContentNodeModeration,
  saveContentDraft,
  updateContentNode,
} from "./contentNodeFunctions";
import {
  createCommunity,
  createMediaUploadSession,
  createNote,
  exportDesignImageMetadata,
  finalizeMediaUpload,
  generateEmbeddings,
  generateCaptions,
  generateMediaSummary,
  generateVideoChapters,
  indexContentNode,
  processUploadedMedia,
  publishScheduledContent,
  convertNoteToPost,
  createCommunityPost,
  createReply,
  rewriteContent,
  saveThreadToNote,
  saveDesignProject,
  scheduleContent,
  summarizeThread,
  updateNoteBlock,
} from "./platformFunctions";

const mockAdmin = admin as unknown as {
  __mockDoc: {
    get: jest.Mock;
    set: jest.Mock;
    update: jest.Mock;
    delete: jest.Mock;
    collection: jest.Mock;
    id: string;
    __data: unknown;
  };
  __mockBatch: {
    set: jest.Mock;
    delete: jest.Mock;
    update: jest.Mock;
    commit: jest.Mock;
  };
  __mockQuery: {
    get: jest.Mock;
    where: jest.Mock;
    orderBy: jest.Mock;
    limit: jest.Mock;
  };
};

const mockDoc = mockAdmin.__mockDoc;
const mockBatch = mockAdmin.__mockBatch;
const mockQuery = mockAdmin.__mockQuery;
const projectRoot = path.resolve(__dirname, "../../../..");

function authed(data: Record<string, unknown> = {}) {
  return {
    auth: { uid: "user-1" },
    app: { appId: "test-app" },
    data,
  };
}

function moderator(data: Record<string, unknown> = {}) {
  return {
    auth: { uid: "mod-1", token: { moderator: true } },
    app: { appId: "test-app" },
    data,
  };
}

function contentDoc(id: string, data: Record<string, unknown>) {
  return {
    id,
    data: () => data,
    get: (field: string) => data[field],
  };
}

function call(fn: unknown, request: Record<string, unknown>) {
  return (fn as (request: Record<string, unknown>) => Promise<unknown>)(request);
}

beforeEach(() => {
  jest.clearAllMocks();
  global.fetch = jest.fn().mockResolvedValue({
    ok: true,
    json: async () => ({
      content: [{ type: "text", text: "A clearer rewritten draft." }],
      data: [{ embedding: [0.1, 0.2, 0.3] }],
    }),
    text: async () => "",
  }) as unknown as typeof fetch;
  mockDoc.__data = undefined;
  mockDoc.id = "mock-doc-id";
  mockDoc.get.mockResolvedValue({ exists: false, data: () => undefined, get: () => undefined });
  mockDoc.set.mockResolvedValue(undefined);
  mockDoc.update.mockResolvedValue(undefined);
  mockDoc.delete.mockResolvedValue(undefined);
  mockBatch.set.mockClear();
  mockBatch.delete.mockClear();
  mockBatch.update.mockClear();
  mockBatch.commit.mockResolvedValue(undefined);
  mockQuery.get.mockResolvedValue({ docs: [], empty: true });
  mockQuery.where.mockReturnValue(mockQuery);
  mockQuery.orderBy.mockReturnValue(mockQuery);
  mockQuery.limit.mockReturnValue(mockQuery);
});

describe("universal content callables", () => {
  it("requires authentication and App Check", async () => {
    await expect(call(createContentNode, { data: { contentType: "post" } }))
      .rejects.toMatchObject({ code: "unauthenticated" });

    await expect(call(createContentNode, { auth: { uid: "user-1" }, data: { contentType: "post" } }))
      .rejects.toMatchObject({ code: "unauthenticated" });
  });

  it("rejects invalid content types before writing", async () => {
    await expect(call(createContentNode, authed({ contentType: "secretMemory", text: "Nope" })))
      .rejects.toMatchObject({ code: "invalid-argument" });

    expect(mockDoc.set).not.toHaveBeenCalled();
  });

  it("saves owner-isolated drafts with server-owned sync fields", async () => {
    await expect(call(saveContentDraft, authed({
      draftId: "draft-1",
      draftType: "textPost",
      contentType: "post",
      text: "A calm idea",
      intendedVisibility: "private",
    }))).resolves.toMatchObject({ success: true, draftId: "draft-1" });

    expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
      id: "draft-1",
      ownerId: "user-1",
      intent: "textPost",
      contentType: "post",
      text: "A calm idea",
      intendedVisibility: "private",
      syncState: "synced",
    }), { merge: true });
  });

  it("returns Swift-decodable drafts from Firestore snapshots", async () => {
    const timestamp = admin.firestore.Timestamp.fromDate(new Date("2026-05-19T12:00:00.000Z"));
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({
        id: "draft-1",
        ownerId: "user-1",
        draftType: "textPost",
        text: "Restore me",
        intendedVisibility: "private",
        createdAt: timestamp,
        updatedAt: timestamp,
      }),
      get: () => undefined,
    });

    await expect(call(getContentDraft, authed({ draftId: "draft-1" })))
      .resolves.toMatchObject({
        success: true,
        draft: {
          id: "draft-1",
          ownerId: "user-1",
          intent: "textPost",
          text: "Restore me",
          createdAt: "2026-05-19T12:00:00.000Z",
          updatedAt: "2026-05-19T12:00:00.000Z",
        },
      });
  });

  it("denies updates by non-owners", async () => {
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ ownerId: "other-user" }),
      get: (field: string) => field === "ownerId" ? "other-user" : undefined,
    });

    await expect(call(updateContentNode, authed({
      contentId: "content-1",
      text: "Changed",
    }))).rejects.toMatchObject({ code: "permission-denied" });

    expect(mockDoc.update).not.toHaveBeenCalled();
  });

  it("publishes drafts as pending moderation content and deletes the draft", async () => {
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({
        id: "draft-1",
        ownerId: "user-1",
        draftType: "textPost",
        contentType: "post",
        text: "Ready to publish",
        intendedVisibility: "public",
      }),
      get: () => undefined,
    });

    await expect(call(publishDraftToContentNode, authed({ draftId: "draft-1" })))
      .resolves.toMatchObject({ success: true, moderationStatus: "pending" });

    expect(mockBatch.set).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      ownerId: "user-1",
      type: "post",
      visibility: "public",
      text: "Ready to publish",
      publishState: "published",
      moderationState: { status: "pending" },
      aiMetadata: { usedAI: false },
    }));
    expect(mockBatch.delete).toHaveBeenCalled();
    expect(mockBatch.commit).toHaveBeenCalled();
  });

  it("lets only moderators review moderation state", async () => {
    await expect(call(reviewContentNodeModeration, authed({
      contentId: "content-1",
      decision: "approved",
    }))).rejects.toMatchObject({ code: "permission-denied" });

    await expect(call(reviewContentNodeModeration, moderator({
      contentId: "content-1",
      decision: "approved",
      reason: "safe",
    }))).resolves.toMatchObject({
      success: true,
      contentId: "content-1",
      moderationStatus: "approved",
    });

    expect(mockDoc.update).toHaveBeenCalledWith(expect.objectContaining({
      moderationState: expect.objectContaining({
        status: "approved",
        reason: "safe",
        reviewedBy: "mod-1",
      }),
    }));
  });

  it("feed and keyword search only return public approved content", async () => {
    const createdAt = admin.firestore.Timestamp.fromDate(new Date("2026-05-19T12:00:00.000Z"));
    mockQuery.get.mockResolvedValue({
      docs: [
        contentDoc("visible", {
          id: "visible",
          title: "Peace",
          text: "A public approved post",
          publishState: "published",
          visibility: "public",
          "moderationState.status": "approved",
          createdAt,
          updatedAt: createdAt,
        }),
        contentDoc("deleted", {
          id: "deleted",
          title: "Deleted",
          text: "Should not return",
          deletedAt: createdAt,
          createdAt,
          updatedAt: createdAt,
        }),
      ],
    });

    await expect(call(getUniversalContentFeed, authed({ limit: 10 })))
      .resolves.toMatchObject({
        success: true,
        items: [expect.objectContaining({ id: "visible", title: "Peace" })],
      });

    await expect(call(keywordSearchContent, authed({ query: "approved" })))
      .resolves.toMatchObject({
        success: true,
        items: [expect.objectContaining({ id: "visible" })],
      });
  });

  it("profile content requires public approved filters for non-owners", async () => {
    mockQuery.get.mockResolvedValue({ docs: [] });

    await expect(call(getProfileContent, authed({ ownerId: "other-user" })))
      .resolves.toMatchObject({ success: true, items: [] });

    const whereCalls = mockQuery.where.mock.calls.map((callArgs) => callArgs.slice(0, 3));
    expect(whereCalls).toContainEqual(["visibility", "==", "public"]);
    expect(whereCalls).toContainEqual(["moderationState.status", "==", "approved"]);
  });
});

describe("universal platform callables", () => {
  it("creates callable-owned media upload sessions and rejects invalid media", async () => {
    await expect(call(createMediaUploadSession, authed({ type: "archive" })))
      .rejects.toMatchObject({ code: "invalid-argument" });

    await expect(call(createMediaUploadSession, authed({ type: "video" })))
      .resolves.toMatchObject({
        success: true,
        mediaId: "mock-doc-id",
        storagePath: "users/user-1/media/mock-doc-id/original",
      });

    expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
      ownerId: "user-1",
      type: "video",
      uploadState: "created",
      processingState: "waitingForUpload",
      moderationState: { status: "pending" },
    }));
  });

  it("finalizes only an owner media upload into queued processing", async () => {
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ id: "media-1", ownerId: "user-1" }),
      get: (field: string) => field === "ownerId" ? "user-1" : undefined,
    });

    await expect(call(finalizeMediaUpload, authed({
      mediaId: "media-1",
      width: 1080,
      height: 1920,
      duration: 12,
    }))).resolves.toMatchObject({
      success: true,
      mediaId: "media-1",
      processingState: "queued",
    });

    expect(mockDoc.update).toHaveBeenCalledWith(expect.objectContaining({
      uploadState: "finalized",
      processingState: "queued",
      width: 1080,
      height: 1920,
      duration: 12,
    }));
  });

  it("creates notes and owner-owned blocks without client-writeable server fields", async () => {
    await expect(call(createNote, authed({ title: "Launch plan" })))
      .resolves.toMatchObject({ success: true, noteId: "mock-doc-id" });

    expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
      ownerId: "user-1",
      title: "Launch plan",
      visibility: "private",
      moderationState: { status: "pending" },
    }));

    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ ownerId: "user-1" }),
      get: (field: string) => field === "ownerId" ? "user-1" : undefined,
    });

    await expect(call(updateNoteBlock, authed({
      noteId: "note-1",
      blockId: "block-1",
      type: "heading",
      text: "Sunday recap",
      order: 1,
    }))).resolves.toMatchObject({ success: true, noteId: "note-1", blockId: "block-1" });
  });

  it("saves design projects and validates export ownership path", async () => {
    await expect(call(saveDesignProject, authed({
      designId: "design-1",
      title: "Invite card",
      templateId: "announcement",
      payload: { text: "Come join us" },
    }))).resolves.toMatchObject({ success: true, designId: "design-1" });

    await expect(call(exportDesignImageMetadata, authed({
      designId: "design-1",
      storagePath: "users/other/designs/design-1/export.png",
    }))).rejects.toMatchObject({ code: "permission-denied" });

    await expect(call(exportDesignImageMetadata, authed({
      designId: "design-1",
      storagePath: "users/user-1/designs/design-1/export.png",
      width: 1080,
      height: 1080,
    }))).resolves.toMatchObject({ success: true, designId: "design-1" });
  });

  it("creates communities and scheduled content through server-owned callables", async () => {
    await expect(call(createCommunity, authed({
      name: "Creators",
      type: "creator",
      isPrivate: true,
    }))).resolves.toMatchObject({ success: true, communityId: "mock-doc-id" });

    expect(mockBatch.set).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      creatorId: "user-1",
      adminIds: ["user-1"],
      type: "creator",
      isPrivate: true,
      moderationStatus: "approved",
    }));

    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ ownerId: "user-1" }),
      get: (field: string) => {
        if (field === "ownerId") return "user-1";
        if (field === "moderationState.status") return "approved";
        return undefined;
      },
    });

    await expect(call(scheduleContent, authed({
      contentId: "content-1",
      scheduledAt: "2026-05-20T15:00:00.000Z",
    }))).resolves.toMatchObject({ success: true, scheduleId: "mock-doc-id" });
  });

  it("publishes scheduled content only when schedule and content are approved", async () => {
    mockDoc.get
      .mockResolvedValueOnce({
        exists: true,
        data: () => ({ ownerId: "user-1", contentId: "content-1", status: "scheduled" }),
        get: (field: string) => {
          if (field === "ownerId") return "user-1";
          if (field === "contentId") return "content-1";
          if (field === "status") return "scheduled";
          return undefined;
        },
      })
      .mockResolvedValueOnce({
        exists: true,
        data: () => ({ ownerId: "user-1" }),
        get: (field: string) => {
          if (field === "ownerId") return "user-1";
          if (field === "moderationState.status") return "approved";
          return undefined;
        },
      });

    await expect(call(publishScheduledContent, authed({ scheduleId: "schedule-1" })))
      .resolves.toMatchObject({ success: true, contentId: "content-1", scheduleId: "schedule-1" });

    expect(mockBatch.update).toHaveBeenCalledTimes(2);
    expect(mockBatch.commit).toHaveBeenCalled();
  });

  it("creates community posts as pending moderation content", async () => {
    mockDoc.get
      .mockResolvedValueOnce({
        exists: true,
        data: () => ({ creatorId: "user-1", adminIds: ["user-1"] }),
        get: (field: string) => {
          if (field === "creatorId") return "user-1";
          if (field === "adminIds") return ["user-1"];
          return undefined;
        },
      })
      .mockResolvedValueOnce({ exists: false, data: () => undefined, get: () => undefined });

    await expect(call(createCommunityPost, authed({
      communityId: "community-1",
      text: "A community update",
    }))).resolves.toMatchObject({ success: true, moderationStatus: "pending" });

    expect(mockBatch.set).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      ownerId: "user-1",
      type: "communityPost",
      visibility: "community",
      text: "A community update",
      moderationState: { status: "pending" },
    }));
  });

  it("creates replies only for approved public content or owned content", async () => {
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ ownerId: "other", visibility: "public", publishState: "published" }),
      get: (field: string) => {
        if (field === "ownerId") return "other";
        if (field === "visibility") return "public";
        if (field === "publishState") return "published";
        if (field === "moderationState.status") return "approved";
        return undefined;
      },
    });

    await expect(call(createReply, authed({ contentId: "content-1", body: "Thoughtful reply" })))
      .resolves.toMatchObject({ success: true, moderationStatus: "pending" });

    expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
      contentId: "content-1",
      ownerId: "user-1",
      body: "Thoughtful reply",
      moderationState: { status: "pending" },
    }));
  });

  it("summarizes approved thread replies through the AI adapter", async () => {
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ ownerId: "other", visibility: "public", publishState: "published", title: "Peace", text: "Main post" }),
      get: (field: string) => {
        if (field === "ownerId") return "other";
        if (field === "visibility") return "public";
        if (field === "publishState") return "published";
        if (field === "moderationState.status") return "approved";
        if (field === "title") return "Peace";
        if (field === "text") return "Main post";
        return undefined;
      },
    });
    mockQuery.get.mockResolvedValue({
      docs: [
        contentDoc("reply-1", { body: "This helped me reflect." }),
        contentDoc("reply-2", { body: "A useful follow-up question." }),
      ],
      empty: false,
    });

    await expect(call(summarizeThread, authed({ contentId: "content-1" })))
      .resolves.toMatchObject({ success: true, summary: "A clearer rewritten draft." });

    expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
      contentId: "content-1",
      ownerId: "user-1",
      summary: "A clearer rewritten draft.",
      replyCount: 2,
    }));
  });

  it("saves a readable thread to the owner note index", async () => {
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ ownerId: "other", visibility: "public", publishState: "published", title: "Peace", text: "Main post" }),
      get: (field: string) => {
        if (field === "ownerId") return "other";
        if (field === "visibility") return "public";
        if (field === "publishState") return "published";
        if (field === "moderationState.status") return "approved";
        if (field === "title") return "Peace";
        if (field === "text") return "Main post";
        return undefined;
      },
    });

    await expect(call(saveThreadToNote, authed({ contentId: "content-1", summary: "Useful summary" })))
      .resolves.toMatchObject({ success: true, noteId: "mock-doc-id" });

    expect(mockBatch.set).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      ownerId: "user-1",
      sourceContentId: "content-1",
      aiSummary: "Useful summary",
    }));
    expect(mockBatch.commit).toHaveBeenCalled();
  });

  it("converts notes into owner draft records", async () => {
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ ownerId: "user-1", title: "Sermon notes" }),
      get: (field: string) => {
        if (field === "ownerId") return "user-1";
        if (field === "title") return "Sermon notes";
        return undefined;
      },
    });

    await expect(call(convertNoteToPost, authed({ noteId: "note-1" })))
      .resolves.toMatchObject({ success: true, draftId: "mock-doc-id" });

    expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
      ownerId: "user-1",
      draftType: "noteToPost",
      sourceNoteId: "note-1",
      syncState: "synced",
    }));
  });

  it("indexes only owner public approved content", async () => {
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ ownerId: "user-1", type: "post", title: "Peace", text: "Approved content" }),
      get: (field: string) => {
        if (field === "ownerId") return "user-1";
        if (field === "visibility") return "public";
        if (field === "publishState") return "published";
        if (field === "moderationState.status") return "approved";
        if (field === "type") return "post";
        if (field === "title") return "Peace";
        if (field === "text") return "Approved content";
        return undefined;
      },
    });

    await expect(call(indexContentNode, authed({ contentId: "content-1" })))
      .resolves.toMatchObject({ success: true, contentId: "content-1" });

    expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
      id: "content-1",
      ownerId: "user-1",
      moderationStatus: "approved",
    }));
  });

  it("moves finalized media into processing state", async () => {
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ ownerId: "user-1", uploadState: "finalized" }),
      get: (field: string) => {
        if (field === "ownerId") return "user-1";
        if (field === "uploadState") return "finalized";
        return undefined;
      },
    });

    await expect(call(processUploadedMedia, authed({ mediaId: "media-1" })))
      .resolves.toMatchObject({ success: true, mediaId: "media-1", processingState: "processing" });

    expect(mockDoc.update).toHaveBeenCalledWith(expect.objectContaining({
      processingState: "processing",
    }));
  });

  it("generates captions from an owner transcript track", async () => {
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ ownerId: "user-1" }),
      get: (field: string) => {
        if (field === "ownerId") return "user-1";
        if (field === "text") return "First sentence. Second sentence.";
        return undefined;
      },
    });

    await expect(call(generateCaptions, authed({ mediaId: "media-1" })))
      .resolves.toMatchObject({ success: true, mediaId: "media-1", captionStatus: "ready", segmentCount: 2 });

    expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
      mediaId: "media-1",
      ownerId: "user-1",
      generatedTranscript: "First sentence. Second sentence.",
      provider: "amen-transcript-segmenter",
    }));
  });

  it("generates media chapters and summaries from ready transcripts", async () => {
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ ownerId: "user-1" }),
      get: (field: string) => {
        if (field === "ownerId") return "user-1";
        if (field === "text") return "A transcript long enough to summarize and chapter for media intelligence.";
        return undefined;
      },
    });

    await expect(call(generateVideoChapters, authed({ mediaId: "media-1" })))
      .resolves.toMatchObject({ success: true, mediaId: "media-1" });
    await expect(call(generateMediaSummary, authed({ mediaId: "media-1" })))
      .resolves.toMatchObject({ success: true, mediaId: "media-1", summary: "A clearer rewritten draft." });

    expect(mockDoc.update).toHaveBeenCalledWith(expect.objectContaining({
      chapterStatus: "ready",
    }));
    expect(mockDoc.update).toHaveBeenCalledWith(expect.objectContaining({
      summaryStatus: "ready",
      summary: "A clearer rewritten draft.",
    }));
  });

  it("runs AI rewrite through the provider adapter and labels generated output", async () => {
    await expect(call(rewriteContent, authed({ text: "Please rewrite this draft." })))
      .resolves.toMatchObject({
        success: true,
        status: "completed",
        result: {
          text: "A clearer rewritten draft.",
          aiMetadata: expect.objectContaining({
            usedAI: true,
            provider: "anthropic",
            userAccepted: false,
          }),
        },
      });

    expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
      ownerId: "user-1",
      feature: "rewriteContent",
      status: "running",
    }));
    expect(mockDoc.update).toHaveBeenCalledWith(expect.objectContaining({
      status: "completed",
    }));
  });

  it("generates embeddings only for owner public approved content", async () => {
    mockDoc.get.mockResolvedValue({
      exists: true,
      data: () => ({ ownerId: "user-1", title: "Peace", text: "Approved content" }),
      get: (field: string) => {
        if (field === "ownerId") return "user-1";
        if (field === "visibility") return "public";
        if (field === "publishState") return "published";
        if (field === "moderationState.status") return "approved";
        if (field === "title") return "Peace";
        if (field === "text") return "Approved content";
        return undefined;
      },
    });

    await expect(call(generateEmbeddings, authed({ contentId: "content-1" })))
      .resolves.toMatchObject({ success: true, contentId: "content-1", dimensions: 3 });

    expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
      id: "content-1",
      ownerId: "user-1",
      model: "text-embedding-3-small",
      dimensions: 3,
      embedding: [0.1, 0.2, 0.3],
    }));
  });
});

describe("universal content Firestore rules posture", () => {
  it("deploy rules protect drafts, content writes, moderation, and aggregate metrics", () => {
    const rules = fs.readFileSync(path.join(projectRoot, "AMENAPP/firestore.deploy.rules"), "utf8").replace(/\s+/g, "");

    expect(rules).toContain("match/users/{userId}/drafts/{draftId}");
    expect(rules).toContain("allowread:ifisOwner(userId);allowwrite:iffalse;");
    expect(rules).toContain("match/content/{contentId}");
    expect(rules).toContain("resource.data.moderationState.status=='approved'");
    expect(rules).toContain("allowcreate,update,delete:iffalse;");
    expect(rules).toContain("match/metrics/{metricId}");
    expect(rules).toContain("metricId=='aggregate'");
    expect(rules).toContain("match/users/{userId}/media/{mediaId}");
    expect(rules).toContain("match/transcriptTracks/{trackId}");
    expect(rules).toContain("match/captionTracks/{trackId}");
    expect(rules).toContain("match/users/{userId}/designs/{designId}");
    expect(rules).toContain("match/users/{userId}/scheduledContent/{scheduleId}");
    expect(rules).toContain("match/users/{userId}/aiJobs/{jobId}");
    expect(rules).toContain("match/notes/{noteId}");
    expect(rules).toContain("match/searchIndex/{itemId}");
    expect(rules).toContain("match/contentEmbeddings/{contentId}");
    expect(rules).toContain("match/replies/{replyId}");
    expect(rules).toContain("match/threadSummaries/{summaryId}");
  });
});

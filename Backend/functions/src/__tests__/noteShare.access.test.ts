jest.mock("firebase-admin", () => ({
  firestore: jest.fn(() => ({ collection: jest.fn() })),
}));

jest.mock("firebase-functions/v2/https", () => ({
  HttpsError: class HttpsError extends Error {
    code: string;

    constructor(code: string, message: string) {
      super(message);
      this.code = code;
    }
  },
  onCall: jest.fn((_options, handler) => handler),
}));

jest.mock("../thinkFirst/validator", () => ({
  validateThinkFirst: jest.fn(() => ({
    status: "allow",
    requiresReview: false,
    categories: [],
  })),
}));

import { noteShareAccessDecisionForTest } from "../noteShare";

describe("noteShare access contract", () => {
  test("revoked share returns nothing", () => {
    expect(noteShareAccessDecisionForTest({
      status: "revoked",
      viewerUid: "viewer",
      authorUid: "author",
      visibility: "public",
    })).toBe(false);
  });

  test("non-connection cannot read a connections-visibility share", () => {
    expect(noteShareAccessDecisionForTest({
      status: "active",
      viewerUid: "viewer",
      authorUid: "author",
      visibility: "followers",
      hasMutualConnection: false,
    })).toBe(false);
  });

  test("mutual connection can read a connections-visibility share", () => {
    expect(noteShareAccessDecisionForTest({
      status: "active",
      viewerUid: "viewer",
      authorUid: "author",
      visibility: "followers",
      hasMutualConnection: true,
    })).toBe(true);
  });

  test("non-member cannot read a church-visibility share", () => {
    expect(noteShareAccessDecisionForTest({
      status: "active",
      viewerUid: "viewer",
      authorUid: "author",
      visibility: "church",
      hasOrganizationMemberRole: false,
    })).toBe(false);
  });

  test("organization member can read a church-visibility share", () => {
    expect(noteShareAccessDecisionForTest({
      status: "active",
      viewerUid: "viewer",
      authorUid: "author",
      visibility: "church",
      hasOrganizationMemberRole: true,
    })).toBe(true);
  });

  test("signed-out access is denied even for link shares", () => {
    expect(noteShareAccessDecisionForTest({
      status: "active",
      viewerUid: null,
      authorUid: "author",
      visibility: "link",
      linkToken: "token",
      providedLinkToken: "token",
    })).toBe(false);
  });
});

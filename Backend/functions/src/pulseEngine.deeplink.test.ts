import { pulseDeeplink } from "./pulseEngine";

describe("pulseDeeplink — verb → in-app route synthesis", () => {
  it("pray → amen://prayer/{prayerId}", () => {
    expect(pulseDeeplink("pray", { prayerId: "p1" })).toBe("amen://prayer/p1");
  });

  it("sendLove → amen://user/{userId}, falling back to friendId", () => {
    expect(pulseDeeplink("sendLove", { userId: "u1" })).toBe("amen://user/u1");
    expect(pulseDeeplink("sendLove", { friendId: "f1" })).toBe("amen://user/f1");
    expect(pulseDeeplink("sendLove", { userId: "u1", friendId: "f1" })).toBe("amen://user/u1");
  });

  it("rsvp and openSermon → amen://event/{eventId}", () => {
    expect(pulseDeeplink("rsvp", { eventId: "e1" })).toBe("amen://event/e1");
    expect(pulseDeeplink("openSermon", { eventId: "e2" })).toBe("amen://event/e2");
  });

  it("openSpace → amen://space/{spaceId}", () => {
    expect(pulseDeeplink("openSpace", { spaceId: "s1" })).toBe("amen://space/s1");
  });

  it("returns undefined when the required id is missing (fail-closed → pill disables)", () => {
    expect(pulseDeeplink("pray", {})).toBeUndefined();
    expect(pulseDeeplink("sendLove", {})).toBeUndefined();
    expect(pulseDeeplink("rsvp", {})).toBeUndefined();
    expect(pulseDeeplink("openSpace", {})).toBeUndefined();
  });

  it("returns undefined for non-routable verbs (openBrief / read / checkIn / seeWhatsNew / none)", () => {
    expect(pulseDeeplink("openBrief", { prayerId: "p1" })).toBeUndefined();
    expect(pulseDeeplink("read", { prayerId: "p1" })).toBeUndefined();
    expect(pulseDeeplink("checkIn", { prayerId: "p1" })).toBeUndefined();
    expect(pulseDeeplink("seeWhatsNew", { spaceId: "s1" })).toBeUndefined();
    expect(pulseDeeplink("none", {})).toBeUndefined();
  });
});

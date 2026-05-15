const test = require("node:test");
const assert = require("node:assert/strict");
const { _internal } = require("../musicAttachmentResolver");

test("parses Spotify track URLs", () => {
  const parsed = _internal.parseMusicAttachmentURL("https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6?si=abc");
  assert.equal(parsed.provider, "spotify");
  assert.equal(parsed.entityType, "song");
  assert.equal(parsed.providerID, "6rqhFgbbKwnb9MLmUQDhG6");
  assert.equal(parsed.canonicalURL, "https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6");
});

test("parses Spotify album URIs", () => {
  const parsed = _internal.parseMusicAttachmentURL("spotify:album:2noRn2Aes5aoNVsU6iWThc");
  assert.equal(parsed.provider, "spotify");
  assert.equal(parsed.entityType, "album");
  assert.equal(parsed.providerID, "2noRn2Aes5aoNVsU6iWThc");
});

test("parses Apple Music song URLs from album pages", () => {
  const parsed = _internal.parseMusicAttachmentURL("https://music.apple.com/us/album/goodness-of-god/1499302433?i=1499302437&utm_source=test");
  assert.equal(parsed.provider, "appleMusic");
  assert.equal(parsed.entityType, "song");
  assert.equal(parsed.providerID, "1499302437");
  assert.equal(parsed.storefront, "us");
  assert.match(parsed.sanitizedURL, /\?i=1499302437$/);
});

test("rejects untrusted hosts", () => {
  assert.throws(
      () => _internal.parseMusicAttachmentURL("https://example.com/track/123"),
      /Only Apple Music and Spotify/,
  );
});

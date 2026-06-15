/**
 * ingestion/providers/index.ts
 *
 * Re-exports all SourceProvider implementations.
 */

export { spotifyProvider, SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET } from "./spotifyProvider";
export { youtubeProvider, YOUTUBE_API_KEY, YOUTUBE_CLIENT_ID, YOUTUBE_CLIENT_SECRET } from "./youtubeProvider";
export { appleMusicProvider, APPLE_MUSIC_DEVELOPER_TOKEN } from "./appleMusicProvider";
export { googleBooksProvider, openLibraryProvider, GOOGLE_BOOKS_API_KEY } from "./googleBooksProvider";
export { podcastRSSProvider } from "./podcastRSSProvider";
export { substackProvider, mediumProvider } from "./substackMediumProvider";
export type { SourceProvider, Work, RawItem, AuthResult, WorkType, WorkVisibility, WorkReviewState, WorkLink } from "./types";

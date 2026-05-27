# Smart Church Search Runtime Setup

This feature builds in Xcode without client-side API keys. Runtime search still depends on server-side Firebase secrets and search indexes.

## Required Firebase secrets

Set these in the Firebase project before deploying the functions codebase:

```sh
firebase functions:secrets:set GOOGLE_MAPS_KEY
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set ANTHROPIC_API_KEY
firebase functions:secrets:set PINECONE_API_KEY
firebase functions:secrets:set ALGOLIA_ADMIN_KEY
```

The Pinecone host is read from an environment variable:

```sh
firebase functions:config:set pinecone.churches_index_host="YOUR_INDEX_HOST"
```

For Gen 2 deployments, prefer setting `PINECONE_CHURCHES_INDEX_HOST` in the function environment for the deployed service if your Firebase tooling does not project `functions:config` into `process.env`.

## Search indexes

Firestore deploy uses the root `firestore.indexes.json`. It includes the compound `churches` index used by the Firestore fallback path.

Algolia settings are configured by the admin-only callable:

```text
configureSmartChurchSearchInfrastructure
```

That callable also validates the configured Pinecone host/key by calling Pinecone index stats for the `churches-v1` namespace. It does not create a Pinecone index; create `churches-v1` with `text-embedding-3-small` dimensions before running ingestion.

## Seed and ingestion

After deploy, use an admin account to call:

```text
seedSmartChurches
```

Then run either `enrichChurchesFromPlaces` for real candidate ingestion or let claimed/manual church docs flow through `onChurchWrite`. The trigger embeds, upserts Pinecone, and syncs Algolia from Firestore as the source of truth.

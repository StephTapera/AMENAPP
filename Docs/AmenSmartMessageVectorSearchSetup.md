# Amen Smart Message Vector Search Setup

## Provider

Amen Smart Message Intelligence now supports a Firebase-native vector path:

- Vertex AI generates text embeddings from Cloud Functions.
- Firestore stores embeddings on server-owned semantic index documents.
- Firestore nearest-neighbor search ranks Space search results.
- Keyword fallback remains active and clearly labeled when vector config, Vertex AI, Firestore vector indexes, or indexed results are unavailable.

## Required Cloud Configuration

Set these environment variables for the Functions runtime:

```bash
SMART_MESSAGE_VECTOR_ENABLED=true
SMART_MESSAGE_VECTOR_PROVIDER=firestore
VERTEX_AI_LOCATION=us-central1
VERTEX_AI_EMBEDDING_MODEL=text-embedding-005
```

Optional, only if you want a specific embedding dimensionality supported by the selected model:

```bash
SMART_MESSAGE_VECTOR_DIMENSIONS=768
```

The Functions service account must have permission to call Vertex AI prediction APIs.

Current production project status:

- `aiplatform.googleapis.com` is enabled.
- `SMART_MESSAGE_VECTOR_ENABLED=true`
- `SMART_MESSAGE_VECTOR_PROVIDER=firestore`
- `VERTEX_AI_LOCATION=us-central1`
- `VERTEX_AI_EMBEDDING_MODEL=text-embedding-005`
- The runtime service account has Agent Platform access for Vertex embedding calls.

## Firestore Vector Index

Create a vector index for:

```text
spaces/{spaceId}/semanticIndex/items/items
```

Vector field:

```text
embedding
```

Distance measure:

```text
COSINE
```

Dimension must match the Vertex embedding model output, or `SMART_MESSAGE_VECTOR_DIMENSIONS` if set.

Production index created:

```text
collection group: items
field: embedding
dimension: 768
config: flat
```

## Existing Content Backfill

New Smart Message analysis, summaries, study sessions, Space-visible prayer requests, and knowledge nodes write semantic index documents as they are created.

Existing content is covered by two production paths:

- `backfillSmartMessageVectorIndex`: member-gated callable for immediate Space/thread indexing.
- `scheduledSmartMessageVectorBackfill`: scheduled Cloud Function running every 6 hours in `us-central1`, indexing bounded batches of existing Space messages, summaries, study sessions, Space-visible prayer requests, and knowledge nodes.

Status can be checked with:

```text
getSmartMessageVectorIndexStatus
```

It reports sampled semantic index items, vector-indexed count, keyword-only count, and type breakdown.

## Runtime Behavior

`semanticSearchAmenSpace` returns:

```json
{ "rankingMode": "vector" }
```

only when:

- vector mode is enabled,
- Vertex AI returns a valid embedding,
- Firestore accepts vector writes,
- Firestore nearest-neighbor search returns results.

Otherwise it returns:

```json
{ "rankingMode": "keywordFallback" }
```

No fake semantic ranking is shown.

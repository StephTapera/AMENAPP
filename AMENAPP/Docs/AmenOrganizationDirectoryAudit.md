# Amen Organization Directory + Smart Spaces Audit

## Decision

AMEN now uses an Organization Identity System instead of creating separate profile screens for every organization kind. School, university, and campus group behavior lives in organization data and modules, not a standalone `SchoolProfileView` or a separate `AMENAccountType`.

Supported organization types:
- church
- school
- university
- campusGroup
- business
- nonprofit
- ministry
- bibleStudy
- creatorCommunity
- communityGroup

## Source Strategy

Approved bulk/import sources:
- NCES CCD for public K-12 schools.
- NCES PSS for private K-12 schools.
- NCES IPEDS for higher education.
- IRS EO BMF for tax-exempt church/ministry/nonprofit candidates.
- U.S. Census Geocoder for address enrichment.
- OSM static extracts only with license-compliant attribution.
- Google Places is claim-time lookup only; persist `place_id` only.

No random scraping is part of the system.

## Implemented

Frontend:
- Added `AmenOrganizationIdentityModels.swift` with organization type/source/claim/billing/module contracts.
- Added reusable `AmenOrganizationProfileView` that renders ordered modules.
- Added Smart Notes modes including `schoolNotes`, `bibleStudyNotes`, `meetingNotes`, `sermonNotes`, `classNotes`, and `eventNotes`.
- Kept school as an organization type, not a user account type.
- Extended contextual organization types for `bibleStudy` and `communityGroup`.

Backend:
- Extended `amenNationalDirectory.ts` for source-aware directory records.
- Added callable coverage for search, claim, approve/reject, suggested edits, official space creation, banner update/moderation, school/nonprofit ingestion, dedupe, geocode placeholder, classification, checkout creation, and billing webhook handling.
- Added `opsRuns` logging for batch/geocode jobs.
- Added Google Places place-id-only guard.
- Added billing eligibility guard: only claimed/verified eligible orgs can create paid checkout records.

Rules:
- Added unified organization profile rules.
- Added national directory, claim, suggested edit, import, membership, and checkout read/write boundaries.
- Clients cannot self-import, self-verify, mutate source fields, mutate billing fields, or approve claims.

## Validation

- Xcode build passed.
- Swift focused tests passed: 3/3.
- Backend Jest tests passed: 13/13.
- Backend TypeScript typecheck passed.

## Remaining Build-Out

- Real CSV parser/import runners for NCES CCD, NCES PSS, IPEDS, and IRS EO BMF source files.
- Real Census geocoder adapter and OSM attribution display.
- Admin review UI for claims, suggested edits, and banner moderation.
- Stripe checkout URL integration using existing production Stripe proxy details.
- Algolia indexing policy and cost cap before indexing large unclaimed source universes.

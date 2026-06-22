"use strict";
// engine.ts — assembleChurchDiscovery + searchChurches + profile hydration.
//
// Server-driven, formation-weighted (ranking.ts), MMR-diversified, CalmCap-capped
// — the assembleDiscoveryFeed sibling. No client-side ranking ever. Distance is
// coarsened for approx-location churches. Media is fail-closed: only `approved`
// media refs are ever returned (§5.4).
Object.defineProperty(exports, "__esModule", { value: true });
exports.RADIUS_CLAMP_METERS = void 0;
exports.mediaSafeChurch = mediaSafeChurch;
exports.fetchCandidates = fetchCandidates;
exports.diversifyByDenomination = diversifyByDenomination;
exports.assembleChurchDiscovery = assembleChurchDiscovery;
exports.searchChurches = searchChurches;
exports.getChurchProfile = getChurchProfile;
const firestore_1 = require("firebase-admin/firestore");
const ranking_1 = require("./ranking");
Object.defineProperty(exports, "RADIUS_CLAMP_METERS", { enumerable: true, get: function () { return ranking_1.RADIUS_CLAMP_METERS; } });
const geo_1 = require("./geo");
const serviceTime_1 = require("./serviceTime");
const db = (0, firestore_1.getFirestore)();
const CANDIDATE_LIMIT = 60; // max churches hydrated per discovery call
const SUBDOC_FANOUT = 20; // churches we read events/smallGroups for
// ---------------------------------------------------------------------------
// media fail-closed projection
// ---------------------------------------------------------------------------
/** Strip any media ref whose state is not `approved` (§5.4 fail-closed). */
function mediaSafeChurch(church) {
    const safe = { ...church };
    if (safe.heroMediaState !== "approved") {
        safe.heroMediaRef = null;
    }
    return safe;
}
function mediaSafeSermon(s) {
    if (s.thumbnailMediaState !== "approved") {
        return { ...s, thumbnailMediaRef: null };
    }
    return s;
}
async function fetchCandidates(center, radiusMeters) {
    const radius = (0, geo_1.clampRadius)(radiusMeters);
    const bounds = (0, geo_1.queryBounds)(center, radius);
    const snaps = await Promise.all(bounds.map((b) => db.collection("churches")
        .orderBy("location.geohash")
        .startAt(b[0])
        .endAt(b[1])
        .limit(CANDIDATE_LIMIT)
        .get()));
    const seen = new Set();
    const out = [];
    for (const snap of snaps) {
        for (const doc of snap.docs) {
            if (seen.has(doc.id))
                continue;
            const church = doc.data();
            // HARD GATE: restricted churches are excluded from ALL results.
            if ((0, ranking_1.isExcludedByReportState)(church.reportState))
                continue;
            const loc = church.location;
            if (!loc || typeof loc.lat !== "number" || typeof loc.lng !== "number")
                continue;
            const d = (0, geo_1.distanceMeters)(center, { lat: loc.lat, lng: loc.lng });
            if (d > radius)
                continue; // geohash bounds are approximate; verify exact
            seen.add(doc.id);
            out.push({ church, distanceMeters: d });
        }
    }
    out.sort((a, b) => a.distanceMeters - b.distanceMeters);
    return out.slice(0, CANDIDATE_LIMIT);
}
async function loadServiceTimes(churchId) {
    const snap = await db.collection("churches").doc(churchId).collection("serviceTimes").get();
    return snap.docs.map((d) => d.data());
}
function buildBadges(church, verified) {
    const badges = [];
    if (verified)
        badges.push("verified");
    // kids_safe_policy requires an actual policy signal (never inferred).
    if (church.safety.hasChildSafetyPolicy ||
        church.safety.backgroundCheckPolicy === "all_volunteers" ||
        church.safety.backgroundCheckPolicy === "child_facing") {
        badges.push("kids_safe_policy");
    }
    if (church.accessibility.wheelchair || church.accessibility.hearingLoop ||
        church.accessibility.aslInterpreted) {
        badges.push("accessible");
    }
    if (church.languages.includes("es"))
        badges.push("spanish");
    return badges;
}
async function rankCandidate(c, ctx, eventCount) {
    const serviceTimes = await loadServiceTimes(c.church.id);
    const next = (0, serviceTime_1.computeNextService)(serviceTimes, ctx.nowMs);
    const features = {
        distanceMeters: c.distanceMeters,
        nextServiceMinutes: next ? next.startsInMinutes : null,
        recentEventCount: eventCount,
    };
    const { score, whyMatched } = (0, ranking_1.scoreChurch)(c.church, ctx, features);
    const verified = c.church.verification.status === "verified";
    const match = {
        churchId: c.church.id,
        distanceMeters: (0, geo_1.coarsenDistanceMeters)(c.distanceMeters, c.church.approxLocationOnly),
        score,
        whyMatched,
        nextService: next,
        openNow: (0, serviceTime_1.isOpenNow)(serviceTimes, ctx.nowMs),
        verified,
        badges: buildBadges(c.church, verified),
    };
    return { match, denomination: c.church.denomination, score, verified, nextServiceMinutes: next?.startsInMinutes ?? null };
}
// ---------------------------------------------------------------------------
// MMR diversification — no >2 consecutive same denomination (spec §4)
// ---------------------------------------------------------------------------
function diversifyByDenomination(items) {
    const sorted = [...items].sort((a, b) => b.score - a.score);
    const out = [];
    const pool = [...sorted];
    while (pool.length > 0) {
        let pickIdx = 0;
        // count trailing run of same denomination in `out`
        const lastDenom = out.length ? out[out.length - 1].denomination : null;
        let run = 0;
        for (let i = out.length - 1; i >= 0 && out[i].denomination === lastDenom; i--)
            run++;
        if (lastDenom && run >= ranking_1.MAX_CONSECUTIVE_SAME_DENOMINATION) {
            const alt = pool.findIndex((p) => p.denomination !== lastDenom);
            if (alt >= 0)
                pickIdx = alt;
        }
        out.push(pool[pickIdx]);
        pool.splice(pickIdx, 1);
    }
    return out;
}
// ---------------------------------------------------------------------------
// events / small groups (bounded fanout over nearest candidates)
// ---------------------------------------------------------------------------
async function loadEventCounts(candidates) {
    const top = candidates.slice(0, SUBDOC_FANOUT);
    const counts = new Map();
    await Promise.all(top.map(async (c) => {
        const snap = await db.collection("churches").doc(c.church.id).collection("events").limit(10).get();
        counts.set(c.church.id, snap.size);
    }));
    return counts;
}
async function buildEventMatches(candidates) {
    const top = candidates.slice(0, SUBDOC_FANOUT);
    const out = [];
    await Promise.all(top.map(async (c) => {
        const snap = await db.collection("churches").doc(c.church.id).collection("events")
            .orderBy("startsAtIso").limit(3).get();
        for (const d of snap.docs) {
            const e = d.data();
            out.push({
                eventId: e.id, churchId: c.church.id, title: e.title,
                startsAtIso: e.startsAtIso,
                distanceMeters: (0, geo_1.coarsenDistanceMeters)(c.distanceMeters, c.church.approxLocationOnly),
                kind: e.kind,
            });
        }
    }));
    return out.slice(0, ranking_1.CALM_CAP.maxItemsPerSection);
}
async function buildSmallGroupMatches(candidates) {
    const top = candidates.slice(0, SUBDOC_FANOUT);
    const out = [];
    await Promise.all(top.map(async (c) => {
        const snap = await db.collection("churches").doc(c.church.id).collection("smallGroups").limit(3).get();
        for (const d of snap.docs) {
            const g = d.data();
            out.push({
                groupId: g.id, churchId: c.church.id, title: g.title, type: g.type,
                distanceMeters: (0, geo_1.coarsenDistanceMeters)(c.distanceMeters, c.church.approxLocationOnly),
                meetsLabel: g.meetsLabel,
            });
        }
    }));
    return out.slice(0, ranking_1.CALM_CAP.maxItemsPerSection);
}
async function buildGuides(candidateIds) {
    const snap = await db.collection("churchGuides").limit(20).get();
    const out = [];
    for (const d of snap.docs) {
        const g = d.data();
        if (!g.churchIds?.some((id) => candidateIds.has(id)))
            continue;
        out.push({
            id: g.id, title: g.title, subtitle: g.subtitle,
            // fail-closed: only serve an approved cover ref.
            coverMediaRef: g.coverMediaState === "approved" ? g.coverMediaRef ?? null : null,
            churchIds: g.churchIds, source: g.source,
        });
        if (out.length >= ranking_1.CALM_CAP.maxItemsPerSection)
            break;
    }
    return out;
}
// ---------------------------------------------------------------------------
// filters
// ---------------------------------------------------------------------------
function passesFilters(r, church, filters) {
    for (const f of filters) {
        switch (f.key) {
            case "verified":
                if (!r.verified)
                    return false;
                break;
            case "accessible":
                if (!(church.accessibility.wheelchair || church.accessibility.hearingLoop ||
                    church.accessibility.aslInterpreted))
                    return false;
                break;
            case "spanish_service":
                if (!church.languages.includes("es"))
                    return false;
                break;
            case "denomination":
                if (f.value && church.denomination !== f.value)
                    return false;
                break;
            case "non_denominational":
                if (church.denomination !== "non_denominational")
                    return false;
                break;
            case "kids":
                if (!church.ministries.includes("kids"))
                    return false;
                break;
            case "youth":
                if (!church.ministries.includes("youth"))
                    return false;
                break;
            case "young_adults":
                if (!church.ministries.includes("young_adults"))
                    return false;
                break;
            case "counseling":
                if (!church.ministries.includes("counseling"))
                    return false;
                break;
            case "service_today":
                if (r.nextServiceMinutes == null || r.nextServiceMinutes > 18 * 60)
                    return false;
                break;
            default: break; // other filters narrow sections, not the candidate set
        }
    }
    return true;
}
// ---------------------------------------------------------------------------
// assembleChurchDiscovery
// ---------------------------------------------------------------------------
async function assembleChurchDiscovery(req, ctx) {
    const center = ctx.center;
    const candidates = await fetchCandidates(center, ctx.radiusMeters);
    const candidateById = new Map(candidates.map((c) => [c.church.id, c.church]));
    const candidateIds = new Set(candidateById.keys());
    const eventCounts = await loadEventCounts(candidates);
    const ranked = await Promise.all(candidates.map((c) => rankCandidate(c, ctx, eventCounts.get(c.church.id) ?? 0)));
    const filtered = ranked.filter((r) => passesFilters(r, candidateById.get(r.match.churchId), req.filters));
    const diversified = diversifyByDenomination(filtered);
    const nearby = diversified.slice(0, ranking_1.CALM_CAP.maxItemsPerSection).map((r) => r.match);
    const servicesToday = diversified
        .filter((r) => r.nextServiceMinutes != null && r.nextServiceMinutes <= 18 * 60)
        .slice(0, ranking_1.CALM_CAP.maxItemsPerSection)
        .map((r) => r.match);
    // suggested: VERIFIED ONLY (suggestions imply endorsement) — spec §4.
    const suggested = diversifyByDenomination(filtered.filter((r) => (0, ranking_1.isEligibleForSuggested)(candidateById.get(r.match.churchId))))
        .slice(0, ranking_1.CALM_CAP.maxItemsPerSection)
        .map((r) => r.match);
    const [events, smallGroups, guides] = await Promise.all([
        buildEventMatches(candidates),
        buildSmallGroupMatches(candidates),
        buildGuides(candidateIds),
    ]);
    const sections = [];
    if (nearby.length)
        sections.push({ kind: "nearby", items: nearby });
    if (servicesToday.length)
        sections.push({ kind: "services_today", items: servicesToday });
    if (suggested.length)
        sections.push({ kind: "suggested", items: suggested });
    if (smallGroups.length)
        sections.push({ kind: "small_groups", items: smallGroups });
    if (events.length)
        sections.push({ kind: "events", items: events });
    if (guides.length)
        sections.push({ kind: "guides", items: guides });
    const soonCount = servicesToday.length;
    const contextChip = nearby.length
        ? {
            dayLabel: new Intl.DateTimeFormat("en-US", { weekday: "long" }).format(new Date(ctx.nowMs)),
            soonCount,
            radiusLabel: `${Math.round((0, geo_1.clampRadius)(ctx.radiusMeters) / 1609.344)} mi`,
        }
        : null;
    return {
        contextChip,
        sections,
        calmCap: { maxItemsPerSection: ranking_1.CALM_CAP.maxItemsPerSection, infiniteScroll: false },
    };
}
// ---------------------------------------------------------------------------
// searchChurches (paginated text search over geo candidates)
// ---------------------------------------------------------------------------
const SEARCH_PAGE_SIZE = 20;
async function searchChurches(q, center, radiusMeters, filters, page, ctx) {
    const term = q.trim().toLowerCase();
    const candidates = await fetchCandidates(center, radiusMeters);
    const candidateById = new Map(candidates.map((c) => [c.church.id, c.church]));
    const matchedCandidates = term
        ? candidates.filter((c) => c.church.name.toLowerCase().includes(term))
        : candidates;
    const eventCounts = await loadEventCounts(matchedCandidates);
    const ranked = await Promise.all(matchedCandidates.map((c) => rankCandidate(c, ctx, eventCounts.get(c.church.id) ?? 0)));
    const filtered = ranked
        .filter((r) => passesFilters(r, candidateById.get(r.match.churchId), filters))
        .sort((a, b) => b.score - a.score);
    const start = Math.max(0, page) * SEARCH_PAGE_SIZE;
    const slice = filtered.slice(start, start + SEARCH_PAGE_SIZE);
    const nextPage = start + SEARCH_PAGE_SIZE < filtered.length ? page + 1 : null;
    return { items: slice.map((r) => r.match), nextPage };
}
// ---------------------------------------------------------------------------
// getChurchProfile (hydrated, media fail-closed)
// ---------------------------------------------------------------------------
async function getChurchProfile(churchId) {
    const ref = db.collection("churches").doc(churchId);
    const [churchSnap, stSnap, minSnap, evSnap, serSnap] = await Promise.all([
        ref.get(),
        ref.collection("serviceTimes").get(),
        ref.collection("ministries").get(),
        ref.collection("events").orderBy("startsAtIso").limit(10).get(),
        ref.collection("sermons").orderBy("createdAt", "desc").limit(10).get(),
    ]);
    if (!churchSnap.exists) {
        throw new Error("not-found");
    }
    const church = mediaSafeChurch(churchSnap.data());
    if ((0, ranking_1.isExcludedByReportState)(church.reportState)) {
        throw new Error("not-found"); // restricted churches are not browseable
    }
    return {
        church,
        serviceTimes: stSnap.docs.map((d) => d.data()),
        ministries: minSnap.docs.map((d) => d.data()),
        upcomingEvents: evSnap.docs.map((d) => d.data()),
        sermons: serSnap.docs.map((d) => mediaSafeSermon(d.data())),
    };
}

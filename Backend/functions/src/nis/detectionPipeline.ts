/**
 * nis/detectionPipeline.ts
 * AMEN — Notes Intelligence System (NIS) Wave 1 Lane B
 *
 * runDetectionPipeline: reads a note, runs regex detectors, calls scripture-
 * quote deep path, deduplicates, writes detections + graph edges, updates
 * the note's nis metadata.
 *
 * Exported surface: runDetectionPipeline
 * Contracts frozen at tag nis-contracts-v1; do not change type shapes.
 */

import * as admin from "firebase-admin";
import { nisDetectScriptureQuote } from "./scriptureQuoteDetector";

const db = admin.firestore();

// ---------------------------------------------------------------------------
// CONTRACT TYPES (frozen — nis-contracts-v1)
// ---------------------------------------------------------------------------

export interface NISDetectionSpan {
    blockId: string;
    start: number;
    end: number;
}

export interface NISDetection {
    id: string;
    type: "scriptureRef" | "prayer" | "action" | "scriptureQuote";
    span?: NISDetectionSpan;
    payload: Record<string, unknown>;
    confidence: number;
    status: "proposed";
    source: "serverPipeline";
    createdAt: admin.firestore.FieldValue;
}

// ---------------------------------------------------------------------------
// SCRIPTURE REF DETECTOR
// Matches patterns: John 3:16, Genesis 1:1-3, 1 Cor 13:4, Psalm 23
// ---------------------------------------------------------------------------

const BIBLE_BOOK_PATTERN =
    // numbered books first (1/2/3 prefix)
    "(?:1|2|3)\\s*(?:Samuel|Kings|Chronicles|Corinthians|Thessalonians|Timothy|Peter|John|Maccabees)|" +
    // common abbreviations and full names (single-word books)
    "Genesis|Exodus|Leviticus|Numbers|Deuteronomy|Joshua|Judges|Ruth|" +
    "(?:1|2)\\s*(?:Sam(?:uel)?|Ki(?:ngs)?|Chr(?:on)?|Cor(?:inthians)?|Thess(?:alonians)?|Tim(?:othy)?|Pet(?:er)?)|" +
    "Ezra|Nehemiah|Esther|Job|Psalms?|Proverbs|Ecclesiastes|" +
    "Song\\s+of\\s+(?:Solomon|Songs?)|Isaiah|Jeremiah|Lamentations|Ezekiel|Daniel|" +
    "Hosea|Joel|Amos|Obadiah|Jonah|Micah|Nahum|Habakkuk|Zephaniah|Haggai|Zechariah|Malachi|" +
    "Matthew|Mark|Luke|John|Acts|Romans|Galatians|Ephesians|Philippians|Colossians|" +
    "Philemon|Hebrews|James|Jude|Revelation|" +
    // common abbreviations
    "Gen|Ex(?:od)?|Lev|Num|Deut?|Josh?|Judg?|Ps(?:alm)?|Prov?|Ecc?l?|Isa|Jer|Lam|Eze?k?|Dan|" +
    "Hos|Oba?d?|Jon|Mic|Nah|Hab|Zeph?|Hag|Zech?|Mal|Matt?|Mk|Lk|Jn|Rom|Gal|Eph|Phil|Col|" +
    "Heb|Jas|Rev|1\\s*Jn|2\\s*Jn|3\\s*Jn|1\\s*Cor|2\\s*Cor";

const SCRIPTURE_REF_REGEX = new RegExp(
    `\\b(${BIBLE_BOOK_PATTERN})\\s+(\\d+)(?::(\\d+)(?:[–\\-](\\d+))?)?\\b`,
    "gi"
);

export function detectScriptureRefs(
    text: string,
    blockId: string
): NISDetection[] {
    const results: NISDetection[] = [];
    // Reset lastIndex since regex is global
    SCRIPTURE_REF_REGEX.lastIndex = 0;
    let match: RegExpExecArray | null;

    while ((match = SCRIPTURE_REF_REGEX.exec(text)) !== null) {
        const [fullMatch, book, chapter, verseStart, verseEnd] = match;
        const start = match.index;
        const end = start + fullMatch.length;

        results.push({
            id: db.collection("_tmp").doc().id,
            type: "scriptureRef",
            span: { blockId, start, end },
            payload: {
                book: book.trim(),
                chapter: parseInt(chapter, 10),
                verseStart: verseStart ? parseInt(verseStart, 10) : null,
                verseEnd: verseEnd ? parseInt(verseEnd, 10) : null,
                refText: fullMatch.trim(),
            },
            confidence: 0.92,
            status: "proposed",
            source: "serverPipeline",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    return results;
}

// ---------------------------------------------------------------------------
// PRAYER PATTERN DETECTOR
// Matches prayer phrases: "pray for", "Lord help", "Father God", etc.
// ---------------------------------------------------------------------------

const PRAYER_PHRASES = [
    /pray(?:ing|er)?(?:\s+for)?/i,
    /lord\s+help/i,
    /father\s+god/i,
    /heavenly\s+father/i,
    /dear\s+(?:lord|god|jesus|father)/i,
    /i\s+ask\s+(?:you|god|lord|jesus)/i,
    /please\s+bless/i,
    /bless\s+(?:me|us|him|her|them|lord)/i,
    /in\s+jesus(?:'s?)?\s+name/i,
    /lord\s+(?:i|we)\s+(?:ask|pray|thank|praise)/i,
    /god\s+(?:i|we)\s+(?:ask|pray|thank|praise)/i,
    /help\s+(?:me|us)\s+(?:lord|god)/i,
    /(?:i|we)\s+pray/i,
    /guide\s+(?:me|us|my|our)/i,
    /give\s+(?:me|us)\s+(?:strength|wisdom|peace|grace)/i,
    /protect\s+(?:me|us|him|her|them)/i,
    /have\s+mercy/i,
    /your\s+will\s+be\s+done/i,
    /amen\b/i,
];

// Split text into sentences for prayer detection
function splitIntoSentences(text: string): string[] {
    return text
        .split(/(?<=[.!?])\s+|(?<=\n)/)
        .map((s) => s.trim())
        .filter((s) => s.length > 0);
}

export function detectPrayerPatterns(
    text: string,
    blockId: string
): NISDetection[] {
    const results: NISDetection[] = [];
    const sentences = splitIntoSentences(text);

    for (const sentence of sentences) {
        for (const pattern of PRAYER_PHRASES) {
            const m = pattern.exec(sentence);
            if (m) {
                const start = text.indexOf(sentence);
                const end = start >= 0 ? start + sentence.length : -1;

                results.push({
                    id: db.collection("_tmp").doc().id,
                    type: "prayer",
                    span:
                        start >= 0
                            ? { blockId, start, end }
                            : undefined,
                    payload: {
                        rawText: sentence,
                        matchedPhrase: m[0],
                    },
                    confidence: 0.82,
                    status: "proposed",
                    source: "serverPipeline",
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                break; // one detection per sentence
            }
        }
    }

    return results;
}

// ---------------------------------------------------------------------------
// ACTION ITEM DETECTOR
// Matches action phrases: "I will", "I need to", "remember to", etc.
// ---------------------------------------------------------------------------

const ACTION_PHRASES = [
    /\bi\s+will\b/i,
    /\bi\s+need\s+to\b/i,
    /\bi\s+should\b/i,
    /\bi\s+must\b/i,
    /\bremember\s+to\b/i,
    /\bdon'?t\s+forget\s+to\b/i,
    /\bthis\s+week\s*:/i,
    /\bnext\s+step\s*[:\-]/i,
    /\btodo\s*[:\-]/i,
    /\bto[\s-]do\s*[:\-]/i,
    /\baction\s+(?:item|step)\s*[:\-]/i,
    /\bfollow[\s-]up\s*[:\-]/i,
    /\bfollow\s+up\s+(?:with|on)\b/i,
    /\bschedule\b/i,
    /\bset\s+a\s+(?:reminder|date|time)\b/i,
    /\bcommit\s+to\b/i,
    /\bplan\s+to\b/i,
    /\bintend\s+to\b/i,
    /\bgoal\s*[:\-]/i,
    /\bstep\s+\d+\s*[:\-]/i,
];

export function detectActionItems(
    text: string,
    blockId: string
): NISDetection[] {
    const results: NISDetection[] = [];
    const sentences = splitIntoSentences(text);

    for (const sentence of sentences) {
        for (const pattern of ACTION_PHRASES) {
            const m = pattern.exec(sentence);
            if (m) {
                const start = text.indexOf(sentence);
                const end = start >= 0 ? start + sentence.length : -1;

                results.push({
                    id: db.collection("_tmp").doc().id,
                    type: "action",
                    span:
                        start >= 0
                            ? { blockId, start, end }
                            : undefined,
                    payload: {
                        rawText: sentence,
                        matchedPhrase: m[0],
                    },
                    confidence: 0.78,
                    status: "proposed",
                    source: "serverPipeline",
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                break; // one detection per sentence
            }
        }
    }

    return results;
}

// ---------------------------------------------------------------------------
// DEDUPLICATION
// Same type + overlapping or identical span → keep highest confidence.
// ---------------------------------------------------------------------------

function detectionsOverlap(a: NISDetection, b: NISDetection): boolean {
    if (a.type !== b.type) return false;
    if (!a.span || !b.span) {
        // If no span, deduplicate by rawText / refText
        const aKey = JSON.stringify(a.payload);
        const bKey = JSON.stringify(b.payload);
        return aKey === bKey;
    }
    if (a.span.blockId !== b.span.blockId) return false;
    // Overlapping if not (a ends before b starts or b ends before a starts)
    return !(a.span.end <= b.span.start || b.span.end <= a.span.start);
}

function deduplicateDetections(detections: NISDetection[]): NISDetection[] {
    const kept: NISDetection[] = [];

    for (const candidate of detections) {
        let dominated = false;
        for (let i = 0; i < kept.length; i++) {
            if (detectionsOverlap(candidate, kept[i])) {
                if (candidate.confidence > kept[i].confidence) {
                    // Replace the existing one
                    kept[i] = candidate;
                }
                dominated = true;
                break;
            }
        }
        if (!dominated) {
            kept.push(candidate);
        }
    }

    return kept;
}

// ---------------------------------------------------------------------------
// MAIN PIPELINE
// ---------------------------------------------------------------------------

interface NoteBlock {
    type?: string;
    text?: string;
    id?: string;
}

interface NoteData {
    uid?: string;
    blocks?: NoteBlock[];
    body?: string;
    nis?: Record<string, unknown>;
    [key: string]: unknown;
}

export async function runDetectionPipeline(
    noteId: string,
    data: NoteData
): Promise<void> {
    const uid = data.uid;
    if (!uid) {
        console.warn(`[NIS] nisProcessNote: note ${noteId} has no uid — skipping.`);
        return;
    }

    // Step 3: Extract text from blocks or body
    const blocks: Array<{ blockId: string; text: string }> = [];

    if (Array.isArray(data.blocks) && data.blocks.length > 0) {
        for (let i = 0; i < data.blocks.length; i++) {
            const block = data.blocks[i];
            const text = block.text ?? "";
            if (text.trim()) {
                blocks.push({
                    blockId: block.id ?? `block_${i}`,
                    text,
                });
            }
        }
    } else if (typeof data.body === "string" && data.body.trim()) {
        blocks.push({ blockId: "body", text: data.body });
    }

    if (blocks.length === 0) {
        // Nothing to detect — still update metadata
        await db.doc(`notes/${noteId}`).set(
            {
                nis: {
                    lastProcessedAt: admin.firestore.FieldValue.serverTimestamp(),
                    detectionCount: 0,
                    pipelineVersion: "1.0.0",
                },
            },
            { merge: true }
        );
        return;
    }

    // Step 4: Run regex detectors on each block
    let allDetections: NISDetection[] = [];

    for (const { blockId, text } of blocks) {
        allDetections = allDetections.concat(
            detectScriptureRefs(text, blockId),
            detectPrayerPatterns(text, blockId),
            detectActionItems(text, blockId)
        );
    }

    // Step 5: Call scripture quote detector
    const sentences = blocks.flatMap(({ text }) => splitIntoSentences(text));
    const quoteMatches = await nisDetectScriptureQuote(sentences, noteId);

    for (const match of quoteMatches) {
        allDetections.push({
            id: db.collection("_tmp").doc().id,
            type: "scriptureQuote",
            payload: {
                sentence: match.sentence,
                verseId: match.verseId,
                score: match.score,
            },
            confidence: match.score,
            status: "proposed",
            source: "serverPipeline",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    // Step 6: Deduplicate
    const deduplicated = deduplicateDetections(allDetections);

    // Step 7 & 8: Write detections + graph edges in a batch
    const batch = db.batch();

    for (const detection of deduplicated) {
        // Assign a fresh Firestore doc ID for each detection
        const detectionRef = db
            .collection("notes")
            .doc(noteId)
            .collection("detections")
            .doc();
        const detectionWithId: NISDetection = { ...detection, id: detectionRef.id };
        batch.set(detectionRef, detectionWithId);

        // Step 8: For scriptureRef detections, write a knowledge-graph edge
        if (detection.type === "scriptureRef") {
            const payload = detection.payload as {
                book: string;
                chapter: number;
                verseStart: number | null;
                refText: string;
            };
            const nodeId = [
                payload.book.replace(/\s+/g, ""),
                payload.chapter,
                payload.verseStart ?? "0",
            ].join(".");

            const edgeRef = db
                .collection("users")
                .doc(uid)
                .collection("graphEdges")
                .doc();
            batch.set(edgeRef, {
                from: { type: "note", nodeId },
                to: {
                    type: "scripture",
                    nodeId,
                    label: payload.refText,
                },
                weight: detection.confidence,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                sourceNoteId: noteId,
            });
        }
    }

    await batch.commit();

    // Step 9: Update note nis metadata
    await db.doc(`notes/${noteId}`).set(
        {
            nis: {
                lastProcessedAt: admin.firestore.FieldValue.serverTimestamp(),
                detectionCount: deduplicated.length,
                pipelineVersion: "1.0.0",
            },
        },
        { merge: true }
    );

    console.log(
        `[NIS] nisProcessNote: note=${noteId} uid=${uid} detections=${deduplicated.length}`
    );
}

// Re-export splitIntoSentences so it can be used internally by the pipeline
// when constructing sentence arrays for the quote detector.
export { splitIntoSentences };

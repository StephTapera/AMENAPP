import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

const REGION = "us-central1";

function requireAdmin(request: { auth?: { token?: Record<string, unknown> } }): void {
    if (request.auth?.token?.admin !== true) {
        throw new HttpsError("permission-denied", "Admin privileges required.");
    }
}

// ─── Seed church docs (St. Louis metro / Overland MO area) ──────────────────
// 10 realistic churches spanning denominations, sizes, worship styles, and
// languages. These provide enough diversity for semantic search testing before
// Google Places ingestion is run.

interface SeedChurch {
    id: string;
    name: string;
    address: string;
    city: string;
    state: string;
    zip: string;
    location: { lat: number; lng: number };
    denomination: string;
    denominationFamily: string;
    worshipStyles: string[];
    ministries: string[];
    size: string;
    serviceTimes: Array<{ day: string; time: string; language: string; type: string }>;
    languages: string[];
    statementOfFaith: string;
    doctrinalTags: string[];
    description: string;
    website: string | null;
    phone: string | null;
    email: string | null;
    photos: string[];
    googlePlaceId: string | null;
    source: string;
    claimed: boolean;
    embeddingVersion: number;
}

const SEED_CHURCHES: SeedChurch[] = [
    {
        id: "stl_seed_001",
        name: "Crossroads Community Church",
        address: "9900 Lackland Rd, Overland, MO 63114",
        city: "Overland",
        state: "MO",
        zip: "63114",
        location: { lat: 38.7066, lng: -90.3754 },
        denomination: "Non-denominational",
        denominationFamily: "Evangelical",
        worshipStyles: ["contemporary", "charismatic"],
        ministries: ["young_adults", "kids", "missions", "recovery"],
        size: "large",
        serviceTimes: [
            { day: "Sunday", time: "9:00 AM", language: "English", type: "main" },
            { day: "Sunday", time: "11:00 AM", language: "English", type: "main" },
            { day: "Wednesday", time: "7:00 PM", language: "English", type: "midweek" },
        ],
        languages: ["English"],
        statementOfFaith: "We believe in the Trinity, the authority of Scripture, salvation by grace through faith, and the ongoing work of the Holy Spirit.",
        doctrinalTags: ["trinitarian", "evangelical", "continuationist", "biblical_inerrancy"],
        description: "A Spirit-filled, non-denominational church passionate about seeing the St. Louis area transformed by the gospel. Known for energetic worship, a thriving young-adults ministry, and community outreach.",
        website: "https://crossroadsstl.com",
        phone: "(314) 555-0101",
        email: "info@crossroadsstl.com",
        photos: [],
        googlePlaceId: null,
        source: "manual",
        claimed: false,
        embeddingVersion: 0,
    },
    {
        id: "stl_seed_002",
        name: "St. Louis Family Church",
        address: "1 Family Way, Chesterfield, MO 63017",
        city: "Chesterfield",
        state: "MO",
        zip: "63017",
        location: { lat: 38.6631, lng: -90.5771 },
        denomination: "Non-denominational",
        denominationFamily: "Evangelical",
        worshipStyles: ["contemporary"],
        ministries: ["kids", "youth", "young_adults", "marriage", "seniors"],
        size: "mega",
        serviceTimes: [
            { day: "Saturday", time: "5:30 PM", language: "English", type: "main" },
            { day: "Sunday", time: "8:30 AM", language: "English", type: "main" },
            { day: "Sunday", time: "10:00 AM", language: "English", type: "main" },
            { day: "Sunday", time: "11:30 AM", language: "English", type: "main" },
        ],
        languages: ["English"],
        statementOfFaith: "We believe in the Bible as God's inspired Word, in the Trinity, and that Jesus Christ is the only way to salvation.",
        doctrinalTags: ["trinitarian", "evangelical", "biblical_inerrancy", "cessationist"],
        description: "One of the largest churches in the St. Louis region. Known for excellence in children's ministry, engaging weekend services, and a robust small-groups network serving every life stage.",
        website: "https://stlfamily.com",
        phone: "(636) 555-0202",
        email: null,
        photos: [],
        googlePlaceId: null,
        source: "manual",
        claimed: false,
        embeddingVersion: 0,
    },
    {
        id: "stl_seed_003",
        name: "Grace Presbyterian Church",
        address: "1234 Olive Blvd, Creve Coeur, MO 63141",
        city: "Creve Coeur",
        state: "MO",
        zip: "63141",
        location: { lat: 38.6609, lng: -90.4507 },
        denomination: "Presbyterian",
        denominationFamily: "Reformed",
        worshipStyles: ["traditional", "blended"],
        ministries: ["youth", "kids", "seniors", "missions", "women", "men"],
        size: "medium",
        serviceTimes: [
            { day: "Sunday", time: "9:15 AM", language: "English", type: "main" },
            { day: "Sunday", time: "11:00 AM", language: "English", type: "main" },
        ],
        languages: ["English"],
        statementOfFaith: "We confess the Westminster Standards. We hold to the authority of Scripture, the doctrines of grace, covenant theology, and the historic creeds of the Church.",
        doctrinalTags: ["reformed", "trinitarian", "nicene_orthodox", "paedobaptism", "cessationist", "biblical_inerrancy"],
        description: "A confessional PCA congregation committed to expository preaching, historic Reformed worship, and deep community. Strong adult Sunday school, missions support, and multigenerational fellowship.",
        website: "https://gracepresbyterianstl.org",
        phone: "(314) 555-0303",
        email: "office@gracepresbyterianstl.org",
        photos: [],
        googlePlaceId: null,
        source: "manual",
        claimed: false,
        embeddingVersion: 0,
    },
    {
        id: "stl_seed_004",
        name: "New Life Apostolic Church",
        address: "5800 Natural Bridge Ave, St. Louis, MO 63120",
        city: "St. Louis",
        state: "MO",
        zip: "63120",
        location: { lat: 38.6905, lng: -90.2830 },
        denomination: "Pentecostal",
        denominationFamily: "Pentecostal",
        worshipStyles: ["charismatic", "contemporary"],
        ministries: ["youth", "young_adults", "women", "recovery", "missions"],
        size: "medium",
        serviceTimes: [
            { day: "Sunday", time: "10:00 AM", language: "English", type: "main" },
            { day: "Sunday", time: "6:00 PM", language: "English", type: "evening" },
            { day: "Friday", time: "7:30 PM", language: "English", type: "prayer" },
        ],
        languages: ["English"],
        statementOfFaith: "We believe in the full gospel, the baptism of the Holy Spirit with evidence of speaking in tongues, divine healing, and the imminent return of Christ.",
        doctrinalTags: ["pentecostal", "trinitarian", "continuationist", "charismatic", "credobaptism"],
        description: "A Spirit-filled Pentecostal congregation in North St. Louis with deep roots in the community. Passionate worship, powerful prayer nights, and a heart for urban missions and youth.",
        website: null,
        phone: "(314) 555-0404",
        email: null,
        photos: [],
        googlePlaceId: null,
        source: "manual",
        claimed: false,
        embeddingVersion: 0,
    },
    {
        id: "stl_seed_005",
        name: "Immanuel Lutheran Church",
        address: "2840 Sutton Blvd, Maplewood, MO 63143",
        city: "Maplewood",
        state: "MO",
        zip: "63143",
        location: { lat: 38.6101, lng: -90.3316 },
        denomination: "Lutheran",
        denominationFamily: "Lutheran",
        worshipStyles: ["liturgical", "traditional"],
        ministries: ["youth", "kids", "seniors", "women", "men", "missions"],
        size: "small",
        serviceTimes: [
            { day: "Sunday", time: "8:00 AM", language: "English", type: "traditional" },
            { day: "Sunday", time: "10:30 AM", language: "English", type: "contemporary" },
        ],
        languages: ["English"],
        statementOfFaith: "We confess all the canonical books of the Bible as the inspired and inerrant Word of God, and we subscribe to the Lutheran Confessions as a true exposition of Scripture.",
        doctrinalTags: ["trinitarian", "nicene_orthodox", "sacramental", "paedobaptism", "biblical_inerrancy"],
        description: "An LCMS congregation offering reverent liturgical worship and warm community. Strong in classical Christian education, a historic choir program, and serving Maplewood through a neighborhood food pantry.",
        website: "https://immanuelstl.org",
        phone: "(314) 555-0505",
        email: "immanuel@immanuelstl.org",
        photos: [],
        googlePlaceId: null,
        source: "manual",
        claimed: false,
        embeddingVersion: 0,
    },
    {
        id: "stl_seed_006",
        name: "The Gathering Church",
        address: "3215 Laclede Ave, St. Louis, MO 63103",
        city: "St. Louis",
        state: "MO",
        zip: "63103",
        location: { lat: 38.6377, lng: -90.2445 },
        denomination: "Non-denominational",
        denominationFamily: "Evangelical",
        worshipStyles: ["contemporary"],
        ministries: ["young_adults", "college", "recovery", "missions"],
        size: "small",
        serviceTimes: [
            { day: "Sunday", time: "5:00 PM", language: "English", type: "main" },
        ],
        languages: ["English"],
        statementOfFaith: "We believe in the authority of Scripture, the Trinity, and that every person matters to God. We welcome doubters, seekers, and those who've been hurt by church.",
        doctrinalTags: ["trinitarian", "evangelical", "missional", "non_denominational"],
        description: "A small, neighborhood church in Midtown St. Louis meeting Sunday evenings. Known for honest community, a radical welcome policy, strong recovery programs, and deep care for college students and young professionals.",
        website: "https://gatheringstl.com",
        phone: "(314) 555-0606",
        email: null,
        photos: [],
        googlePlaceId: null,
        source: "manual",
        claimed: false,
        embeddingVersion: 0,
    },
    {
        id: "stl_seed_007",
        name: "Epiphany United Church of Christ",
        address: "6901 Delmar Blvd, University City, MO 63130",
        city: "University City",
        state: "MO",
        zip: "63130",
        location: { lat: 38.6604, lng: -90.3090 },
        denomination: "United Church of Christ",
        denominationFamily: "Protestant",
        worshipStyles: ["blended", "traditional"],
        ministries: ["seniors", "women", "missions", "youth"],
        size: "small",
        serviceTimes: [
            { day: "Sunday", time: "10:30 AM", language: "English", type: "main" },
        ],
        languages: ["English"],
        statementOfFaith: "We are an open and affirming congregation committed to justice, the way of Jesus, and the radical hospitality of the Gospel.",
        doctrinalTags: ["trinitarian", "missional", "egalitarian"],
        description: "A welcoming, progressive UCC congregation in the Delmar Loop neighborhood. Passionate about social justice, creation care, and interfaith dialogue while maintaining a Christ-centered identity.",
        website: "https://epiphanystl.org",
        phone: "(314) 555-0707",
        email: null,
        photos: [],
        googlePlaceId: null,
        source: "manual",
        claimed: false,
        embeddingVersion: 0,
    },
    {
        id: "stl_seed_008",
        name: "Iglesia Bautista Emanuel",
        address: "4502 Gravois Ave, St. Louis, MO 63116",
        city: "St. Louis",
        state: "MO",
        zip: "63116",
        location: { lat: 38.5900, lng: -90.2620 },
        denomination: "Baptist",
        denominationFamily: "Baptist",
        worshipStyles: ["contemporary", "traditional"],
        ministries: ["youth", "kids", "women", "missions", "seniors"],
        size: "medium",
        serviceTimes: [
            { day: "Sunday", time: "11:00 AM", language: "Spanish", type: "main" },
            { day: "Sunday", time: "6:00 PM", language: "English", type: "bilingual" },
            { day: "Wednesday", time: "7:00 PM", language: "Spanish", type: "midweek" },
        ],
        languages: ["Spanish", "English"],
        statementOfFaith: "Creemos en la Biblia como la Palabra de Dios, en la Trinidad, y en la salvación por gracia mediante la fe en Jesucristo.",
        doctrinalTags: ["trinitarian", "baptist", "evangelical", "credobaptism", "biblical_inerrancy"],
        description: "A bilingual Spanish-English Baptist church serving the Hispanic community of South St. Louis. Warm, multigenerational family atmosphere with strong youth programming and community service.",
        website: null,
        phone: "(314) 555-0808",
        email: null,
        photos: [],
        googlePlaceId: null,
        source: "manual",
        claimed: false,
        embeddingVersion: 0,
    },
    {
        id: "stl_seed_009",
        name: "Grace Fellowship Church",
        address: "10765 Dielman Rock Island, Overland, MO 63114",
        city: "Overland",
        state: "MO",
        zip: "63114",
        location: { lat: 38.7100, lng: -90.3810 },
        denomination: "Baptist",
        denominationFamily: "Evangelical",
        worshipStyles: ["contemporary", "blended"],
        ministries: ["youth", "kids", "young_adults", "men", "women", "missions", "marriage"],
        size: "large",
        serviceTimes: [
            { day: "Sunday", time: "9:00 AM", language: "English", type: "main" },
            { day: "Sunday", time: "11:00 AM", language: "English", type: "main" },
        ],
        languages: ["English"],
        statementOfFaith: "We believe in the verbal, plenary inspiration of all 66 books of Scripture, the Trinity, salvation by grace alone through faith alone in Christ alone, and the importance of believers baptism.",
        doctrinalTags: ["trinitarian", "baptist", "evangelical", "credobaptism", "cessationist", "biblical_inerrancy"],
        description: "A growing Southern Baptist congregation in Overland with exceptional kids and youth programs, a busy small-groups calendar, and a passion for international missions. Family-friendly and multigenerational.",
        website: "https://gracefellowshipstl.org",
        phone: "(314) 555-0909",
        email: "office@gracefellowshipstl.org",
        photos: [],
        googlePlaceId: null,
        source: "manual",
        claimed: false,
        embeddingVersion: 0,
    },
    {
        id: "stl_seed_010",
        name: "Life Church St. Louis",
        address: "2720 Hampton Ave, St. Louis, MO 63139",
        city: "St. Louis",
        state: "MO",
        zip: "63139",
        location: { lat: 38.5981, lng: -90.3011 },
        denomination: "Assemblies of God",
        denominationFamily: "Pentecostal",
        worshipStyles: ["charismatic", "contemporary"],
        ministries: ["young_adults", "college", "youth", "kids", "recovery", "women"],
        size: "medium",
        serviceTimes: [
            { day: "Sunday", time: "10:30 AM", language: "English", type: "main" },
            { day: "Thursday", time: "7:00 PM", language: "English", type: "young_adults" },
        ],
        languages: ["English"],
        statementOfFaith: "We are an Assemblies of God church. We believe in Scripture as our final authority, salvation through Christ, water baptism, and the baptism of the Holy Spirit as a distinct experience subsequent to salvation.",
        doctrinalTags: ["pentecostal", "trinitarian", "continuationist", "charismatic", "credobaptism", "evangelical"],
        description: "A charismatic Assemblies of God church in South St. Louis City. Known for a Thursday-night young-adults gathering that draws college students from SLU and WashU, expressive worship, and strong discipleship pathways.",
        website: "https://lifechurchstl.com",
        phone: "(314) 555-1010",
        email: null,
        photos: [],
        googlePlaceId: null,
        source: "manual",
        claimed: false,
        embeddingVersion: 0,
    },
];

// ─── seedChurchData callable ─────────────────────────────────────────────────
// Admin-only callable: writes all seed churches to Firestore. Run once per env.
// Re-running is safe (merge: true). The onChurchWrite trigger fires after each
// write and will embed + index each doc automatically.

export const seedChurchData = onCall(
    {
        region: REGION,
        enforceAppCheck: true,
        timeoutSeconds: 120,
        memory: "512MiB",
    },
    async (request) => {
        requireAdmin(request);
        const firestore = admin.firestore();
        const batch = firestore.batch();
        const now = admin.firestore.FieldValue.serverTimestamp();
        let count = 0;
        for (const church of SEED_CHURCHES) {
            const ref = firestore.collection("churches").doc(church.id);
            batch.set(ref, {
                ...church,
                geoPoint: new admin.firestore.GeoPoint(church.location.lat, church.location.lng),
                createdAt: now,
                updatedAt: now,
            }, { merge: true });
            count += 1;
        }
        await batch.commit();
        logger.info(`[seedChurchData] wrote ${count} seed churches`);
        return { written: count };
    }
);

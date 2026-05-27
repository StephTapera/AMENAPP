import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

type ChurchSize = "small" | "medium" | "large" | "mega";
type ChurchSource = "google_places" | "claimed" | "manual";

interface ChurchSeed {
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
    size: ChurchSize;
    serviceTimes: Array<{ day: string; time: string; language: string; type: string }>;
    languages: string[];
    statementOfFaith: string;
    doctrinalTags: string[];
    description: string;
    website?: string;
    phone?: string;
    email?: string;
    photos: string[];
    googlePlaceId?: string;
    source: ChurchSource;
    claimed: boolean;
    claimedByUid?: string;
    embeddingVersion: number;
}

const seedChurches: ChurchSeed[] = [
    {
        id: "seed-overland-renewal-church",
        name: "Overland Renewal Church",
        address: "2520 Woodson Road",
        city: "Overland",
        state: "MO",
        zip: "63114",
        location: { lat: 38.7018, lng: -90.3624 },
        denomination: "Non-denominational",
        denominationFamily: "Evangelical",
        worshipStyles: ["contemporary", "charismatic"],
        ministries: ["young_adults", "kids", "missions"],
        size: "medium",
        serviceTimes: [{ day: "Sunday", time: "10:30 AM", language: "English", type: "main" }],
        languages: ["English"],
        statementOfFaith: "We affirm the Trinity, the authority of Scripture, salvation by grace through faith in Jesus Christ, and the work of the Holy Spirit in the life of the church.",
        doctrinalTags: ["trinitarian", "evangelical", "continuationist", "non_denominational", "missional"],
        description: "A contemporary neighborhood church with expressive worship, practical Bible teaching, and a strong young-adults community.",
        photos: [],
        source: "manual",
        claimed: false,
        embeddingVersion: 1,
    },
    {
        id: "seed-clayton-grace-fellowship",
        name: "Clayton Grace Fellowship",
        address: "7740 Carondelet Avenue",
        city: "Clayton",
        state: "MO",
        zip: "63105",
        location: { lat: 38.6489, lng: -90.3378 },
        denomination: "Presbyterian",
        denominationFamily: "Reformed",
        worshipStyles: ["traditional", "liturgical"],
        ministries: ["men", "women", "seniors", "missions"],
        size: "medium",
        serviceTimes: [{ day: "Sunday", time: "9:00 AM", language: "English", type: "main" }],
        languages: ["English"],
        statementOfFaith: "We confess historic Christian orthodoxy, the Trinity, the authority of Scripture, and the gospel of grace centered on the person and work of Jesus Christ.",
        doctrinalTags: ["trinitarian", "nicene_orthodox", "reformed", "paedobaptism"],
        description: "A reverent, teaching-focused congregation with traditional worship and intergenerational discipleship.",
        photos: [],
        source: "manual",
        claimed: false,
        embeddingVersion: 1,
    },
    {
        id: "seed-tower-grove-community-church",
        name: "Tower Grove Community Church",
        address: "3520 Magnolia Avenue",
        city: "St. Louis",
        state: "MO",
        zip: "63118",
        location: { lat: 38.6075, lng: -90.2406 },
        denomination: "Baptist",
        denominationFamily: "Evangelical",
        worshipStyles: ["blended", "contemporary"],
        ministries: ["kids", "youth", "recovery", "missions"],
        size: "large",
        serviceTimes: [{ day: "Sunday", time: "10:00 AM", language: "English", type: "main" }],
        languages: ["English"],
        statementOfFaith: "We believe in one God in three persons, the inspiration of Scripture, believer's baptism, and the call to make disciples in word and deed.",
        doctrinalTags: ["trinitarian", "evangelical", "baptist", "credobaptism", "missional"],
        description: "A city congregation with blended worship, recovery care, family ministries, and a missions emphasis.",
        photos: [],
        source: "manual",
        claimed: false,
        embeddingVersion: 1,
    },
    {
        id: "seed-south-city-vineyard",
        name: "South City Vineyard",
        address: "4201 Arsenal Street",
        city: "St. Louis",
        state: "MO",
        zip: "63116",
        location: { lat: 38.6046, lng: -90.2554 },
        denomination: "Vineyard",
        denominationFamily: "Charismatic",
        worshipStyles: ["contemporary", "charismatic"],
        ministries: ["young_adults", "college", "recovery", "missions"],
        size: "medium",
        serviceTimes: [{ day: "Sunday", time: "11:00 AM", language: "English", type: "main" }],
        languages: ["English"],
        statementOfFaith: "We hold to the historic Christian faith, the authority of Scripture, the kingdom ministry of Jesus, and dependence on the Holy Spirit.",
        doctrinalTags: ["trinitarian", "evangelical", "continuationist", "charismatic", "missional"],
        description: "A relaxed, Spirit-led church with contemporary worship, prayer ministry, and outreach in South City.",
        photos: [],
        source: "manual",
        claimed: false,
        embeddingVersion: 1,
    },
    {
        id: "seed-webster-hills-anglican",
        name: "Webster Hills Anglican",
        address: "29 West Lockwood Avenue",
        city: "Webster Groves",
        state: "MO",
        zip: "63119",
        location: { lat: 38.5925, lng: -90.3581 },
        denomination: "Anglican",
        denominationFamily: "Anglican",
        worshipStyles: ["liturgical", "traditional"],
        ministries: ["kids", "seniors", "marriage"],
        size: "small",
        serviceTimes: [{ day: "Sunday", time: "8:30 AM", language: "English", type: "eucharist" }],
        languages: ["English"],
        statementOfFaith: "We worship the Triune God through Word and Sacrament and confess the creeds of the historic Christian church.",
        doctrinalTags: ["trinitarian", "nicene_orthodox", "sacramental", "paedobaptism"],
        description: "A smaller liturgical parish with historic worship, pastoral care, and a quiet intergenerational rhythm.",
        photos: [],
        source: "manual",
        claimed: false,
        embeddingVersion: 1,
    },
    {
        id: "seed-florissant-family-church",
        name: "Florissant Family Church",
        address: "1290 Shackelford Road",
        city: "Florissant",
        state: "MO",
        zip: "63031",
        location: { lat: 38.7956, lng: -90.3204 },
        denomination: "Assemblies of God",
        denominationFamily: "Pentecostal",
        worshipStyles: ["contemporary", "charismatic"],
        ministries: ["kids", "youth", "women", "missions"],
        size: "large",
        serviceTimes: [{ day: "Sunday", time: "10:00 AM", language: "English", type: "main" }],
        languages: ["English", "Spanish"],
        statementOfFaith: "We believe in the Trinity, salvation through Jesus Christ, the baptism and gifts of the Holy Spirit, and the mission of the church.",
        doctrinalTags: ["trinitarian", "pentecostal", "continuationist", "charismatic", "missional"],
        description: "A family-centered Pentecostal church with energetic worship, youth ministry, and bilingual outreach.",
        photos: [],
        source: "manual",
        claimed: false,
        embeddingVersion: 1,
    },
    {
        id: "seed-maplewood-mercy-chapel",
        name: "Maplewood Mercy Chapel",
        address: "7301 Manchester Road",
        city: "Maplewood",
        state: "MO",
        zip: "63143",
        location: { lat: 38.6137, lng: -90.3187 },
        denomination: "Methodist",
        denominationFamily: "Wesleyan",
        worshipStyles: ["blended", "traditional"],
        ministries: ["recovery", "men", "women", "seniors"],
        size: "small",
        serviceTimes: [{ day: "Sunday", time: "9:30 AM", language: "English", type: "main" }],
        languages: ["English"],
        statementOfFaith: "We confess the Triune God, salvation by grace through faith, Scripture as the guide for faith and practice, and holiness expressed in love of God and neighbor.",
        doctrinalTags: ["trinitarian", "wesleyan", "missional"],
        description: "A pastoral, service-oriented church with blended worship and recovery support for the wider Maplewood community.",
        photos: [],
        source: "manual",
        claimed: false,
        embeddingVersion: 1,
    },
    {
        id: "seed-st-charles-river-church",
        name: "St. Charles River Church",
        address: "1050 South Riverside Drive",
        city: "St. Charles",
        state: "MO",
        zip: "63301",
        location: { lat: 38.7791, lng: -90.4841 },
        denomination: "Non-denominational",
        denominationFamily: "Evangelical",
        worshipStyles: ["contemporary"],
        ministries: ["kids", "youth", "young_adults", "marriage"],
        size: "mega",
        serviceTimes: [
            { day: "Saturday", time: "5:00 PM", language: "English", type: "main" },
            { day: "Sunday", time: "9:30 AM", language: "English", type: "main" },
        ],
        languages: ["English"],
        statementOfFaith: "We affirm the Trinity, the authority of the Bible, salvation in Christ alone, and the calling of every believer to serve and make disciples.",
        doctrinalTags: ["trinitarian", "evangelical", "non_denominational", "credobaptism", "missional"],
        description: "A large contemporary church with multiple weekend services, strong family ministries, and marriage support.",
        photos: [],
        source: "manual",
        claimed: false,
        embeddingVersion: 1,
    },
    {
        id: "seed-kirkwood-covenant-church",
        name: "Kirkwood Covenant Church",
        address: "221 West Adams Avenue",
        city: "Kirkwood",
        state: "MO",
        zip: "63122",
        location: { lat: 38.5825, lng: -90.4108 },
        denomination: "Evangelical Covenant",
        denominationFamily: "Evangelical",
        worshipStyles: ["blended"],
        ministries: ["kids", "college", "missions", "seniors"],
        size: "medium",
        serviceTimes: [{ day: "Sunday", time: "10:15 AM", language: "English", type: "main" }],
        languages: ["English"],
        statementOfFaith: "We are centered on Jesus Christ, rooted in Scripture, committed to the whole mission of the church, and united around historic Christian faith.",
        doctrinalTags: ["trinitarian", "evangelical", "missional"],
        description: "A mission-minded church with blended worship, college connections, and steady discipleship across life stages.",
        photos: [],
        source: "manual",
        claimed: false,
        embeddingVersion: 1,
    },
    {
        id: "seed-south-county-esperanza",
        name: "Iglesia Esperanza South County",
        address: "4335 Butler Hill Road",
        city: "St. Louis",
        state: "MO",
        zip: "63128",
        location: { lat: 38.4916, lng: -90.3605 },
        denomination: "Non-denominational",
        denominationFamily: "Evangelical",
        worshipStyles: ["contemporary", "charismatic"],
        ministries: ["kids", "youth", "men", "women"],
        size: "medium",
        serviceTimes: [{ day: "Sunday", time: "12:30 PM", language: "Spanish", type: "main" }],
        languages: ["Spanish", "English"],
        statementOfFaith: "Afirmamos al Dios trino, la autoridad de la Biblia, la salvacion por gracia mediante la fe en Cristo, y la obra del Espiritu Santo.",
        doctrinalTags: ["trinitarian", "evangelical", "continuationist", "non_denominational"],
        description: "A bilingual congregation with Spanish-language worship, family ministries, and a welcoming contemporary style.",
        photos: [],
        source: "manual",
        claimed: false,
        embeddingVersion: 1,
    },
];

function assertAdmin(context: functions.https.CallableContext): void {
    if (!context.auth?.token?.admin) {
        throw new functions.https.HttpsError("permission-denied", "Admin access is required.");
    }
}

export const seedSmartChurches = functions
    .runWith({ enforceAppCheck: true })
    .https.onCall(async (_data, context) => {
        assertAdmin(context);

        const db = admin.firestore();
        const now = admin.firestore.FieldValue.serverTimestamp();
        const batch = db.batch();

        for (const church of seedChurches) {
            const ref = db.collection("churches").doc(church.id);
            batch.set(ref, {
                ...church,
                geoPoint: new admin.firestore.GeoPoint(church.location.lat, church.location.lng),
                createdAt: now,
                updatedAt: now,
            }, { merge: true });
        }

        await batch.commit();
        return { count: seedChurches.length, churchIds: seedChurches.map((church) => church.id) };
    });

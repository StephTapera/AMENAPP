/**
 * seedTheologyCorpus.ts
 *
 * Seeds 8 public-domain theology documents into the Firestore collection
 * "bereanTheologyCorpus". All content is original summary text of
 * public-domain doctrinal material — no modern copyrighted text is included.
 *
 * Usage:
 *   cd functions && npx tsx scripts/seedTheologyCorpus.ts
 *
 * Idempotent: existing docs are skipped (not overwritten).
 */

import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();
const COLLECTION = "bereanTheologyCorpus";

interface TheologyDoc {
  id: string;
  title: string;
  content: string;
  source: string;
  denomination: string;
  relevanceKeywords: string[];
}

const DOCS: TheologyDoc[] = [
  {
    id: "apostles-creed",
    title: "The Apostles' Creed — Summary",
    source: "Early Church (2nd–4th century)",
    denomination: "Universal/Ecumenical",
    content:
      "The Apostles' Creed is one of Christianity's oldest confessions, affirming belief in God the Father Almighty, Creator of heaven and earth. " +
      "It declares faith in Jesus Christ — his miraculous birth, suffering under Pontius Pilate, crucifixion, burial, and bodily resurrection on the third day. " +
      "It affirms his ascension to the right hand of the Father and his coming again in judgment. " +
      "The creed confesses the Holy Spirit, the holy catholic (universal) Church, the communion of saints, forgiveness of sins, and resurrection of the body.",
    relevanceKeywords: ["creed", "trinity", "resurrection", "apostles", "faith", "belief"],
  },
  {
    id: "nicene-creed",
    title: "The Nicene Creed — Summary",
    source: "Council of Nicaea (325 AD) and Constantinople (381 AD)",
    denomination: "Universal/Ecumenical",
    content:
      "The Nicene Creed emerged from the First Council of Nicaea in 325 AD and was expanded at Constantinople in 381 AD. " +
      "It affirms that Jesus Christ is 'God from God, Light from Light, true God from true God' — begotten, not made — and of one substance (homoousios) with the Father. " +
      "This language was crafted to refute Arianism, which held that the Son was a created being subordinate to the Father. " +
      "The creed also affirms the Holy Spirit as 'the Lord, the giver of life' proceeding from the Father.",
    relevanceKeywords: ["nicene", "trinity", "homoousios", "Jesus", "divinity", "council"],
  },
  {
    id: "attributes-of-god",
    title: "Classic Attributes of God — Summary",
    source: "Historical Christian Theology",
    denomination: "Broadly Evangelical",
    content:
      "Classical Christian theology describes God through communicable and incommunicable attributes. " +
      "Incommunicable attributes — those unique to God alone — include omniscience (knowing all things), omnipotence (unlimited power), omnipresence (present everywhere simultaneously), immutability (unchanging in nature), and aseity (self-existence, dependent on nothing). " +
      "Communicable attributes — those God shares in measure with humanity — include love, justice, mercy, wisdom, and holiness. " +
      "Scripture presents these attributes not as contradictions but as a harmonious whole reflecting God's perfect nature.",
    relevanceKeywords: ["attributes", "God", "omniscience", "omnipotence", "holy", "love", "justice"],
  },
  {
    id: "doctrine-of-salvation",
    title: "Doctrine of Salvation (Soteriology) — Overview",
    source: "Systematic Theology — Protestant Tradition",
    denomination: "Broadly Protestant",
    content:
      "Soteriology is the branch of Christian theology concerned with salvation. " +
      "Most Protestant traditions affirm that salvation is by grace through faith alone (sola gratia, sola fide), not earned by human merit. " +
      "The ordo salutis (order of salvation) describes the logical sequence of redemptive acts: calling, regeneration, faith, repentance, justification, adoption, sanctification, perseverance, and glorification — though traditions differ on the order and nature of some steps. " +
      "Justification means God declares the sinner righteous on the basis of Christ's atoning work imputed to the believer.",
    relevanceKeywords: ["salvation", "grace", "faith", "justification", "soteriology", "atonement"],
  },
  {
    id: "scripture-authority",
    title: "Biblical Authority and Inerrancy — Summary",
    source: "Chicago Statement on Biblical Inerrancy (1978) — Public Summary",
    denomination: "Broadly Evangelical",
    content:
      "The doctrine of biblical authority affirms that Scripture is the written Word of God, given by divine inspiration and therefore truthful and trustworthy in all that it affirms. " +
      "Inerrancy holds that the original manuscripts of the Bible are without error or falsehood in matters of faith, history, and science as the biblical authors intended to address them. " +
      "Most evangelical traditions distinguish inerrancy (no errors in originals) from infallibility (cannot deceive in matters of faith and practice). " +
      "The Bible is considered the final authority — above tradition, reason, and experience — though it is read through interpretive communities.",
    relevanceKeywords: ["Bible", "inerrancy", "authority", "scripture", "inspiration", "infallibility"],
  },
  {
    id: "atonement-theories",
    title: "Theories of the Atonement — Summary",
    source: "Historical Christian Theology",
    denomination: "Cross-denominational",
    content:
      "Christian theology offers several complementary models explaining how Christ's death accomplishes human salvation. " +
      "Penal substitution holds that Christ bore the punishment for sin that humanity deserved, satisfying divine justice. " +
      "Christus Victor emphasizes Christ's victory over sin, death, and the devil through the cross and resurrection. " +
      "Moral influence theory sees the cross primarily as a demonstration of God's love that transforms human hearts. " +
      "Ransom theory views Christ's death as paying a price to free humanity from bondage. " +
      "Most Reformed and evangelical traditions emphasize penal substitution; Orthodox traditions favor Christus Victor; these models are not necessarily mutually exclusive.",
    relevanceKeywords: ["atonement", "cross", "penal substitution", "Christus Victor", "redemption", "sacrifice"],
  },
  {
    id: "holy-spirit-work",
    title: "The Work of the Holy Spirit — Summary",
    source: "Systematic Theology — Pneumatology",
    denomination: "Broadly Christian",
    content:
      "Pneumatology is the study of the Holy Spirit. " +
      "The Spirit is the third person of the Trinity — fully divine, co-equal with the Father and Son. " +
      "The Spirit's work includes conviction of sin, regeneration (new birth), indwelling of believers, sanctification (progressive transformation toward holiness), and distribution of spiritual gifts for edification of the church. " +
      "Traditions differ on the cessation or continuation of certain gifts (cessationism vs. continuationism) and on the Spirit's relationship to water baptism. " +
      "What is broadly affirmed is that no one can come to faith apart from the Spirit's work.",
    relevanceKeywords: ["Holy Spirit", "pneumatology", "spiritual gifts", "sanctification", "regeneration", "Trinity"],
  },
  {
    id: "eschatology-overview",
    title: "Eschatology — Last Things Overview",
    source: "Systematic Theology — Eschatology",
    denomination: "Cross-denominational",
    content:
      "Eschatology is the study of last things: death, resurrection, final judgment, and the new creation. " +
      "Christians broadly affirm bodily resurrection, final judgment, and the eternal states of heaven and hell, though they differ significantly on the nature and timing of millennial events. " +
      "Premillennialism holds that Christ returns before a literal thousand-year reign; postmillennialism holds believers usher in a golden age before Christ returns; amillennialism views the millennium as a symbolic present-age reign of Christ. " +
      "All traditions affirm the personal, physical, visible return of Jesus Christ and the resurrection of the dead.",
    relevanceKeywords: ["eschatology", "end times", "resurrection", "judgment", "millennium", "heaven", "return"],
  },
];

async function seedTheologyCorpus(): Promise<void> {
  console.log(`Starting theology corpus seed — ${DOCS.length} documents to process.`);

  const collectionRef = db.collection(COLLECTION);

  let created = 0;
  let skipped = 0;

  // Process each document individually to allow idempotent skip-if-exists logic.
  // Firestore batch.set() with merge:false would overwrite; we read first to skip.
  for (const doc of DOCS) {
    const ref = collectionRef.doc(doc.id);
    const snapshot = await ref.get();

    if (snapshot.exists) {
      console.log(`  SKIP  ${doc.id} (already exists)`);
      skipped++;
    } else {
      const { id, ...data } = doc;
      await ref.set({
        ...data,
        seededAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`  CREATE ${doc.id}`);
      created++;
    }
  }

  // Read back the collection count for verification.
  const allDocs = await collectionRef.get();
  const totalInCollection = allDocs.size;

  console.log("\n--- Seed complete ---");
  console.log(`  Created : ${created}`);
  console.log(`  Skipped : ${skipped}`);
  console.log(`  Total docs in ${COLLECTION}: ${totalInCollection}`);

  process.exit(0);
}

seedTheologyCorpus().catch((err) => {
  console.error("Seed failed:", err);
  process.exit(1);
});

// === AGENT D: DATA LAYER ===
// BereanDataLayer.jsx — Ground-truth data layer for the Berean daily formation companion
//
// EXPORTS (no import statements — all 4 are named):
//   mockData         — seeded mock data object (ground truth for prototype)
//   getVerse         — (ref, translation?) => { ref, text, translation, isMock }
//   useBereanData    — (selectedTopics?) => full data object + dailyCards
//   whySeeingThis    — (card) => human-readable explanation string
//
// HARD CONSTRAINTS (override everything):
//   - No invented Scripture. All verse text explicitly mock-labeled.
//   - Crisis items NEVER receive AI treatment; surfaced separately, always.
//   - No localStorage / sessionStorage. React state only.
//   - Deterministic assembly: same inputs → same output. No random filler.
//   - isMock: true on every getVerse result — no exceptions.
//
// Topic keys accepted (short form from onboarding OR long form from spec):
//   verse | verse_reflection
//   plan  | reading_plan
//   prayer | prayer_followups
//   sanctuary | sanctuary_stirrings
//   memory | memory_verse
//   study  (short only)
//   seasonal (same both forms)

// ─── TODAY constant ──────────────────────────────────────────────────────────
// Use a fixed date for deterministic prototype behaviour.
// In production this becomes: new Date().toISOString().slice(0, 10)
const _TODAY = '2026-06-07';

// ─── Helpers ─────────────────────────────────────────────────────────────────

function _daysBetween(isoA, isoB) {
  return Math.floor(
    (new Date(isoB).getTime() - new Date(isoA).getTime()) / 86400000
  );
}

function _daysSinceToday(isoStr) {
  return _daysBetween(isoStr, _TODAY);
}

// Normalise topic keys so both short and long forms match
function _normaliseTopic(key) {
  const MAP = {
    verse_reflection:   'verse',
    reading_plan:       'plan',
    prayer_followups:   'prayer',
    sanctuary_stirrings:'sanctuary',
    memory_verse:       'memory',
  };
  return MAP[key] ?? key;
}

function _topicsInclude(selectedTopics, shortKey) {
  return selectedTopics.some(t => _normaliseTopic(t) === shortKey);
}

// ─── Verse look-up table ──────────────────────────────────────────────────────
// ~10 well-known verses; text explicitly marked [MOCK].
// All text MUST be replaced by a YouVersion Content API call before any release.
const _VERSE_DB = {
  'Psalm 46:1': {
    ESV: '[MOCK — Psalm 46:1 ESV] God is our refuge and strength, a very present help in trouble.',
    NIV: '[MOCK — Psalm 46:1 NIV] God is our refuge and strength, an ever-present help in trouble.',
    KJV: '[MOCK — Psalm 46:1 KJV] God is our refuge and strength, a very present help in trouble.',
    NASB:'[MOCK — Psalm 46:1 NASB] God is our refuge and strength, a very present help in trouble.',
    NLT: '[MOCK — Psalm 46:1 NLT] God is our refuge and strength, always ready to help in times of trouble.',
  },
  'Psalm 23:4': {
    ESV: '[MOCK — Psalm 23:4 ESV] Even though I walk through the valley of the shadow of death, I will fear no evil, for you are with me; your rod and your staff, they comfort me.',
    NIV: '[MOCK — Psalm 23:4 NIV] Even though I walk through the darkest valley, I will fear no evil, for you are with me; your rod and your staff, they comfort me.',
    KJV: '[MOCK — Psalm 23:4 KJV] Yea, though I walk through the valley of the shadow of death, I will fear no evil: for thou art with me; thy rod and thy staff they comfort me.',
  },
  'Romans 8:28': {
    ESV: '[MOCK — Romans 8:28 ESV] And we know that for those who love God all things work together for good, for those who are called according to his purpose.',
    NIV: '[MOCK — Romans 8:28 NIV] And we know that in all things God works for the good of those who love him, who have been called according to his purpose.',
    KJV: '[MOCK — Romans 8:28 KJV] And we know that all things work together for good to them that love God, to them who are the called according to his purpose.',
  },
  'James 1:5': {
    ESV: '[MOCK — James 1:5 ESV] If any of you lacks wisdom, let him ask God, who gives generously to all without reproach, and it will be given him.',
    NIV: '[MOCK — James 1:5 NIV] If any of you lacks wisdom, you should ask God, who gives generously to all without finding fault, and it will be given to you.',
    KJV: '[MOCK — James 1:5 KJV] If any of you lack wisdom, let him ask of God, that giveth to all men liberally, and upbraideth not; and it shall be given him.',
  },
  'Philippians 4:13': {
    ESV: '[MOCK — Philippians 4:13 ESV] I can do all things through him who strengthens me.',
    NIV: '[MOCK — Philippians 4:13 NIV] I can do all this through him who gives me strength.',
    KJV: '[MOCK — Philippians 4:13 KJV] I can do all things through Christ which strengtheneth me.',
    NASB:'[MOCK — Philippians 4:13 NASB] I can do all things through Him who strengthens me.',
  },
  'John 3:16': {
    ESV: '[MOCK — John 3:16 ESV] For God so loved the world, that he gave his only Son, that whoever believes in him should not perish but have eternal life.',
    NIV: '[MOCK — John 3:16 NIV] For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.',
    KJV: '[MOCK — John 3:16 KJV] For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.',
  },
  'Matthew 11:28': {
    ESV: '[MOCK — Matthew 11:28 ESV] Come to me, all who labor and are heavy laden, and I will give you rest.',
    NIV: '[MOCK — Matthew 11:28 NIV] Come to me, all you who are weary and burdened, and I will give you rest.',
    KJV: '[MOCK — Matthew 11:28 KJV] Come unto me, all ye that labour and are heavy laden, and I will give you rest.',
  },
  'Proverbs 3:5-6': {
    ESV: '[MOCK — Proverbs 3:5-6 ESV] Trust in the LORD with all your heart, and do not lean on your own understanding. In all your ways acknowledge him, and he will make straight your paths.',
    NIV: '[MOCK — Proverbs 3:5-6 NIV] Trust in the LORD with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.',
    KJV: '[MOCK — Proverbs 3:5-6 KJV] Trust in the LORD with all thine heart; and lean not unto thine own understanding. In all thy ways acknowledge him, and he shall direct thy paths.',
  },
  'Isaiah 40:31': {
    ESV: '[MOCK — Isaiah 40:31 ESV] But they who wait for the LORD shall renew their strength; they shall mount up with wings like eagles; they shall run and not be weary; they shall walk and not faint.',
    NIV: '[MOCK — Isaiah 40:31 NIV] But those who hope in the LORD will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.',
    KJV: '[MOCK — Isaiah 40:31 KJV] But they that wait upon the LORD shall renew their strength; they shall mount up with wings as eagles; they shall run, and not be weary; and they shall walk, and not faint.',
  },
  'Acts 17:11': {
    ESV: '[MOCK — Acts 17:11 ESV] Now these Jews were more noble than those in Thessalonica; they received the word with all eagerness, examining the Scriptures daily to see if these things were so.',
    NIV: '[MOCK — Acts 17:11 NIV] Now the Berean Jews received the message with great eagerness and examined the Scriptures every day to see if what Paul said was true.',
    KJV: '[MOCK — Acts 17:11 KJV] These were more noble than those in Thessalonica, in that they received the word with all readiness of mind, and searched the scriptures daily, whether those things were so.',
  },
  // Reading-plan passage for the mock user
  'Psalm 46': {
    ESV: '[MOCK — Psalm 46 ESV] God is our refuge and strength, a very present help in trouble. Therefore we will not fear though the earth gives way, though the mountains be moved into the heart of the sea.',
    NIV: '[MOCK — Psalm 46 NIV] God is our refuge and strength, an ever-present help in trouble. Therefore we will not fear, though the earth give way and the mountains fall into the heart of the sea.',
  },
};

// ─── getVerse ─────────────────────────────────────────────────────────────────

const getVerse = (ref, translation = 'ESV') => {
  const byRef = _VERSE_DB[ref];
  if (!byRef) {
    return {
      ref,
      translation,
      text:   `[MOCK — ${ref} ${translation}] Verse text will be sourced from YouVersion license.`,
      isMock: true,
    };
  }
  // Fall back to first available translation if the requested one isn't present
  const text = byRef[translation] ?? byRef[Object.keys(byRef)[0]];
  return { ref, translation, text, isMock: true };
};

// ─── mockData ─────────────────────────────────────────────────────────────────

const mockData = {
  user: {
    name:              'Marcus',
    tradition:         'non-denominational',
    translationPref:   'ESV',
    // Long-form topic keys per spec — normalised internally during assembly
    selectedTopics:    ['verse_reflection', 'reading_plan', 'prayer_followups', 'sanctuary_stirrings', 'memory_verse'],
    joinedOn:          '2024-09-14',
  },

  readingPlan: {
    name:             'Through the Psalms in 60 Days',
    totalDays:        60,
    currentDay:       23,
    todayPassageRef:  'Psalm 46',
    progress:         23 / 60, // ≈ 0.383
    lastReadOn:       '2026-06-06', // yesterday relative to _TODAY
  },

  prayerList: [
    // Normal sensitivity — eligible for arc feed
    { id: 'p1', subject: 'Job clarity',          forWhom: 'Myself',           prayedOn: '2026-06-04', status: 'active',   sensitivity: 'normal' },
    // Tender — surfaces with gentle nudge, no AI reflection
    { id: 'p2', subject: 'Healing journey',       forWhom: 'Mom',              prayedOn: '2026-06-03', status: 'active',   sensitivity: 'tender' },
    { id: 'p3', subject: 'Marriage restoration',  forWhom: 'David & Kezia',    prayedOn: '2026-06-01', status: 'active',   sensitivity: 'normal' },
    // Crisis — must NOT receive AI treatment; rendered separately at feed bottom
    { id: 'p4', subject: 'Mental health crisis',  forWhom: 'Friend (James)',   prayedOn: '2026-06-06', status: 'active',   sensitivity: 'crisis' },
    // Answered — not surfaced in feed
    { id: 'p5', subject: 'Safe travel',           forWhom: 'Sister',           prayedOn: '2026-05-28', status: 'answered', sensitivity: 'normal' },
  ],

  sanctuaries: [
    { id: 's1', name: 'Eastside Fellowship',        openPrayerRequests: 7, activeThreads: 3, lastVisited: '2026-06-05' },
    { id: 's2', name: 'Men of Valor Study Group',   openPrayerRequests: 2, activeThreads: 1, lastVisited: '2026-06-03' },
  ],

  highlights: [
    { verseRef: 'Psalm 23:4',    note: 'Even in dark seasons, presence is the promise.', savedOn: '2026-06-02', translation: 'ESV' },
    { verseRef: 'Romans 8:28',   note: 'Purpose in suffering — not bypassing it.',       savedOn: '2026-05-30', translation: 'ESV' },
  ],

  memoryVerses: [
    { verseRef: 'James 1:5',        srsDueDate: '2026-06-07', strength: 2, lastPracticedOn: '2026-06-04', translation: 'ESV' },
    { verseRef: 'Philippians 4:13', srsDueDate: '2026-06-10', strength: 4, lastPracticedOn: '2026-06-06', translation: 'ESV' },
  ],

  seasonal: {
    liturgicalSeason: 'Ordinary Time',
    prompt:           'In the unhurried pace of Ordinary Time, what ordinary moments is God asking you to notice?',
    color:            '#4A7A4A',
  },
};

// ─── assembleDailyCards ───────────────────────────────────────────────────────
// Deterministic: same inputs → same output. No random ordering.
// Returns CardSpec[] each with: { id, type, cardType, data, whyReason, priority, icon, preview, chips, source, sourceDetail }
//
// Sort order (priority): verse → plan → memory → prayer (normal/tender) → sanctuary → study → seasonal
//                        crisis items are always appended last regardless of topic order
//
// Rules:
//   1. Card only appears if its topic is in selectedTopics
//   2. Reading plan: include if lastReadOn === yesterday (momentum) OR ≥ 2 days ago (nudge)
//   3. Prayer: ONE most-due normal-sensitivity item; tender items with gentle nudge;
//              crisis items appended at end — never enter the arc
//   4. Sanctuary: pick the one with most recent lastVisited
//   5. Memory: only if srsDueDate <= today
//   6. Seasonal: always included if liturgicalSeason is set
//   7. Verse card is always first when present

function assembleDailyCards(userData, selectedTopics) {
  const topics    = selectedTopics ?? userData.selectedTopics ?? [];
  const cards     = [];
  let   priority  = 1;
  const today     = _TODAY;
  const yesterday = (() => {
    const d = new Date(today);
    d.setDate(d.getDate() - 1);
    return d.toISOString().slice(0, 10);
  })();

  // ── 1. Verse reflection ────────────────────────────────────────────────────
  if (_topicsInclude(topics, 'verse')) {
    const verse = getVerse(userData.readingPlan?.todayPassageRef ?? 'Psalm 46', userData.translationPref ?? 'ESV');
    cards.push({
      id:          'card-verse',
      type:        'Daily Verse',
      cardType:    'verse',
      icon:        '✦',
      priority:    priority++,
      source:      'readingPlan',
      sourceDetail: userData.readingPlan?.name ?? '',
      data:        { verse },
      preview:     verse.text.replace(/\[MOCK[^\]]*\]\s*/g, '').substring(0, 90) + '…',
      chips:       [{ ref: userData.readingPlan?.todayPassageRef, tr: userData.translationPref ?? 'ESV' }],
      whyReason:   `Your daily verse is drawn from ${userData.readingPlan?.name ?? 'your reading plan'} — Day ${userData.readingPlan?.currentDay ?? '—'} of ${userData.readingPlan?.totalDays ?? '—'}. Berean ties your morning verse to where you are in Scripture, not a random pick.`,
    });
  }

  // ── 2. Reading plan ────────────────────────────────────────────────────────
  if (_topicsInclude(topics, 'plan')) {
    const plan       = userData.readingPlan;
    const lastRead   = plan?.lastReadOn ?? null;
    const daysSince  = lastRead ? _daysBetween(lastRead, today) : 999;
    // Include if read yesterday (momentum) OR not read for 2+ days (gentle nudge)
    const shouldShow = daysSince <= 1 || daysSince >= 2;

    if (shouldShow && plan) {
      const nudgeReason = daysSince <= 1
        ? `You read ${plan.todayPassageRef} yesterday. Berean shows your reading plan card each morning to help you maintain momentum.`
        : `You haven't opened your reading plan in ${daysSince} day${daysSince === 1 ? '' : 's'}. This is a gentle nudge — not guilt — to keep your pace.`;

      cards.push({
        id:          'card-plan',
        type:        'Reading Plan',
        cardType:    'plan',
        icon:        '📖',
        priority:    priority++,
        source:      'readingPlan',
        sourceDetail: plan.name,
        data:        { readingPlan: plan, daysSinceLastRead: daysSince },
        preview:     `Day ${plan.currentDay} of ${plan.totalDays} — ${plan.todayPassageRef}`,
        chips:       [],
        whyReason:   `You're on Day ${plan.currentDay} of ${plan.name}. ${nudgeReason}`,
      });
    }
  }

  // ── 3. Memory verse (SRS) ──────────────────────────────────────────────────
  if (_topicsInclude(topics, 'memory')) {
    // Only if due date <= today; pick the one with lowest strength first
    const dueVerses = (userData.memoryVerses ?? [])
      .filter(v => v.srsDueDate <= today)
      .sort((a, b) => a.strength - b.strength);

    if (dueVerses.length > 0) {
      const due = dueVerses[0];
      const overdueDays = _daysBetween(due.srsDueDate, today);
      cards.push({
        id:          `card-memory-${due.verseRef.replace(/\s/g, '-')}`,
        type:        'Memory Verse',
        cardType:    'memory',
        icon:        '⭐',
        priority:    priority++,
        source:      'memoryVerses',
        sourceDetail: 'Spaced repetition schedule',
        data:        { memoryVerse: due },
        preview:     `${due.verseRef} — memory strength ${due.strength * 20}%`,
        chips:       [{ ref: due.verseRef, tr: due.translation ?? userData.translationPref ?? 'ESV' }],
        whyReason:   `${due.verseRef} is due for practice today based on your spaced repetition schedule.${overdueDays > 0 ? ` It was due ${overdueDays} day${overdueDays === 1 ? '' : 's'} ago.` : ''} Reviewing it now builds long-term retention.`,
      });
    }
  }

  // ── 4. Prayer follow-up ────────────────────────────────────────────────────
  // Step A: pick ONE most-due normal-sensitivity active item (most days since last prayed)
  // Step B: if no normal item, pick most-due tender item with gentle nudge flag
  // Step C: crisis items are collected and appended at the very end — never in main arc
  if (_topicsInclude(topics, 'prayer')) {
    const activePrayers = (userData.prayerList ?? []).filter(p => p.status === 'active');

    // Eligible arc prayers: normal or tender, sorted by oldest prayedOn first
    const eligible = activePrayers
      .filter(p => p.sensitivity !== 'crisis')
      .sort((a, b) => new Date(a.prayedOn) - new Date(b.prayedOn));

    if (eligible.length > 0) {
      const prayer     = eligible[0];
      const daysAgo    = _daysSinceToday(prayer.prayedOn);
      const isTender   = prayer.sensitivity === 'tender';

      const tenderNote = isTender
        ? ' This is a tender request — Berean holds it gently and never generates AI reflection for it.'
        : '';

      cards.push({
        id:          `card-prayer-${prayer.id}`,
        type:        'Prayer Follow-up',
        cardType:    'prayer',
        icon:        '🙏',
        priority:    priority++,
        source:      'prayerList',
        sourceDetail: 'Your prayer list',
        data:        { prayer, isTender, daysAgo },
        preview:     `Praying for ${prayer.forWhom} — ${prayer.subject}`,
        chips:       [],
        whyReason:   `You prayed for ${prayer.subject} ${daysAgo === 0 ? 'today' : `${daysAgo} day${daysAgo === 1 ? '' : 's'} ago`}. Regular follow-up strengthens prayer habits and helps you notice answers.${tenderNote}`,
      });
    }

    // Crisis items: always appended last — NEVER in the main arc
    const crisisItems = activePrayers.filter(p => p.sensitivity === 'crisis');
    for (const crisis of crisisItems) {
      const daysAgo = _daysSinceToday(crisis.prayedOn);
      cards.push({
        id:          `card-crisis-${crisis.id}`,
        type:        'You\'re Not Alone',
        cardType:    'crisis',
        icon:        '🛡️',
        priority:    9000 + cards.length, // always sort to end
        source:      'prayerList',
        sourceDetail: 'Crisis prayer list',
        data:        { prayer: crisis, daysAgo },
        preview:     'Crisis support resources are available to you.',
        chips:       [],
        // Crisis items have no AI why-reason — they have a human support message
        whyReason:   'You\'ve been carrying something heavy. Crisis items always appear separately at the bottom — they never receive AI reflection. Please reach out to someone who loves you.',
        isCrisis:    true,
      });
    }
  }

  // ── 5. Sanctuary stirrings ─────────────────────────────────────────────────
  if (_topicsInclude(topics, 'sanctuary')) {
    const sanctuaries = userData.sanctuaries ?? [];
    if (sanctuaries.length > 0) {
      // Pick the one most recently visited
      const sanctuary = [...sanctuaries].sort(
        (a, b) => new Date(b.lastVisited) - new Date(a.lastVisited)
      )[0];

      const daysSinceVisit = _daysSinceToday(sanctuary.lastVisited);

      cards.push({
        id:          `card-sanctuary-${sanctuary.id}`,
        type:        'Sanctuary Stirring',
        cardType:    'sanctuary',
        icon:        '⛪',
        priority:    priority++,
        source:      'sanctuary',
        sourceDetail: sanctuary.name,
        data:        { sanctuary, daysSinceVisit },
        preview:     `${sanctuary.openPrayerRequests} open prayer request${sanctuary.openPrayerRequests === 1 ? '' : 's'} · ${sanctuary.activeThreads} active thread${sanctuary.activeThreads === 1 ? '' : 's'}`,
        chips:       [],
        whyReason:   `Your ${sanctuary.name} community has ${sanctuary.openPrayerRequests} open prayer request${sanctuary.openPrayerRequests === 1 ? '' : 's'}. You last visited ${daysSinceVisit === 0 ? 'today' : `${daysSinceVisit} day${daysSinceVisit === 1 ? '' : 's'} ago`}.`,
      });
    }
  }

  // ── 6. Study thread (open highlights) ─────────────────────────────────────
  if (_topicsInclude(topics, 'study')) {
    const highlights = userData.highlights ?? [];
    if (highlights.length > 0) {
      // Most recently saved highlight
      const highlight = [...highlights].sort(
        (a, b) => new Date(b.savedOn) - new Date(a.savedOn)
      )[0];

      cards.push({
        id:          `card-study-${highlight.verseRef.replace(/\s/g, '-')}`,
        type:        'Open Study',
        cardType:    'study',
        icon:        '🔍',
        priority:    priority++,
        source:      'highlights',
        sourceDetail: 'Your highlights',
        data:        { highlight },
        preview:     `"${highlight.note}"`,
        chips:       [{ ref: highlight.verseRef, tr: highlight.translation ?? userData.translationPref ?? 'ESV' }],
        whyReason:   `You highlighted ${highlight.verseRef} and noted: "${highlight.note}" This thread is still open.`,
      });
    }
  }

  // ── 7. Seasonal rhythm ─────────────────────────────────────────────────────
  // Always included if liturgicalSeason is set; topic gate still applies
  const seasonal = userData.seasonal;
  if (_topicsInclude(topics, 'seasonal') && seasonal?.liturgicalSeason) {
    cards.push({
      id:          'card-seasonal',
      type:        'Seasonal Rhythm',
      cardType:    'seasonal',
      icon:        '🌾',
      priority:    priority++,
      source:      'liturgicalCalendar',
      sourceDetail: seasonal.liturgicalSeason,
      data:        { seasonal },
      preview:     seasonal.prompt,
      chips:       [],
      whyReason:   `You opted into seasonal prompts during onboarding. The church calendar is in ${seasonal.liturgicalSeason}.`,
    });
  }

  // Final sort: by priority ascending (crisis items are already at 9000+)
  return cards.sort((a, b) => a.priority - b.priority);
}

// ─── whySeeingThis ────────────────────────────────────────────────────────────
// Accepts a CardSpec (output of assembleDailyCards) and returns a human-readable
// explanation string. Falls back gracefully for cards with missing fields.

const whySeeingThis = (card) => {
  // Card produced by assembleDailyCards already carries whyReason
  if (card.whyReason) return card.whyReason;

  // Fallback by cardType for cards not produced by assembleDailyCards
  const { cardType, type, data, source, sourceDetail } = card;

  switch (cardType ?? card.type) {
    case 'verse':
    case 'Daily Verse': {
      const plan = data?.readingPlan ?? data?.plan;
      return plan
        ? `Your daily verse is drawn from ${plan.name} — Day ${plan.currentDay} of ${plan.totalDays}. Berean ties your morning verse to where you are in Scripture.`
        : 'Your daily verse is drawn from your reading plan. Berean ties each morning\'s verse to where you actually are in Scripture — not a random pick.';
    }

    case 'plan':
    case 'Reading Plan': {
      const plan = data?.readingPlan;
      if (!plan) return 'You have an active reading plan. Berean shows your reading plan card each morning.';
      return `You're on Day ${plan.currentDay} of ${plan.name}. Berean shows your reading plan card each morning to help you maintain momentum.`;
    }

    case 'memory':
    case 'Memory Verse': {
      const mv = data?.memoryVerse;
      return mv
        ? `${mv.verseRef} is due for practice today based on your spaced repetition schedule. Reviewing it now builds long-term retention.`
        : 'This verse is due for practice today based on your spaced repetition schedule.';
    }

    case 'prayer':
    case 'Prayer Follow-up': {
      const p = data?.prayer;
      if (!p) return 'You selected prayer follow-ups in your Berean preferences.';
      const daysAgo = data?.daysAgo ?? _daysSinceToday(p.prayedOn);
      return `You prayed for ${p.subject} ${daysAgo === 0 ? 'today' : `${daysAgo} day${daysAgo === 1 ? '' : 's'} ago`}. Regular follow-up strengthens prayer habits.`;
    }

    case 'crisis':
    case "You're Not Alone": {
      return 'You\'ve been carrying something heavy. Crisis items always appear separately — they never receive AI reflection. Please reach out to someone who loves you.';
    }

    case 'sanctuary':
    case 'Sanctuary Stirring': {
      const s = data?.sanctuary;
      return s
        ? `Your ${s.name} community has ${s.openPrayerRequests} open prayer request${s.openPrayerRequests === 1 ? '' : 's'}. You chose to join this Sanctuary.`
        : `This comes from activity in your ${sourceDetail ?? 'Sanctuary'} — a community you chose to join.`;
    }

    case 'study':
    case 'Open Study': {
      const h = data?.highlight;
      return h
        ? `You highlighted ${h.verseRef} and added a note. Berean surfaced it so you can continue that thread of thought.`
        : 'You highlighted and annotated this verse. Berean surfaced it so you can continue that thread of thought.';
    }

    case 'seasonal':
    case 'Seasonal Rhythm': {
      const season = data?.seasonal?.liturgicalSeason ?? sourceDetail ?? 'this season';
      return `You opted into seasonal prompts during onboarding. The church calendar is in ${season}.`;
    }

    default:
      return 'You selected this type of content in your Berean preferences.';
  }
};

// ─── useBereanData ────────────────────────────────────────────────────────────
// React hook (useState must be in scope).
// selectedTopics defaults to mockData.user.selectedTopics when null/undefined.
//
// Returns:
//   { user, readingPlan, prayerList, sanctuaries, highlights, memoryVerses,
//     seasonal, dailyCards, getVerse, whySeeingThis, status }
//
// status: "ready" | "preparing" | "empty"
//   - "ready"     → dailyCards.length > 0
//   - "empty"     → user has no selectedTopics
//   - "preparing" → selectedTopics present but all data is null (not yet possible in mock)

const useBereanData = (selectedTopics = null) => {
  const effectiveTopics = selectedTopics ?? mockData.user.selectedTopics;

  // status logic
  let status = 'ready';
  if (!effectiveTopics || effectiveTopics.length === 0) {
    status = 'empty';
  }

  // Build a synthetic userData object by merging mockData fields the assembler needs
  const userData = {
    ...mockData.user,
    selectedTopics:  effectiveTopics,
    readingPlan:     mockData.readingPlan,
    prayerList:      mockData.prayerList,
    sanctuaries:     mockData.sanctuaries,
    highlights:      mockData.highlights,
    memoryVerses:    mockData.memoryVerses,
    seasonal:        mockData.seasonal,
  };

  const dailyCards = status === 'empty'
    ? []
    : assembleDailyCards(userData, effectiveTopics);

  if (status === 'ready' && dailyCards.length === 0) {
    status = 'empty';
  }

  return {
    // Raw data (consumed by card renderers directly)
    user:         mockData.user,
    readingPlan:  mockData.readingPlan,
    prayerList:   mockData.prayerList,
    sanctuaries:  mockData.sanctuaries,
    highlights:   mockData.highlights,
    memoryVerses: mockData.memoryVerses,
    seasonal:     mockData.seasonal,

    // Assembled card list for the feed
    dailyCards,

    // Utilities
    getVerse,
    whySeeingThis,

    // Feed status
    status,
  };
};

// === END AGENT D: DATA LAYER ===

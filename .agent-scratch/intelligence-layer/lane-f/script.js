const surfaceData = {
    "life-navigation": {
        allowed: "Calendar, route, dinner thread",
        blocked: "Journal, unrelated messages, creator-private data",
        previewTitle: "Start navigation preview",
        previewCopy: "Berean will show the route handoff and the memory it used before anything starts."
    },
    relationship: {
        allowed: "Current thread, Sunday notes, saved event address",
        blocked: "Private notebook entries, other conversations, creator-private data",
        previewTitle: "Send reply preview",
        previewCopy: "Berean will show the reply draft, cited notes, and source chain before sending."
    },
    "creator-space": {
        allowed: "Creator-private board, verified Sunday notes, church-published source packet",
        blocked: "Personal journal, direct messages, unrelated member records",
        previewTitle: "Post to space preview",
        previewCopy: "Berean will show the pinned post draft and exclude private care signals."
    },
    notes: {
        allowed: "Personal notebook, decision trail, explicit note links",
        blocked: "Group thread messages, creator dashboards, church-published data",
        previewTitle: "Merge notes preview",
        previewCopy: "Berean will show the exact merge diff and proposed context edge before saving."
    }
};

const provenanceData = {
    "leave-now": {
        action: "Start navigation to Community Dinner at 5:42 PM.",
        original: "Calendar event: Community Dinner, saved by you.",
        capture: "Captured in personal_trip_ellie on this device.",
        processing: "bereanDetectNeedProxy, leaveNowTravelNudge, human reviewed: no.",
        retrieval: "Namespace personal_user_steph, ranking signals: event time and saved destination."
    },
    "reply-summary": {
        action: "Send a reply with Sunday notes and the dinner address.",
        original: "Conversation message from Mara plus Sunday notes source packet.",
        capture: "Captured inside conversation_small_group with explicit participants.",
        processing: "bereanSummarizeContextProxy, contextBeforeReply, human reviewed: no.",
        retrieval: "Namespaces conversation_small_group and church_published_local, cited claims only."
    },
    "creator-post": {
        action: "Post a pinned note that explains where Sunday notes live.",
        original: "Verified Sunday notes and creator-private member care board.",
        capture: "Captured inside creator_private_space_21 with owner access.",
        processing: "bereanSuggestFollowUpProxy, postToSpace preview, human reviewed: no.",
        retrieval: "Creator-private namespace used for need detection; public post uses verified notes only."
    },
    "merge-notes": {
        action: "Merge two notebook notes and create a relatedTo context edge.",
        original: "Two human notes in the personal notebook.",
        capture: "Captured inside personal_user_steph boundary.",
        processing: "bereanLinkThoughtsProxy, duplicateThought, human reviewed: no.",
        retrieval: "Namespace personal_user_steph, proposed edge requires explicit confirmation."
    }
};

const tabs = document.querySelectorAll(".surface-tab");
const panels = document.querySelectorAll("[data-panel]");
const nudges = document.querySelectorAll("[data-nudge]");
const allowed = document.querySelector("[data-allowed]");
const blocked = document.querySelector("[data-blocked]");
const previewTitle = document.querySelector("[data-preview-title]");
const previewCopy = document.querySelector("[data-preview-copy]");
const dialog = document.querySelector(".preview-dialog");
const panel = document.querySelector(".berean-panel");

function setSurface(surface) {
    document.querySelector(".app-shell").dataset.activeSurface = surface;

    tabs.forEach((tab) => {
        tab.classList.toggle("is-active", tab.dataset.surface === surface);
    });

    panels.forEach((item) => {
        item.classList.toggle("active", item.dataset.panel === surface);
    });

    nudges.forEach((item) => {
        item.classList.toggle("active", item.dataset.nudge === surface);
    });

    const data = surfaceData[surface];
    allowed.textContent = data.allowed;
    blocked.textContent = data.blocked;
    previewTitle.textContent = data.previewTitle;
    previewCopy.textContent = data.previewCopy;
}

function openPreview(key = "leave-now") {
    const data = provenanceData[key];
    document.querySelector("[data-dialog-action]").textContent = data.action;
    document.querySelector("[data-source-original]").textContent = data.original;
    document.querySelector("[data-source-capture]").textContent = data.capture;
    document.querySelector("[data-source-processing]").textContent = data.processing;
    document.querySelector("[data-source-retrieval]").textContent = data.retrieval;
    dialog.showModal();
}

tabs.forEach((tab) => {
    tab.addEventListener("click", () => setSurface(tab.dataset.surface));
});

document.querySelectorAll("[data-provenance]").forEach((button) => {
    button.addEventListener("click", () => openPreview(button.dataset.provenance));
});

document.querySelector("[data-open-preview]").addEventListener("click", () => {
    const activeSurface = document.querySelector(".app-shell").dataset.activeSurface;
    const keyBySurface = {
        "life-navigation": "leave-now",
        relationship: "reply-summary",
        "creator-space": "creator-post",
        notes: "merge-notes"
    };

    openPreview(keyBySurface[activeSurface]);
});

document.querySelectorAll("[data-close-preview]").forEach((button) => {
    button.addEventListener("click", () => dialog.close());
});

document.querySelector("[data-toggle-panel]").addEventListener("click", (event) => {
    panel.classList.toggle("is-collapsed");
    event.currentTarget.textContent = panel.classList.contains("is-collapsed") ? "+" : "–";
});

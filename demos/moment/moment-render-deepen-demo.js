const sheet = document.querySelector("#deepen-sheet");
const deepenTrigger = document.querySelector("[data-action-family='Deepen']");
const dismissButton = document.querySelector("[data-dismiss-sheet]");
const actionRows = document.querySelectorAll("[data-deepen-action]");

function setSheetExpanded(isExpanded) {
    deepenTrigger?.setAttribute("aria-expanded", String(isExpanded));
    sheet?.setAttribute("data-sheet-state", isExpanded ? "open" : "dismissed");
}

dismissButton?.addEventListener("click", () => {
    sheet?.classList.add("is-dismissed");
    setSheetExpanded(false);
});

deepenTrigger?.addEventListener("click", () => {
    sheet?.classList.remove("is-dismissed");
    setSheetExpanded(true);
});

actionRows.forEach((row) => {
    row.addEventListener("click", () => {
        actionRows.forEach((item) => item.classList.remove("is-selected"));
        row.classList.add("is-selected");
    });
});

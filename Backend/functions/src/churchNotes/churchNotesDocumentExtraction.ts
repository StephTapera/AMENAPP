import AdmZip from "adm-zip";

export type DocumentSourceAttribution = {
    pageNumber: number;
    text: string;
    source: "pdf_ocr" | "pptx_slide_text";
};

function decodeXmlText(value: string): string {
    return value
        .replace(/&amp;/g, "&")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&quot;/g, "\"")
        .replace(/&apos;/g, "'")
        .replace(/\s+/g, " ")
        .trim();
}

export function extractPptxSlideText(buffer: Buffer, maxChars = 40_000): {
    extractedText: string;
    pageAttributions: DocumentSourceAttribution[];
} {
    const zip = new AdmZip(buffer);
    const slideEntries = zip.getEntries()
        .filter((entry) => /^ppt\/slides\/slide\d+\.xml$/i.test(entry.entryName))
        .sort((a, b) => {
            const aNum = Number(a.entryName.match(/slide(\d+)\.xml$/i)?.[1] ?? "0");
            const bNum = Number(b.entryName.match(/slide(\d+)\.xml$/i)?.[1] ?? "0");
            return aNum - bNum;
        });

    const pageAttributions = slideEntries
        .map((entry) => {
            const slideNumber = Number(entry.entryName.match(/slide(\d+)\.xml$/i)?.[1] ?? "0");
            const xml = entry.getData().toString("utf8");
            const textRuns = Array.from(xml.matchAll(/<a:t>([\s\S]*?)<\/a:t>/g))
                .map((match) => decodeXmlText(match[1]))
                .filter((text) => text.length > 0);
            return {
                pageNumber: slideNumber,
                text: textRuns.join("\n"),
                source: "pptx_slide_text" as const,
            };
        })
        .filter((slide) => slide.text.length > 0);

    return {
        pageAttributions,
        extractedText: pageAttributions
            .map((slide) => `[Slide ${slide.pageNumber}]\n${slide.text}`)
            .join("\n\n")
            .slice(0, maxChars),
    };
}

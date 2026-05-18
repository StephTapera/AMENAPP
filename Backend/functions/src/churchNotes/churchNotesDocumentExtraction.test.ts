import AdmZip from "adm-zip";
import { extractPptxSlideText } from "./churchNotesImageOCR";

function makePptx(slides: string[]): Buffer {
    const zip = new AdmZip();
    slides.forEach((text, index) => {
        const runs = text
            .split("\n")
            .map((line) => `<a:r><a:t>${line}</a:t></a:r>`)
            .join("");
        zip.addFile(`ppt/slides/slide${index + 1}.xml`, Buffer.from(`<p:sld>${runs}</p:sld>`));
    });
    return zip.toBuffer();
}

describe("Church Notes document extraction", () => {
    it("extracts PPTX slide text with slide attribution", () => {
        const buffer = makePptx([
            "Romans 8:28\nGod works all things together",
            "Prayer prompts & action items",
        ]);

        const result = extractPptxSlideText(buffer);

        expect(result.extractedText).toContain("[Slide 1]");
        expect(result.extractedText).toContain("Romans 8:28");
        expect(result.extractedText).toContain("[Slide 2]");
        expect(result.extractedText).toContain("Prayer prompts & action items");
        expect(result.pageAttributions).toEqual([
            {
                pageNumber: 1,
                text: "Romans 8:28\nGod works all things together",
                source: "pptx_slide_text",
            },
            {
                pageNumber: 2,
                text: "Prayer prompts & action items",
                source: "pptx_slide_text",
            },
        ]);
    });

    it("returns no text for PPTX files with no slide text runs", () => {
        const zip = new AdmZip();
        zip.addFile("ppt/slides/slide1.xml", Buffer.from("<p:sld></p:sld>"));

        const result = extractPptxSlideText(zip.toBuffer());

        expect(result.extractedText).toBe("");
        expect(result.pageAttributions).toEqual([]);
    });
});

declare module "adm-zip" {
    export interface IZipEntry {
        entryName: string;
        getData(): Buffer;
    }

    export default class AdmZip {
        constructor(input: Buffer);
        getEntries(): IZipEntry[];
    }
}

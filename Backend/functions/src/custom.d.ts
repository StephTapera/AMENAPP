/**
 * custom.d.ts
 *
 * Minimal type declarations for packages whose types are not being resolved
 * by tsc (either @types package not yet installed, or module resolution gap).
 *
 * These declarations are scoped precisely to what the codebase actually uses,
 * so they won't mask genuine type errors elsewhere.
 *
 * Once `npm install` is run in Backend/functions/ with the updated package.json,
 * @types/uuid will be installed and the uuid block here can be removed.
 * The @google-cloud/vision block can be removed when the module resolves cleanly.
 */

// ─── uuid ────────────────────────────────────────────────────────────────────

declare module "uuid" {
    /** Generates a random (v4) UUID string. */
    export function v4(): string;
    /** Generates a time-based (v1) UUID string. */
    export function v1(): string;
}

// ─── @google-cloud/vision ────────────────────────────────────────────────────

declare module "@google-cloud/vision" {
    export interface SafeSearchAnnotation {
        adult?: number | null;
        spoof?: number | null;
        medical?: number | null;
        violence?: number | null;
        racy?: number | null;
        childSafety?: number | null;
    }

    export interface AnnotateImageResponse {
        // Typed as ISafeSearchAnnotation-compatible shape so assignments in
        // mediaScanning.ts compile: `safeSearch = result.safeSearchAnnotation ?? {}`
        safeSearchAnnotation?: {
            adult?: number | null;
            spoof?: number | null;
            medical?: number | null;
            violence?: number | null;
            racy?: number | null;
            childSafety?: number | null;
        } | null;
        error?: { code?: number; message?: string } | null;
    }

    export interface ImageSource {
        imageUri?: string;
        gcsImageUri?: string;
    }

    export interface Image {
        source?: ImageSource;
        content?: string | Buffer;
    }

    export class ImageAnnotatorClient {
        constructor(options?: Record<string, unknown>);
        safeSearchDetection(
            request: string | { image: Image }
        ): Promise<[AnnotateImageResponse]>;
    }

    export namespace protos {
        export namespace google {
            export namespace cloud {
                export namespace vision {
                    export namespace v1 {
                        export enum Likelihood {
                            UNKNOWN = 0,
                            VERY_UNLIKELY = 1,
                            UNLIKELY = 2,
                            POSSIBLE = 3,
                            LIKELY = 4,
                            VERY_LIKELY = 5,
                        }
                        // Protobuf-style interface (I-prefix) for SafeSearchAnnotation.
                        // Used as a type annotation alongside the enum above.
                        export interface ISafeSearchAnnotation {
                            adult?: number | null;
                            spoof?: number | null;
                            medical?: number | null;
                            violence?: number | null;
                            racy?: number | null;
                            childSafety?: number | null;
                        }
                    }
                }
            }
        }
    }
}

// ─── adm-zip ────────────────────────────────────────────────────────────────

declare module "adm-zip" {
    export interface IZipEntry {
        entryName: string;
        getData(): Buffer;
    }

    export default class AdmZip {
        constructor(input?: Buffer);
        addFile(path: string, content: Buffer): void;
        toBuffer(): Buffer;
        getEntries(): IZipEntry[];
    }
}

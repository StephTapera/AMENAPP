import * as admin from "firebase-admin";
import * as path from "path";
import * as os from "os";
import * as fs from "fs";
import ffmpeg from "fluent-ffmpeg";
// eslint-disable-next-line @typescript-eslint/no-var-requires
const ffmpegPath = require("ffmpeg-static");

ffmpeg.setFfmpegPath(ffmpegPath);

export const downloadToTmp = async (storagePath: string): Promise<string> => {
    const bucket = admin.storage().bucket();
    const tempFilePath = path.join(os.tmpdir(), path.basename(storagePath));
    await bucket.file(storagePath).download({ destination: tempFilePath });
    return tempFilePath;
};

export const uploadFromTmp = async (localPath: string, storagePath: string): Promise<void> => {
    const bucket = admin.storage().bucket();
    await bucket.upload(localPath, { destination: storagePath, resumable: false });
};

export const createProxyVideo = async (inputPath: string, outputPath: string): Promise<void> => {
    await new Promise<void>((resolve, reject) => {
        ffmpeg(inputPath)
            .outputOptions([
                "-vf scale=-2:720",
                "-preset veryfast",
                "-crf 28",
                "-movflags +faststart"
            ])
            .output(outputPath)
            .on("end", () => resolve())
            .on("error", (err) => reject(err))
            .run();
    });
};

export const createThumbnailImage = async (inputPath: string, outputPath: string): Promise<void> => {
    await new Promise<void>((resolve, reject) => {
        ffmpeg(inputPath)
            .outputOptions(["-frames:v 1", "-q:v 2"])
            .seekInput(1)
            .output(outputPath)
            .on("end", () => resolve())
            .on("error", (err) => reject(err))
            .run();
    });
};

export const cleanupTmp = (filePath: string) => {
    if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
    }
};

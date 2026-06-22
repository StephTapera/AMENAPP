"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.cleanupTmp = exports.createThumbnailImage = exports.createProxyVideo = exports.uploadFromTmp = exports.downloadToTmp = void 0;
const admin = __importStar(require("firebase-admin"));
const path = __importStar(require("path"));
const os = __importStar(require("os"));
const fs = __importStar(require("fs"));
const fluent_ffmpeg_1 = __importDefault(require("fluent-ffmpeg"));
// eslint-disable-next-line @typescript-eslint/no-var-requires
const ffmpegPath = require("ffmpeg-static");
fluent_ffmpeg_1.default.setFfmpegPath(ffmpegPath);
const downloadToTmp = async (storagePath) => {
    const bucket = admin.storage().bucket();
    const tempFilePath = path.join(os.tmpdir(), path.basename(storagePath));
    await bucket.file(storagePath).download({ destination: tempFilePath });
    return tempFilePath;
};
exports.downloadToTmp = downloadToTmp;
const uploadFromTmp = async (localPath, storagePath) => {
    const bucket = admin.storage().bucket();
    await bucket.upload(localPath, { destination: storagePath, resumable: false });
};
exports.uploadFromTmp = uploadFromTmp;
const createProxyVideo = async (inputPath, outputPath) => {
    await new Promise((resolve, reject) => {
        (0, fluent_ffmpeg_1.default)(inputPath)
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
exports.createProxyVideo = createProxyVideo;
const createThumbnailImage = async (inputPath, outputPath) => {
    await new Promise((resolve, reject) => {
        (0, fluent_ffmpeg_1.default)(inputPath)
            .outputOptions(["-frames:v 1", "-q:v 2"])
            .seekInput(1)
            .output(outputPath)
            .on("end", () => resolve())
            .on("error", (err) => reject(err))
            .run();
    });
};
exports.createThumbnailImage = createThumbnailImage;
const cleanupTmp = (filePath) => {
    if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
    }
};
exports.cleanupTmp = cleanupTmp;
//# sourceMappingURL=ffmpegUtils.js.map
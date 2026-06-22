"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.momentCrossReference = void 0;
const https_1 = require("firebase-functions/v2/https");
const shared_1 = require("./shared");
exports.momentCrossReference = (0, https_1.onCall)({ region: shared_1.MOMENT_REGION, enforceAppCheck: true }, (0, shared_1.makeDeepenHandler)("crossReference"));

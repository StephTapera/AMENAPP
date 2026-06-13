"use strict";
// capabilities/scripture/index.ts — Scripture Intelligence module (Wave 1: Lane B)
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseRefs = exports.detectReferencesInBlocks = exports.detectReferences = exports.scripture_searchVerses = exports.scripture_getVerses = exports.scripture_detectReferences = void 0;
var callables_1 = require("./callables");
Object.defineProperty(exports, "scripture_detectReferences", { enumerable: true, get: function () { return callables_1.scripture_detectReferences; } });
Object.defineProperty(exports, "scripture_getVerses", { enumerable: true, get: function () { return callables_1.scripture_getVerses; } });
Object.defineProperty(exports, "scripture_searchVerses", { enumerable: true, get: function () { return callables_1.scripture_searchVerses; } });
var referenceParser_1 = require("./referenceParser");
Object.defineProperty(exports, "detectReferences", { enumerable: true, get: function () { return referenceParser_1.detectReferences; } });
Object.defineProperty(exports, "detectReferencesInBlocks", { enumerable: true, get: function () { return referenceParser_1.detectReferencesInBlocks; } });
Object.defineProperty(exports, "parseRefs", { enumerable: true, get: function () { return referenceParser_1.parseRefs; } });

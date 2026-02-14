/**
 * Cloud Functions Index
 * Exports all functions for deployment
 */

const moderation = require("./moderation");
const crisisDetection = require("./crisis-detection");

// Export all functions
exports.moderatePost = moderation.moderatePost;
exports.moderateComment = moderation.moderateComment;
exports.checkContent = moderation.checkContent;
exports.detectCrisis = crisisDetection.detectCrisis;

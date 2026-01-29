/**
 * Firebase Cloud Functions for AMENAPP
 * 
 * Handles:
 * - Push notifications
 * - Real-time messaging
 * - Background tasks
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// Initialize Firebase Admin
admin.initializeApp();

// Import function modules
export * from "./notifications";
export * from "./messaging";

// Health check function
export const healthCheck = functions.https.onRequest((request, response) => {
  response.json({
    status: "healthy",
    timestamp: new Date().toISOString(),
    version: "1.0.0",
  });
});

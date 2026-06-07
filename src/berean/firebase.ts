/**
 * firebase.ts — Firebase client SDK initialization for Berean v1 React prototype
 *
 * Import this file first in any component that uses Firebase services.
 * All service singletons are exported from here.
 *
 * Config values are from the Firebase project amen-5e359.
 * These are public-safe web config values (not secrets) — Firebase restricts
 * access via Security Rules and Auth, not by hiding this config.
 */

import { initializeApp, getApps, getApp, type FirebaseApp } from 'firebase/app';
import { getFirestore, type Firestore } from 'firebase/firestore';
import { getFunctions, type Functions } from 'firebase/functions';
import { getAuth, type Auth } from 'firebase/auth';

// ─────────────────────────────────────────────────────────────────────────────
// FIREBASE WEB CONFIG
// These values are safe to include in the client bundle — Firebase Security
// Rules and Authentication govern what each user can access.
// ─────────────────────────────────────────────────────────────────────────────

const FIREBASE_CONFIG = {
  apiKey:            import.meta.env.VITE_FIREBASE_API_KEY            ?? '',
  authDomain:        import.meta.env.VITE_FIREBASE_AUTH_DOMAIN        ?? 'amen-5e359.firebaseapp.com',
  projectId:         import.meta.env.VITE_FIREBASE_PROJECT_ID         ?? 'amen-5e359',
  storageBucket:     import.meta.env.VITE_FIREBASE_STORAGE_BUCKET     ?? 'amen-5e359.appspot.com',
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID ?? '',
  appId:             import.meta.env.VITE_FIREBASE_APP_ID             ?? '',
};

// ─────────────────────────────────────────────────────────────────────────────
// SINGLETON INIT — safe to import from multiple modules
// ─────────────────────────────────────────────────────────────────────────────

export const app: FirebaseApp = getApps().length
  ? getApp()
  : initializeApp(FIREBASE_CONFIG);

export const db: Firestore = getFirestore(app);

export const functions: Functions = getFunctions(app, 'us-central1');

export const auth: Auth = getAuth(app);

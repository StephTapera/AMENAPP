/**
 * voiceService.ts — Berean Phase 2B Voice Service
 * Pure TypeScript: no React, no client-side API keys.
 *
 * CLEAN-END GUARDRAIL: endSession() terminates immediately, silently.
 * No re-engagement prompts. No "want to continue?" No auto-restart.
 */

import {
  VoiceMode,
  VoicePersona,
  VoiceSpeed,
  BereanCapabilities,
} from '../contracts';

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

export interface VoiceSettings {
  persona: VoicePersona;
  speed: VoiceSpeed;
  language: string;
  mode: VoiceMode;
}

export interface VoiceSessionState {
  active: boolean;
  mode: VoiceMode;
  persona: VoicePersona;
  speed: VoiceSpeed;
  language: string;
  isListening: boolean;
  isSpeaking: boolean;
}

type SessionListener = (state: VoiceSessionState) => void;

// ─────────────────────────────────────────────────────────────────────────────
// Default state
// ─────────────────────────────────────────────────────────────────────────────

const DEFAULT_STATE: VoiceSessionState = {
  active: false,
  mode: 'push_to_talk',
  persona: 'still',
  speed: 'normal',
  language: 'en',
  isListening: false,
  isSpeaking: false,
};

// ─────────────────────────────────────────────────────────────────────────────
// VoiceService
// ─────────────────────────────────────────────────────────────────────────────

class VoiceService {
  private state: VoiceSessionState = { ...DEFAULT_STATE };
  private listeners: Set<SessionListener> = new Set();

  // ── Subscriptions ──────────────────────────────────────────────────────────

  subscribe(listener: SessionListener): () => void {
    this.listeners.add(listener);
    // Emit current state immediately so new subscribers are in sync
    listener({ ...this.state });
    return () => {
      this.listeners.delete(listener);
    };
  }

  private emit(): void {
    const snapshot = { ...this.state };
    this.listeners.forEach((l) => l(snapshot));
  }

  // ── Session control ────────────────────────────────────────────────────────

  startSession(mode: VoiceMode): void {
    this.state = {
      ...this.state,
      active: true,
      mode,
      isListening: mode === 'hands_free',
      isSpeaking: false,
    };
    this.emit();
  }

  /**
   * CLEAN-END GUARDRAIL
   * Session ends immediately. No prompt, no hook, no deferred callback.
   * Caller is responsible for navigation back to the previous screen.
   */
  endSession(): void {
    this.state = {
      ...DEFAULT_STATE,
      // Preserve persona/speed/language across sessions (user settings)
      persona: this.state.persona,
      speed: this.state.speed,
      language: this.state.language,
    };
    this.emit();
    // Silent log only — no toast, no follow-up prompt
    if (process.env.NODE_ENV !== 'production') {
      console.debug('[VoiceService] session ended');
    }
  }

  // ── Push-to-talk ───────────────────────────────────────────────────────────

  holdToSpeak(): void {
    if (!this.state.active || this.state.mode !== 'push_to_talk') return;
    this.state = { ...this.state, isListening: true, isSpeaking: false };
    this.emit();
  }

  releaseToSpeak(): void {
    if (!this.state.active || this.state.mode !== 'push_to_talk') return;
    // Stop listening; caller should submit audio buffer at this point
    this.state = { ...this.state, isListening: false };
    this.emit();
  }

  // ── Speaking state ─────────────────────────────────────────────────────────

  /** Called by TTS layer when audio playback begins */
  setSpeaking(value: boolean): void {
    if (!this.state.active) return;
    this.state = {
      ...this.state,
      isSpeaking: value,
      // In hands-free mode, resume listening once speaking finishes
      isListening: !value && this.state.mode === 'hands_free',
    };
    this.emit();
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  setPersona(persona: VoicePersona): void {
    this.state = { ...this.state, persona };
    this.emit();
  }

  setSpeed(speed: VoiceSpeed): void {
    this.state = { ...this.state, speed };
    this.emit();
  }

  setLanguage(language: string): void {
    this.state = { ...this.state, language };
    this.emit();
  }

  getState(): Readonly<VoiceSessionState> {
    return { ...this.state };
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  /**
   * Persists voice settings to Firestore at berean/{uid}/capabilities
   * (voice sub-object).  Uses the Firebase client SDK — no API key embedded.
   * Caller must pass a Firestore `doc` reference or equivalent write fn so
   * this service remains Firebase-version-agnostic.
   */
  async saveSettings(
    userId: string,
    settings: VoiceSettings,
    /**
     * Injected writer: (path: string, data: object) => Promise<void>
     * Accepts a thin wrapper around Firestore setDoc / updateDoc.
     * This keeps the service free of direct Firebase imports.
     */
    firestoreWriter: (path: string, data: Record<string, unknown>) => Promise<void>
  ): Promise<void> {
    if (!userId || userId.trim() === '') {
      throw new Error('VoiceService.saveSettings: userId is required');
    }

    const path = `berean/${userId}/capabilities`;
    const payload: Record<string, unknown> = {
      'voice.persona': settings.persona,
      'voice.speed': settings.speed,
      'voice.language': settings.language,
      'voice.mode': settings.mode,
    };

    await firestoreWriter(path, payload);

    // Mirror to in-memory state
    this.state = {
      ...this.state,
      persona: settings.persona,
      speed: settings.speed,
      language: settings.language,
      mode: settings.mode,
    };
    this.emit();
  }
}

// Singleton — one session active at a time across the app
export const voiceService = new VoiceService();

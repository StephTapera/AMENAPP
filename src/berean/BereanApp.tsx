/**
 * BereanApp.tsx — Berean v1 Root Application Component
 *
 * Entry point for the React prototype. Wraps all screens in BereanProvider
 * and provides a tab-based shell (Chat | Voice | Usage | Connectors | Settings).
 *
 * Import firebase.ts before mounting this component to initialise Firebase.
 */

import React, { useState, useEffect } from 'react';
import { onAuthStateChanged, signInAnonymously, type User } from 'firebase/auth';
import { doc, setDoc } from 'firebase/firestore';

import { auth, db } from './firebase';
import { BereanProvider, useBerean } from './core/BereanCore';
import VoiceSettings from './voice/VoiceSettings';
import VoiceSession from './voice/VoiceSession';
import UsageMeters from './usage/UsageMeters';
import ConnectorsScreen from './connectors/ConnectorsScreen';
import CapabilitiesScreen from './controls/CapabilitiesScreen';
import { tokens } from './contracts';

// ── Connected Intelligence v1 surfaces (src/features/**) ──────────────────────
import { ResponseActionSheet } from '../features/actionSheet';
import { MentionComposer } from '../features/berean/composer';
import { DailyBriefCard } from '../features/brief';
import { NotebooksScreen } from '../features/notebooks';
import { ScheduledActionsScreen } from '../features/scheduled';

// ─────────────────────────────────────────────────────────────────────────────
// NAV TABS
// ─────────────────────────────────────────────────────────────────────────────

type Tab =
  | 'today'
  | 'chat'
  | 'notebooks'
  | 'scheduled'
  | 'voice'
  | 'usage'
  | 'connectors'
  | 'settings';

const TABS: { id: Tab; label: string; icon: string }[] = [
  { id: 'today',      label: 'Today',       icon: '◔' },
  { id: 'chat',       label: 'Berean',      icon: '✦' },
  { id: 'notebooks',  label: 'Notebooks',   icon: '▤' },
  { id: 'scheduled',  label: 'Scheduled',   icon: '◷' },
  { id: 'voice',      label: 'Voice',        icon: '♪' },
  { id: 'usage',      label: 'Usage',        icon: '◑' },
  { id: 'connectors', label: 'Connectors',  icon: '⊕' },
  { id: 'settings',  label: 'Settings',    icon: '⚙' },
];

// ─────────────────────────────────────────────────────────────────────────────
// CHAT SCREEN — uses useBerean() from context
// ─────────────────────────────────────────────────────────────────────────────

type ChatMessage = {
  id: string;
  role: 'user' | 'berean';
  text: string;
  refusal?: string;
  // Connected Intelligence: canonical provenance carried so the action sheet can
  // stamp every created object and so transforms inherit the source domain.
  domain?: import('./contracts').Domain;
  provenance?: { sources: unknown[]; truthLevel: string };
};

function ChatScreen() {
  const { sendMessage, context } = useBerean();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [loading, setLoading] = useState(false);
  // Stable thread id for continue_later / resume + transform provenance pointers.
  const [threadId] = useState(() => `thread_${Date.now().toString(36)}`);

  // Wrap sendMessage so the transcript captures the assistant turn + provenance.
  // MentionComposer owns the INPUT only; the transcript stays the parent's job.
  const wrappedSend = async (input: string, domain: import('./contracts').Domain) => {
    const result = await sendMessage(input, domain);
    if (result.refusal === 'crisis_handoff') {
      setMessages((prev) => [...prev, {
        id: `m_${Date.now()}_${prev.length}`,
        role: 'berean',
        text: 'If you\'re going through a crisis, please reach out to real support:',
        refusal: 'crisis_handoff',
        domain,
        provenance: result.provenance ?? { sources: [], truthLevel: 'refused' },
      }]);
    } else {
      setMessages((prev) => [...prev, {
        id: `m_${Date.now()}_${prev.length}`,
        role: 'berean',
        text: result.text,
        domain,
        provenance: result.provenance ?? { sources: [], truthLevel: 'inferred' },
      }]);
    }
    return result;
  };

  const cardStyle: React.CSSProperties = {
    backgroundColor: tokens.card,
    borderRadius: tokens.radius,
    padding: '12px 16px',
    marginBottom: 8,
    boxShadow: tokens.shadow,
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif',
    fontSize: 15,
    lineHeight: 1.5,
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ flex: 1, overflowY: 'auto', padding: '16px 16px 0' }}>
        {messages.length === 0 && (
          <div style={{ ...cardStyle, color: tokens.textSub, fontSize: 14, textAlign: 'center', marginTop: 40 }}>
            <div style={{ fontSize: 28, marginBottom: 8 }}>✦</div>
            <div style={{ fontWeight: 600, color: tokens.text, marginBottom: 4 }}>Ask Berean anything</div>
            <div>Scripture, prayer, theology, pastoral guidance.</div>
            <div style={{ marginTop: 8, fontSize: 12 }}>Formation over engagement. Berean gets out of the way.</div>
          </div>
        )}
        {messages.map((msg, i) => (
          <div key={msg.id ?? i} style={{ marginBottom: 8 }}>
            <div style={{
              ...cardStyle,
              marginBottom: 0,
              alignSelf: msg.role === 'user' ? 'flex-end' : 'flex-start',
              backgroundColor: msg.role === 'user' ? tokens.accent : tokens.card,
              color: msg.role === 'user' ? '#fff' : tokens.text,
              marginLeft: msg.role === 'user' ? 40 : 0,
              marginRight: msg.role === 'user' ? 0 : 40,
            }}>
              {msg.text}
              {msg.refusal === 'crisis_handoff' && (
                <div style={{ marginTop: 8, color: tokens.text, fontSize: 13 }}>
                  <div>• <strong>988</strong> — Suicide & Crisis Lifeline (call or text)</div>
                  <div>• Text <strong>HOME</strong> to <strong>741741</strong> — Crisis Text Line</div>
                  <div>• <strong>1-800-799-7233</strong> — National Domestic Violence Hotline</div>
                </div>
              )}
            </div>
            {/* Connected Intelligence: action pill + sheet under every Berean response.
                Suppressed for crisis hand-offs (transforms never run on crisis content). */}
            {msg.role === 'berean' && msg.refusal !== 'crisis_handoff' && (
              <div style={{ marginRight: 40, marginTop: 4 }}>
                <ResponseActionSheet
                  response={{
                    responseId: msg.id ?? `resp_${i}`,
                    domain: msg.domain ?? 'general',
                    text: msg.text,
                    provenance: (msg.provenance ?? { sources: [], truthLevel: 'grounded' }) as never,
                    threadId,
                    conversationState: {
                      threadId,
                      domain: msg.domain ?? 'general',
                      messages: messages.map((m) => ({ role: m.role, text: m.text })),
                    } as never,
                  }}
                />
              </div>
            )}
          </div>
        ))}
        {loading && (
          <div style={{ ...cardStyle, color: tokens.textSub, fontSize: 13 }}>Berean is thinking…</div>
        )}
      </div>
      {/* Connected Intelligence: @mention composer (calendar/music via live grants).
          Owns the input row, the @-picker, degraded chips, and the calendar draft
          card. Mentions are the ONLY way connector context enters a Berean turn. */}
      <div style={{ padding: 16, borderTop: `1px solid ${tokens.divider}` }}>
        <MentionComposer
          userId={context.userId}
          minorScoped={context.minorScoped}
          sendMessage={wrappedSend}
          onUserSubmit={(raw) => {
            setMessages((prev) => [...prev, {
              id: `m_${Date.now()}_${prev.length}`,
              role: 'user',
              text: raw,
            }]);
            setLoading(true);
          }}
          onResolved={() => setLoading(false)}
        />
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB SHELL
// ─────────────────────────────────────────────────────────────────────────────

function BereanShell({ userId }: { userId: string }) {
  const [tab, setTab] = useState<Tab>('chat');
  const [voiceActive, setVoiceActive] = useState(false);

  const firestoreWriter = async (path: string, data: Record<string, unknown>): Promise<void> => {
    const segments = path.split('/');
    const ref = doc(db, segments[0], ...segments.slice(1));
    await setDoc(ref, data, { merge: true });
  };

  const tabBarStyle: React.CSSProperties = {
    display: 'flex', borderTop: `1px solid ${tokens.divider}`,
    backgroundColor: tokens.card, padding: '4px 0',
  };

  const tabStyle = (active: boolean): React.CSSProperties => ({
    flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center',
    padding: '6px 4px', border: 'none', background: 'none', cursor: 'pointer',
    color: active ? tokens.accent : tokens.textSub,
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif',
    fontSize: 10, fontWeight: active ? 600 : 400,
  });

  const screenStyle: React.CSSProperties = {
    flex: 1, overflowY: 'auto', backgroundColor: tokens.bg,
  };

  return (
    <BereanProvider userId={userId} plan="free">
      <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', backgroundColor: tokens.bg }}>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          {voiceActive ? (
            <VoiceSession
              mode="push_to_talk"
              persona="still"
              onEnd={() => setVoiceActive(false)}
            />
          ) : (
            <div style={screenStyle}>
              {tab === 'today'      && (
                <div style={{ padding: 16 }}>
                  <DailyBriefCard
                    userId={userId}
                    minorScoped={false}
                    onOpenPointer={(pointer) => {
                      // amen:// deep link — open via the host router when embedded
                      // natively; in the web prototype, navigate the address bar.
                      if (typeof window !== 'undefined' && pointer) {
                        window.location.assign(pointer);
                      }
                    }}
                    onOpenSafety={() => setTab('chat')}
                  />
                </div>
              )}
              {tab === 'chat'       && <ChatScreen />}
              {tab === 'notebooks'  && <NotebooksScreen userId={userId} />}
              {tab === 'scheduled'  && <ScheduledActionsScreen userId={userId} plan="free" />}
              {tab === 'voice'      && (
                <div style={{ display: 'flex', flexDirection: 'column' }}>
                  <VoiceSettings userId={userId} firestoreWriter={firestoreWriter} />
                  <div style={{ padding: '0 16px 24px' }}>
                    <button
                      onClick={() => setVoiceActive(true)}
                      style={{
                        width: '100%', padding: '14px', borderRadius: tokens.radius,
                        border: 'none', backgroundColor: tokens.accent, color: '#fff',
                        fontSize: 16, fontWeight: 600, cursor: 'pointer',
                        fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif',
                      }}
                    >
                      Begin Voice Session
                    </button>
                  </div>
                </div>
              )}
              {tab === 'usage'      && <UsageMeters userId={userId} />}
              {tab === 'connectors' && <ConnectorsScreen userId={userId} minorScoped={false} />}
              {tab === 'settings'   && <CapabilitiesScreen userId={userId} />}
            </div>
          )}
        </div>
        {!voiceActive && (
          <nav style={tabBarStyle}>
            {TABS.map(({ id, label, icon }) => (
              <button key={id} style={tabStyle(tab === id)} onClick={() => setTab(id)}>
                <span style={{ fontSize: 18, marginBottom: 2 }}>{icon}</span>
                <span>{label}</span>
              </button>
            ))}
          </nav>
        )}
      </div>
    </BereanProvider>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTH GATE
// ─────────────────────────────────────────────────────────────────────────────

export default function BereanApp() {
  const [user, setUser] = useState<User | null>(null);
  const [authReady, setAuthReady] = useState(false);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (u) => {
      if (u) {
        setUser(u);
      } else {
        const { user: anonUser } = await signInAnonymously(auth);
        setUser(anonUser);
      }
      setAuthReady(true);
    });
    return unsub;
  }, []);

  if (!authReady) {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        height: '100vh', backgroundColor: tokens.bg,
        fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif',
        color: tokens.textSub, fontSize: 14,
      }}>
        Preparing Berean…
      </div>
    );
  }

  return <BereanShell userId={user!.uid} />;
}

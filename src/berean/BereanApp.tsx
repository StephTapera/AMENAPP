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

import { auth } from './firebase';
import { BereanProvider, useBerean } from './core/BereanCore';
import VoiceSettings from './voice/VoiceSettings';
import VoiceSession from './voice/VoiceSession';
import UsageMeters from './usage/UsageMeters';
import ConnectorsScreen from './connectors/ConnectorsScreen';
import CapabilitiesScreen from './controls/CapabilitiesScreen';
import { tokens } from './contracts';

// ─────────────────────────────────────────────────────────────────────────────
// NAV TABS
// ─────────────────────────────────────────────────────────────────────────────

type Tab = 'chat' | 'voice' | 'usage' | 'connectors' | 'settings';

const TABS: { id: Tab; label: string; icon: string }[] = [
  { id: 'chat',       label: 'Berean',      icon: '✦' },
  { id: 'voice',      label: 'Voice',        icon: '♪' },
  { id: 'usage',      label: 'Usage',        icon: '◑' },
  { id: 'connectors', label: 'Connectors',  icon: '⊕' },
  { id: 'settings',  label: 'Settings',    icon: '⚙' },
];

// ─────────────────────────────────────────────────────────────────────────────
// CHAT SCREEN — uses useBerean() from context
// ─────────────────────────────────────────────────────────────────────────────

function ChatScreen() {
  const { sendMessage, context } = useBerean();
  const [input, setInput] = useState('');
  const [messages, setMessages] = useState<{ role: 'user' | 'berean'; text: string; refusal?: string }[]>([]);
  const [loading, setLoading] = useState(false);

  const handleSend = async () => {
    const text = input.trim();
    if (!text || loading) return;
    setInput('');
    setMessages((prev) => [...prev, { role: 'user', text }]);
    setLoading(true);
    try {
      const result = await sendMessage(text, 'general');
      if (result.refusal === 'crisis_handoff') {
        setMessages((prev) => [...prev, {
          role: 'berean',
          text: 'If you\'re going through a crisis, please reach out to real support:',
          refusal: 'crisis_handoff',
        }]);
      } else {
        setMessages((prev) => [...prev, { role: 'berean', text: result.text }]);
      }
    } catch (err) {
      setMessages((prev) => [...prev, { role: 'berean', text: 'Unable to reach Berean right now. Please try again.' }]);
    } finally {
      setLoading(false);
    }
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
          <div key={i} style={{
            ...cardStyle,
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
        ))}
        {loading && (
          <div style={{ ...cardStyle, color: tokens.textSub, fontSize: 13 }}>Berean is thinking…</div>
        )}
      </div>
      <div style={{ padding: 16, borderTop: `1px solid ${tokens.divider}`, display: 'flex', gap: 8 }}>
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && !e.shiftKey && handleSend()}
          placeholder="Ask Berean…"
          disabled={loading}
          style={{
            flex: 1, padding: '10px 14px', borderRadius: 12,
            border: `1px solid ${tokens.divider}`, fontSize: 15,
            fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif',
            outline: 'none', backgroundColor: tokens.card, color: tokens.text,
          }}
        />
        <button
          onClick={handleSend}
          disabled={!input.trim() || loading}
          style={{
            padding: '10px 18px', borderRadius: 12, border: 'none',
            backgroundColor: input.trim() && !loading ? tokens.accent : tokens.divider,
            color: '#fff', fontSize: 15, cursor: input.trim() && !loading ? 'pointer' : 'default',
            fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif',
          }}
        >
          Send
        </button>
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
              speed="normal"
              onEnd={() => setVoiceActive(false)}
            />
          ) : (
            <div style={screenStyle}>
              {tab === 'chat'       && <ChatScreen />}
              {tab === 'voice'      && <VoiceSettings userId={userId} onVoiceSessionStart={() => setVoiceActive(true)} />}
              {tab === 'usage'      && <UsageMeters userId={userId} />}
              {tab === 'connectors' && <ConnectorsScreen userId={userId} minorScoped={false} />}
              {tab === 'settings'   && <CapabilitiesScreen userId={userId} minorScoped={false} />}
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

/**
 * MinorExplainer.tsx — age-appropriate replacement for the Connectors Hub.
 * OWNER: Phase 2 Agent A.
 *
 * For minor-scoped accounts the ENTIRE hub is replaced by this explainer.
 * There is NO grant path in the UI — no toggles, no sheets, no CF calls.
 */

import React from 'react';
import { s } from './styles';
import { tokens } from '../../berean/contracts';

export default function MinorExplainer(): JSX.Element {
  return (
    <main style={s.screen} aria-label="Connectors">
      <div
        style={{
          ...s.card,
          textAlign: 'center',
          padding: '32px 22px',
          marginTop: 24,
        }}
      >
        <div
          aria-hidden="true"
          style={{
            fontSize: 30,
            width: 56,
            height: 56,
            borderRadius: 16,
            border: `1px solid ${tokens.divider}`,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            margin: '0 auto 16px',
            color: tokens.text,
          }}
        >
          ☺
        </div>
        <h1 style={{ ...s.heading, fontSize: 22, marginBottom: 10 }}>
          Connectors are for grown-up accounts
        </h1>
        <p style={{ fontSize: 15, color: tokens.textSub, lineHeight: 1.6, margin: '0 auto', maxWidth: 360 }}>
          Connecting outside apps like a calendar or music isn’t available on your account yet.
          You can still read the Bible, pray, take notes, and chat with Berean — all the good stuff,
          kept simple and safe for you.
        </p>
        <p style={{ fontSize: 13, color: tokens.textSub, lineHeight: 1.6, marginTop: 18 }}>
          When your account is set up for an adult, this is where you’ll connect those apps.
        </p>
      </div>
    </main>
  );
}

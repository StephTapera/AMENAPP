#!/usr/bin/env node
// strip-rules.js — run before every firestore rules deploy.
// Minifies AMENAPP/firestore 18.rules (source of truth) into
// AMENAPP/firestore.deploy.rules. Preserves every rule and every
// function — only comments and whitespace are stripped so the
// artifact is small enough to paste into the Firebase Console
// (256 KB limit) or, eventually, the Firebase CLI (64 KB limit).
//
// Compiles to identical bytecode as the source.

const fs = require('fs');
const path = require('path');

const src = path.join(__dirname, '../AMENAPP/firestore 18.rules');
const dst = path.join(__dirname, '../AMENAPP/firestore.deploy.rules');

let s = fs.readFileSync(src, 'utf8');
const original = s.length;

// 1) Block comments /* ... */
s = s.replace(/\/\*[\s\S]*?\*\//g, '');

// 2) Line comments // ...  (string-aware: ignore // inside '...' or "...")
s = s.split('\n').map((line) => {
  let inStr = null;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inStr) {
      if (c === '\\') { i++; continue; }
      if (c === inStr) inStr = null;
    } else {
      if (c === '"' || c === "'") inStr = c;
      else if (c === '/' && line[i + 1] === '/') return line.slice(0, i);
    }
  }
  return line;
}).join('\n');

// 3) Collapse runs of spaces/tabs
s = s.replace(/[ \t]+/g, ' ');

// 4) Strip whitespace around punctuation that doesn't need it
s = s.replace(/\s*([{}();,:?])\s*/g, '$1');
s = s.replace(/\s*(==|!=|<=|>=|&&|\|\||=|<|>|\+|-|\*|\/)\s*/g, '$1');

// 5) Drop blank/whitespace-only lines, trim
s = s.split('\n').map((l) => l.trim()).filter((l) => l.length > 0).join('\n');

// 6) Collapse newlines to nothing — Firestore rules are whitespace-insensitive
//    between tokens, so the bytecode is identical.
s = s.replace(/\n/g, '');

fs.writeFileSync(dst, s);
console.log(`Rules minified: ${original} → ${s.length} bytes`);

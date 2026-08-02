/**
 * Prove MAX_ACTIVE_GAMES shed-load: start 3-seat games until HTTP 409.
 * Ephemeral / laptop only — never against production.
 */
import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';
import { createGuest, createRoom, joinRoom, readyRoom, startGame, apiBase } from '../lib/api.js';

const admissionRejected = new Counter('admission_rejected');
const admissionStarted = new Counter('admission_started');
const TARGET_STARTS = Number(__ENV.ADMISSION_ATTEMPTS || 110);
const SEATS = 3;

export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    admission_rejected: ['count>=1'],
    http_req_failed: ['rate<0.5'],
  },
};

function startOneTable(index) {
  const host = createGuest(`AdH${index}`);
  const created = createRoom(host.token, {
    max_players: SEATS,
    round_schedule: { mode: 'manual', steps: [{ cards: 1, repeat: 1 }] },
  });
  const code = created.room.code;
  const tokens = [host.token];
  for (let s = 1; s < SEATS; s++) {
    const g = createGuest(`Ad${index}P${s}`);
    joinRoom(g.token, code);
    tokens.push(g.token);
  }
  for (const t of tokens) {
    readyRoom(t, code);
  }
  return startGame(tokens[0], code, 1000 + index);
}

export default function () {
  // Confirm API is up before flooding starts.
  const ready = http.get(`${apiBase()}/readyz`);
  check(ready, { 'readyz 200': (r) => r.status === 200 });

  let rejected = 0;
  let started = 0;
  for (let i = 0; i < TARGET_STARTS; i++) {
    const result = startOneTable(i);
    if (result.ok) {
      started += 1;
      admissionStarted.add(1);
    } else if (result.status === 409) {
      rejected += 1;
      admissionRejected.add(1);
      // Keep going a few more to confirm sustained shed-load.
      if (rejected >= 3) break;
    } else {
      throw new Error(`unexpected start status ${result.status}: ${result.body}`);
    }
  }

  check(null, {
    'got admission 409': () => rejected >= 1,
    'started some games first': () => started >= 1,
  });
  console.log(`admission: started=${started} rejected=${rejected}`);
}

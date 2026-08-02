import http from 'k6/http';
import { check } from 'k6';

export function apiBase() {
  return (__ENV.API_BASE || 'http://127.0.0.1:8080').replace(/\/$/, '');
}

export function wsBase() {
  return apiBase().replace(/^http/, 'ws');
}

function authHeaders(token) {
  return {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${token}`,
  };
}

export function createGuest(nickname) {
  const res = http.post(
    `${apiBase()}/api/v1/guest-sessions`,
    JSON.stringify({ nickname }),
    { headers: { 'Content-Type': 'application/json' }, tags: { name: 'guest-sessions' } },
  );
  check(res, { 'guest-session 200': (r) => r.status === 200 });
  if (res.status !== 200) {
    throw new Error(`guest-session failed: ${res.status} ${res.body}`);
  }
  return res.json();
}

export function createRoom(token, body) {
  const res = http.post(`${apiBase()}/api/v1/rooms`, JSON.stringify(body || {}), {
    headers: authHeaders(token),
    tags: { name: 'rooms-create' },
  });
  check(res, { 'create-room 200': (r) => r.status === 200 });
  if (res.status !== 200) {
    throw new Error(`create-room failed: ${res.status} ${res.body}`);
  }
  return res.json();
}

export function joinRoom(token, roomRef) {
  const res = http.post(
    `${apiBase()}/api/v1/rooms/${roomRef}/join`,
    JSON.stringify({}),
    { headers: authHeaders(token), tags: { name: 'rooms-join' } },
  );
  check(res, { 'join-room 200': (r) => r.status === 200 });
  if (res.status !== 200) {
    throw new Error(`join-room failed: ${res.status} ${res.body}`);
  }
  return res.json();
}

export function readyRoom(token, roomRef) {
  const res = http.post(
    `${apiBase()}/api/v1/rooms/${roomRef}/ready`,
    JSON.stringify({ ready: true }),
    { headers: authHeaders(token), tags: { name: 'rooms-ready' } },
  );
  check(res, { 'ready 200': (r) => r.status === 200 });
  if (res.status !== 200) {
    throw new Error(`ready failed: ${res.status} ${res.body}`);
  }
  return res.json();
}

/**
 * Start a game. Returns { ok, status, body, game_id }.
 * Pass seed=null/undefined to omit seed (required for prod).
 */
export function startGame(token, roomRef, seed) {
  const payload = seed === undefined || seed === null ? {} : { seed };
  const res = http.post(
    `${apiBase()}/api/v1/rooms/${roomRef}/start`,
    JSON.stringify(payload),
    { headers: authHeaders(token), tags: { name: 'rooms-start' } },
  );
  if (res.status === 200) {
    const body = res.json();
    return { ok: true, status: 200, body, game_id: body.game_id };
  }
  return { ok: false, status: res.status, body: res.body, game_id: null };
}

/** Short schedule for CI/prod smoke: 2 rounds × 3 cards. */
export function shortRoundSchedule() {
  return {
    mode: 'manual',
    steps: [{ cards: 3, repeat: 2 }],
  };
}

export function automaticRoundSchedule() {
  return { mode: 'automatic' };
}

/**
 * Create a seats-player table, ready everyone, start.
 * opts: { seed, schedule, omitSeed }
 */
export function createStartedTable(tableIndex, seats, opts) {
  const options = opts || {};
  const schedule =
    options.schedule ||
    (__ENV.FULL_SCHEDULE === '1' ? automaticRoundSchedule() : shortRoundSchedule());
  const omitSeed = options.omitSeed === true || __ENV.OMIT_SEED === '1';
  const seed = omitSeed
    ? null
    : options.seed !== undefined
      ? options.seed
      : 42 + tableIndex;
  const maxPlayers = seats;

  const hostNick = `H${tableIndex}`;
  const host = createGuest(hostNick);
  const created = createRoom(host.token, {
    max_players: maxPlayers,
    turn_timeout_seconds: 300,
    round_schedule: schedule,
  });
  const roomCode = created.room.code;
  const seatList = [
    { token: host.token, player_id: created.player_id, nickname: hostNick },
  ];

  for (let s = 1; s < seats; s++) {
    const nick = `T${tableIndex}P${s}`;
    const session = createGuest(nick);
    const joined = joinRoom(session.token, roomCode);
    seatList.push({
      token: session.token,
      player_id: joined.player_id,
      nickname: nick,
    });
  }

  for (const seat of seatList) {
    readyRoom(seat.token, roomCode);
  }

  const started = startGame(seatList[0].token, roomCode, seed);
  if (!started.ok) {
    throw new Error(`start failed for table ${tableIndex}: ${started.status} ${started.body}`);
  }

  return {
    game_id: started.game_id,
    room_code: roomCode,
    seats: seatList,
  };
}

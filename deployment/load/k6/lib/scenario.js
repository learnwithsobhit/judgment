import { buildThresholds } from './thresholds.js';
import { createStartedTable } from './api.js';
import { playSeatToFinish } from './ws_game.js';

/**
 * Build k6 options for N tables × seats VUs (one short game each).
 */
export function makeTableOptions(tables, seats, profile) {
  const vus = tables * seats;
  return {
    scenarios: {
      tables: {
        executor: 'per-vu-iterations',
        vus,
        iterations: 1,
        maxDuration: '12m',
        gracefulStop: '30s',
      },
    },
    thresholds: buildThresholds(profile),
  };
}

export function setupTables(tables, seats, opts) {
  const out = [];
  for (let t = 0; t < tables; t++) {
    out.push(createStartedTable(t, seats, opts));
  }
  return { tables: out, seats };
}

/**
 * Map __VU (1-based) onto a seat in setup data and play to finish.
 */
export function playAssignedSeat(data) {
  const seats = data.seats;
  const tableIndex = Math.floor((__VU - 1) / seats);
  const seatIndex = (__VU - 1) % seats;
  const table = data.tables[tableIndex];
  if (!table) {
    throw new Error(`VU ${__VU}: missing table ${tableIndex}`);
  }
  const seat = table.seats[seatIndex];
  playSeatToFinish(seat, table.game_id);
}

/**
 * Tiny prod smoke: 1×6 seats, no seed, remote thresholds.
 * Only run via ALLOW_PROD_LOAD=1 against judgment-api.fly.dev.
 */
import { makeTableOptions, setupTables, playAssignedSeat } from '../lib/scenario.js';

const TABLES = 1;
const SEATS = 6;
const PROFILE = __ENV.THRESHOLDS_PROFILE || 'prod_remote';

export const options = makeTableOptions(TABLES, SEATS, PROFILE);

export function setup() {
  return setupTables(TABLES, SEATS, { omitSeed: true });
}

export default function (data) {
  playAssignedSeat(data);
}

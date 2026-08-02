import { makeTableOptions, setupTables, playAssignedSeat } from '../lib/scenario.js';

const TABLES = Number(__ENV.TABLES || 2);
const SEATS = Number(__ENV.SEATS || 6);
const PROFILE = __ENV.THRESHOLDS_PROFILE || 'ci';

export const options = makeTableOptions(TABLES, SEATS, PROFILE);

export function setup() {
  return setupTables(TABLES, SEATS);
}

export default function (data) {
  playAssignedSeat(data);
}

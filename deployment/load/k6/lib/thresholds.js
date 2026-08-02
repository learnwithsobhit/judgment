/**
 * Shared k6 thresholds.
 *
 * Profiles:
 *   ci          — hard UX fail bands (ephemeral GitHub runners)
 *   strict      — comfort-band laptop / staging (p95 action RTT < 250ms)
 *   prod_remote — manual Fly smoke from GH (no tight RTT; gate errors/WS)
 */

export function buildThresholds(profile) {
  const p = (profile || __ENV.THRESHOLDS_PROFILE || 'ci').toLowerCase();

  if (p === 'prod_remote') {
    return {
      ws_connect_errors: ['rate<0.01'],
      command_reject_hard: ['rate<0.01'],
      command_reject_retryable: ['rate<0.05'],
      http_req_failed: ['rate<0.1'],
      // Record RTT but do not gate — GH → sin is high and noisy.
      action_rtt: ['p(95)<5000'],
    };
  }

  const thresholds = {
    action_rtt: ['p(95)<500', 'p(99)<1500'],
    ws_connect_errors: ['rate<0.01'],
    command_reject_hard: ['rate<0.001'],
    command_reject_retryable: ['rate<0.02'],
    http_req_failed: ['rate<0.05'],
  };

  if (p === 'strict') {
    thresholds.action_rtt = ['p(95)<250', 'p(99)<500'];
  }

  return thresholds;
}

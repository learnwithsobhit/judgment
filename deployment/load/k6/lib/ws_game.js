import ws from 'k6/ws';
import { check } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import { wsBase } from './api.js';

export const actionRtt = new Trend('action_rtt', true);
export const wsConnectErrors = new Rate('ws_connect_errors');
export const commandRejectHard = new Rate('command_reject_hard');
export const commandRejectRetryable = new Rate('command_reject_retryable');
export const gamesFinished = new Counter('games_finished');
export const commandsSent = new Counter('commands_sent');

export function uuidv4() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

function isRetryableReject(msg) {
  const kind = msg && msg.reason && msg.reason.kind;
  return kind === 'queue_full' || kind === 'persist_unavailable';
}

/**
 * Play one seat to game finished (or maxDurationMs).
 * Measures action_rtt for bid/play → command_accepted.
 */
export function playSeatToFinish(seat, gameId, maxDurationMs) {
  const url = `${wsBase()}/api/v1/games/${gameId}/ws?token=${encodeURIComponent(seat.token)}`;
  const limitMs = maxDurationMs || 8 * 60 * 1000;
  let connected = false;

  const res = ws.connect(url, {}, (socket) => {
    connected = true;
    let view = null;
    const playerId = seat.player_id;
    let pending = null;
    let finished = false;

    function maybeAct() {
      if (finished || !view || pending) return;
      if (view.phase === 'finished') {
        finished = true;
        gamesFinished.add(1);
        socket.close();
        return;
      }
      if (view.current_turn !== playerId) return;

      const bids = (view.legal_actions && view.legal_actions.legal_bids) || [];
      const cards = (view.legal_actions && view.legal_actions.playable_cards) || [];
      if (bids.length === 0 && cards.length === 0) return;

      const action_id = uuidv4();
      const action =
        bids.length > 0
          ? { type: 'place_bid', bid: bids[0] }
          : { type: 'play_card', card_id: cards[0] };

      const envelope = {
        protocol_version: 1,
        action_id,
        game_id: gameId,
        expected_state_version: view.state_version,
        action,
      };

      pending = { action_id, started: Date.now() };
      commandsSent.add(1);
      socket.send(JSON.stringify(envelope));
    }

    socket.on('open', () => {});

    socket.on('message', (data) => {
      let msg;
      try {
        msg = JSON.parse(data);
      } catch (_) {
        return;
      }

      switch (msg.type) {
        case 'token_rotated':
          break;
        case 'state_snapshot':
          view = msg.view;
          maybeAct();
          break;
        case 'command_accepted':
          if (pending && msg.action_id === pending.action_id) {
            actionRtt.add(Date.now() - pending.started);
            pending = null;
            commandRejectHard.add(0);
            commandRejectRetryable.add(0);
          }
          break;
        case 'command_rejected': {
          const retryable = !!msg.retryable || isRetryableReject(msg);
          if (retryable) {
            commandRejectRetryable.add(1);
            commandRejectHard.add(0);
          } else {
            const code =
              msg.reason && msg.reason.error && msg.reason.error.code;
            if (code === 'stale_state') {
              commandRejectHard.add(0);
              commandRejectRetryable.add(0);
            } else {
              commandRejectHard.add(1);
              commandRejectRetryable.add(0);
            }
          }
          if (pending && (!msg.action_id || msg.action_id === pending.action_id)) {
            pending = null;
          }
          maybeAct();
          break;
        }
        default:
          break;
      }

      if (view && view.phase === 'finished' && !finished) {
        finished = true;
        gamesFinished.add(1);
        socket.close();
      }
    });

    socket.on('error', () => {});

    // Poll during round-reveal pauses (~1.8s).
    socket.setInterval(() => {
      maybeAct();
    }, 200);

    socket.setTimeout(() => {
      socket.close();
    }, limitMs);
  });

  const ok = check(res, { 'ws status 101': (r) => r && r.status === 101 });
  wsConnectErrors.add(connected && ok ? 0 : 1);
  return ok;
}

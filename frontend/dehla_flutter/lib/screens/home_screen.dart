import 'package:flutter/material.dart';

import '../networking/api_client.dart';
import '../theme/dehla_theme.dart';
import '../util/analytics.dart';
import '../util/avatar_pack.dart';
import '../util/game_reclaim_store.dart';
import '../util/i18n.dart';
import '../util/legal_consent.dart';
import '../util/room_share.dart';
import '../widgets/app_version_bar.dart';
import '../widgets/avatar_picker.dart';
import '../widgets/legal_consent_checkbox.dart';
import 'lobby_screen.dart';
import 'table_screen.dart';

class DehlaHomeScreen extends StatefulWidget {
  const DehlaHomeScreen({
    super.key,
    this.api,
    this.initialJoinCode,
    this.invalidJoinLink = false,
  });

  final DehlaApiClient? api;
  final String? initialJoinCode;
  final bool invalidJoinLink;

  @override
  State<DehlaHomeScreen> createState() => _DehlaHomeScreenState();
}

class _DehlaHomeScreenState extends State<DehlaHomeScreen> {
  late final DehlaApiClient _api = widget.api ?? DehlaApiClient();
  final _nickCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  late bool _joining;
  bool _busy = false;
  bool _legalAccepted = false;
  String _trump = 'cut_trump';
  String _partnership = 'random_opposite';
  String _avatarId = defaultAvatarId;
  String? _error;

  bool get _fromLink => widget.initialJoinCode != null;

  @override
  void initState() {
    super.initState();
    _legalAccepted = hasAcceptedCurrentLegalAgreement();
    final code = widget.initialJoinCode;
    _joining = code != null || widget.invalidJoinLink;
    if (code != null) {
      final normalized = normalizeRoomCode(code);
      _codeCtrl.text = normalized;
      if (normalized.isEmpty) {
        _error = 'That join link was invalid';
      }
    } else if (widget.invalidJoinLink) {
      _error = 'That join link was invalid';
    }
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _joinWithReclaim(String nick) async {
    final code = normalizeRoomCode(_codeCtrl.text);
    final stored = readGameReclaim(code);
    final nickMatches = stored != null &&
        stored.nickname.trim().toLowerCase() == nick.trim().toLowerCase();

    // Prefer stored token when reclaiming own vacant seat mid-game.
    if (stored != null && nickMatches) {
      _api.token = stored.token;
      _api.sessionId = stored.sessionId;
      try {
        final peek = await _api.getRoom(code);
        if (peek.phase == 'in_game' && peek.gameId != null) {
          try {
            final claimed = await _api.claimSeat(
              code,
              playerId: stored.playerId,
            );
            _api.persistReclaim(
              roomCode: code,
              playerId: claimed.playerId,
              nickname: nick,
              gameId: claimed.gameId,
            );
            if (!mounted) return;
            trackDehlaEvent('reclaim_success');
            final isHost = claimed.room.seats.any(
              (s) => s.playerId == claimed.playerId && s.isHost,
            );
            await Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => DehlaTableScreen(
                  api: _api,
                  gameId: claimed.gameId,
                  playerId: claimed.playerId,
                  roomCode: code,
                  isHost: isHost,
                  nickname: nick,
                ),
              ),
            );
            return;
          } catch (_) {
            // Fall through to fresh join / claim without preferred id.
          }
        } else if (peek.phase == 'lobby' || peek.phase == 'partnership') {
          clearGameReclaim(code);
        }
      } catch (_) {
        clearGameReclaim(code);
      }
    }

    await _api.createGuestSession(nick, avatarId: _avatarId);
    try {
      final peek = await _api.getRoom(code);
      if (peek.phase == 'in_game') {
        final claimed = await _api.claimSeat(
          code,
          playerId: nickMatches ? stored!.playerId : null,
        );
        _api.persistReclaim(
          roomCode: code,
          playerId: claimed.playerId,
          nickname: nick,
          gameId: claimed.gameId,
        );
        if (!mounted) return;
        final isHost = claimed.room.seats.any(
          (s) => s.playerId == claimed.playerId && s.isHost,
        );
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DehlaTableScreen(
              api: _api,
              gameId: claimed.gameId,
              playerId: claimed.playerId,
              roomCode: code,
              isHost: isHost,
              nickname: nick,
            ),
          ),
        );
        return;
      }
    } catch (_) {
      // Room may still be joinable as lobby.
    }

    final result = await _api.joinRoom(code);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DehlaLobbyScreen(
          api: _api,
          room: result.room,
          playerId: result.playerId,
          isHost: result.room.seats
              .any((s) => s.playerId == result.playerId && s.isHost),
          nickname: nick,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final nick = _nickCtrl.text.trim();
    if (nick.isEmpty) {
      setState(() => _error = 'Pick a nickname first');
      return;
    }
    if (!_legalAccepted) {
      setState(() => _error = t('legal_required'));
      return;
    }
    if (_joining && _codeCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter the room code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_joining) {
        await _joinWithReclaim(nick);
      } else {
        await _api.createGuestSession(nick, avatarId: _avatarId);
        final result = await _api.createRoom(
          trumpMethod: _trump,
          partnershipMode: _partnership,
        );
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DehlaLobbyScreen(
              api: _api,
              room: result.room,
              playerId: result.playerId,
              isHost: true,
              nickname: nick,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 12),
                const Text(
                  '♠ ♥ ♦ ♣',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: goldAccent, fontSize: 22, letterSpacing: 6),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Dehla Pakad',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: goldAccent,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t('app_tagline'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.center,
                  child: SegmentedButton<DehlaLang>(
                    segments: const [
                      ButtonSegment(value: DehlaLang.en, label: Text('EN')),
                      ButtonSegment(value: DehlaLang.hi, label: Text('हिं')),
                    ],
                    selected: {dehlaLang},
                    onSelectionChanged: (s) =>
                        setState(() => dehlaLang = s.first),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_fromLink) ...[
                          Text(
                            'Joining room ${_codeCtrl.text}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: goldAccent,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ] else
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('Create')),
                              ButtonSegment(value: true, label: Text('Join')),
                            ],
                            selected: {_joining},
                            onSelectionChanged: (s) =>
                                setState(() => _joining = s.first),
                          ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _nickCtrl,
                          maxLength: 24,
                          autofocus: _fromLink,
                          decoration: const InputDecoration(
                            labelText: 'Nickname',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Your avatar',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 8),
                        AvatarPicker(
                          selectedId: _avatarId,
                          onSelected: (id) => setState(() => _avatarId = id),
                        ),
                        if (!_joining) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Trump',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                  value: 'cut_trump', label: Text('Cut')),
                              ButtonSegment(
                                  value: 'announced_trump',
                                  label: Text('Announced')),
                            ],
                            selected: {_trump},
                            onSelectionChanged: (s) =>
                                setState(() => _trump = s.first),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Cut trump is the branded default — suspense on the first offsuit.',
                            style: TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Partners',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                  value: 'random_opposite',
                                  label: Text('Random')),
                              ButtonSegment(
                                  value: 'choose_partners',
                                  label: Text('Choose')),
                            ],
                            selected: {_partnership},
                            onSelectionChanged: (s) =>
                                setState(() => _partnership = s.first),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _partnership == 'choose_partners'
                                ? 'Host picks teammates in the lobby before start.'
                                : 'Seats shuffle so partners sit opposite when the table fills.',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white54),
                          ),
                        ],
                        if (_joining && !_fromLink) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _codeCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Room code',
                              hintText: 'e.g. XK7P2Q',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) {
                              final n = normalizeRoomCode(v);
                              if (n != v.toUpperCase().replaceAll(' ', '')) {
                                _codeCtrl.value = TextEditingValue(
                                  text: n,
                                  selection: TextSelection.collapsed(offset: n.length),
                                );
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        LegalConsentCheckbox(
                          value: _legalAccepted,
                          onChanged: (v) => setState(() => _legalAccepted = v),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: (_busy || !_legalAccepted) ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(
                                    _joining ? t('join_game') : t('create_room'),
                                  ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const AppVersionBar(),
                const LegalFooterLinks(),
                const SizedBox(height: 8),
                Text(
                  'Social skill play — no real-money wagering.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

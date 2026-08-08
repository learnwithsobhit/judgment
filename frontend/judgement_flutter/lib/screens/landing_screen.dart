import 'package:flutter/material.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import '../networking/api_client.dart';
import '../state/game_controller.dart';
import '../util/app_update.dart';
import '../util/avatar_pack.dart';
import '../util/legal_consent.dart';
import '../util/table_media_session.dart';
import '../widgets/app_version_bar.dart';
import '../widgets/avatar_picker.dart';
import '../widgets/legal_consent_checkbox.dart';
import 'live_now_screen.dart';
import 'lobby_screen.dart';
import 'schedule_event_screen.dart';
import 'table_screen.dart';

class LandingScreen extends StatefulWidget {
  /// Prefill join mode from a `/r/{CODE}` deep link.
  final String? initialJoinCode;

  /// True when `/r/...` was present but the code could not be parsed.
  final bool invalidJoinLink;

  const LandingScreen({
    super.key,
    this.initialJoinCode,
    this.invalidJoinLink = false,
  });

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _nickname = TextEditingController();
  final _roomCode = TextEditingController();
  late bool _joining; // false = create, true = join
  bool _busy = false;
  bool _legalAccepted = false;
  String _selectedAvatarId = defaultAvatarId;
  bool get _fromLink => widget.initialJoinCode != null;

  @override
  void initState() {
    super.initState();
    _legalAccepted = hasAcceptedCurrentLegalAgreement();
    final code = widget.initialJoinCode;
    _joining = code != null;
    if (code != null) {
      _roomCode.text = code;
    }
    if (widget.invalidJoinLink) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That join link was invalid')),
        );
      });
    }
  }

  // Room options (create mode, ADR 0003).
  int _maxPlayers = 6;
  bool _timerEnabled = false;
  int _timerSeconds = 30;
  String? _firstTrump; // null = revealed-card trump each round
  bool _manualSchedule = false;
  /// Classic Oh Hell: dealer cannot make totals equal tricks (default off).
  bool _dealerTotalRestriction = false;
  List<ManualRoundStep> _manualSteps =
      RoundSchedule.defaultManualForPlayers(6).steps!;

  String? _scheduleValidationError() {
    if (!_manualSchedule) return null;
    if (_manualSteps.isEmpty) return 'Add at least one round step';
    final max = RoundSchedule.maxCardsPerPlayer(_maxPlayers);
    for (final step in _manualSteps) {
      if (step.cards < 1 || step.cards > max) {
        return 'Cards must be between 1 and $max for $_maxPlayers players';
      }
      if (step.repeat < 1 || step.repeat > 8) {
        return 'Repeat must be between 1 and 8';
      }
    }
    final expanded = RoundSchedule(mode: 'manual', steps: _manualSteps)
        .expandPreview();
    if (expanded.isEmpty || expanded.length > 64) {
      return 'Schedule must expand to 1–64 rounds';
    }
    return null;
  }

  void _setMaxPlayers(int n) {
    setState(() {
      _maxPlayers = n;
      _manualSteps = RoundSchedule(mode: 'manual', steps: _manualSteps)
          .clampedToPlayers(n)
          .steps!;
    });
  }

  Future<void> _submit() async {
    final nickname = _nickname.text.trim();
    if (nickname.isEmpty) {
      _showError('Pick a nickname first');
      return;
    }
    if (!_legalAccepted) {
      _showError('Please agree to the Terms of Use and Privacy Policy');
      return;
    }
    if (_joining && _roomCode.text.trim().isEmpty) {
      _showError('Enter the room code');
      return;
    }
    if (!_joining) {
      final scheduleError = _scheduleValidationError();
      if (scheduleError != null) {
        _showError(scheduleError);
        return;
      }
    }

    final fresh = await AppUpdateController.instance.ensureFreshOrReload();
    if (!fresh || !mounted) return;

    setState(() => _busy = true);
    final api = ApiClient();
    try {
      // Sound + mic under this tap, fully settled before network (fixes iOS hang).
      await TableMediaSession.prepareBeforeNetwork();

      final session = await api.createGuestSession(nickname);
      await api.setAvatar(_selectedAvatarId);
      final ({RoomView room, String playerId}) result;
      String? capacityHint;
      if (_joining) {
        final joined = await api.joinRoom(_roomCode.text.trim().toUpperCase());
        result = (room: joined.room, playerId: joined.playerId);
      } else {
        final schedule = _manualSchedule
            ? RoundSchedule(mode: 'manual', steps: _manualSteps)
            : RoundSchedule.automatic();
        final created = await api.createRoom(
          maxPlayers: _maxPlayers,
          turnTimeoutSeconds: _timerEnabled ? _timerSeconds : null,
          firstTrump: _firstTrump,
          roundSchedule: schedule,
          dealerTotalRestriction: _dealerTotalRestriction,
        );
        result = (room: created.room, playerId: created.playerId);
        capacityHint = created.capacity;
      }
      if (!mounted) return;
      if (capacityHint == 'busy') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lots of games are in progress right now. '
              'You can still make a room — starting may take a moment.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
      final gameId = result.room.gameId;
      if (result.room.phase == 'in_game' && gameId != null) {
        final controller = GameController(
          api: api,
          gameId: gameId,
          myPlayerId: result.playerId,
          myNickname: session.nickname,
        )
          ..roomCode = result.room.code
          ..amHost = result.room.seats.any(
            (s) => s.playerId == result.playerId && s.isHost,
          );
        controller.connect();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TableScreen(controller: controller),
        ));
      } else {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LobbyScreen(
            api: api,
            nickname: session.nickname,
            initialRoom: result.room,
            myPlayerId: result.playerId,
          ),
        ));
      }
    } on ApiException catch (error) {
      if (error.code == 'CAPACITY_FULL' || error.statusCode == 503) {
        _showCapacityFull(error.message);
      } else {
        _showError(error.message);
      }
    } catch (_) {
      _showError('Could not reach the server. Is it running?');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showCapacityFull(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tables are full'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _roomOptions() {
    final labelStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Colors.white.withValues(alpha: 0.75),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Players', style: labelStyle),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          segments: [
            for (var n = 3; n <= 8; n++)
              ButtonSegment(value: n, label: Text('$n')),
          ],
          selected: {_maxPlayers},
          onSelectionChanged: (selection) => _setMaxPlayers(selection.first),
        ),
        const SizedBox(height: 12),
        Text('Round schedule', style: labelStyle),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
          segments: const [
            ButtonSegment(value: false, label: Text('Automatic')),
            ButtonSegment(value: true, label: Text('Manual')),
          ],
          selected: {_manualSchedule},
          onSelectionChanged: (selection) => setState(() {
            _manualSchedule = selection.first;
            if (_manualSchedule) {
              _manualSteps =
                  RoundSchedule.defaultManualForPlayers(_maxPlayers).steps!;
            }
          }),
        ),
        const SizedBox(height: 4),
        Text(
          _manualSchedule
              ? 'Set cards per round and how many times each count repeats'
              : 'Descending from max cards for table size → 1',
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
        if (_manualSchedule) ...[
          const SizedBox(height: 8),
          _manualStepsEditor(),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('Turn timer', style: labelStyle),
          subtitle: Text(
            _timerEnabled
                ? 'Auto-plays after $_timerSeconds seconds'
                : 'No time limit — nobody is auto-played',
            style: const TextStyle(fontSize: 12),
          ),
          value: _timerEnabled,
          onChanged: (value) => setState(() => _timerEnabled = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('Dealer bid restriction', style: labelStyle),
          subtitle: Text(
            _dealerTotalRestriction
                ? 'Dealer cannot make total bids equal the tricks this round'
                : 'Off — dealer may bid so totals match the trick count',
            style: const TextStyle(fontSize: 12),
          ),
          value: _dealerTotalRestriction,
          onChanged: (value) =>
              setState(() => _dealerTotalRestriction = value),
        ),
        if (_timerEnabled)
          Wrap(
            spacing: 8,
            children: [
              for (final seconds in const [15, 30, 60, 120])
                ChoiceChip(
                  label: Text('${seconds}s'),
                  selected: _timerSeconds == seconds,
                  onSelected: (_) => setState(() => _timerSeconds = seconds),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Text('First trump', style: labelStyle),
        const SizedBox(height: 2),
        Text(
          _firstTrump == null
              ? 'A card is revealed each round; its suit is trump'
              : 'Starts at ${suitSymbols[_firstTrump]}, then rotates '
                  '\u2660 \u2666 \u2663 \u2665 each round',
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Revealed card'),
              selected: _firstTrump == null,
              onSelected: (_) => setState(() => _firstTrump = null),
            ),
            for (final suit in const ['spades', 'diamonds', 'clubs', 'hearts'])
              ChoiceChip(
                label: Text(
                  suitSymbols[suit]!,
                  style: TextStyle(
                    fontSize: 18,
                    color: _firstTrump == suit
                        ? (suit == 'hearts' || suit == 'diamonds'
                            ? const Color(0xFFFF6B6B)
                            : Colors.white)
                        : Colors.white70,
                  ),
                ),
                tooltip: suit,
                selected: _firstTrump == suit,
                onSelected: (_) => setState(() => _firstTrump = suit),
              ),
          ],
        ),
      ],
    );
  }

  Widget _manualStepsEditor() {
    final preview = RoundSchedule(mode: 'manual', steps: _manualSteps)
        .expandPreview();
    final previewText = preview.isEmpty
        ? '(empty)'
        : preview.length > 24
            ? '${preview.take(12).join(',')},…,${preview.sublist(preview.length - 4).join(',')}'
            : preview.join(',');
    final maxCards = RoundSchedule.maxCardsPerPlayer(_maxPlayers);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _manualSteps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('cards-$i-${_manualSteps[i].cards}'),
                    initialValue: _manualSteps[i].cards.clamp(1, maxCards),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Cards',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (var c = 1; c <= maxCards; c++)
                        DropdownMenuItem(value: c, child: Text('$c')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _manualSteps[i] = ManualRoundStep(
                          cards: value,
                          repeat: _manualSteps[i].repeat,
                        );
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('repeat-$i-${_manualSteps[i].repeat}'),
                    initialValue: _manualSteps[i].repeat.clamp(1, 8),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Repeat',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (var r = 1; r <= 8; r++)
                        DropdownMenuItem(value: r, child: Text('×$r')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _manualSteps[i] = ManualRoundStep(
                          cards: _manualSteps[i].cards,
                          repeat: value,
                        );
                      });
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Remove step',
                  visualDensity: VisualDensity.compact,
                  onPressed: _manualSteps.length <= 1
                      ? null
                      : () => setState(() => _manualSteps.removeAt(i)),
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => setState(() {
                _manualSteps.add(ManualRoundStep(cards: 1, repeat: 1));
              }),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add step'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _manualSteps =
                    RoundSchedule.defaultManualForPlayers(_maxPlayers).steps!;
              }),
              child: const Text('Reset default'),
            ),
          ],
        ),
        Text(
          'Preview ($previewText) — ${preview.length} rounds',
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '\u2660 \u2665 Judgement \u2666 \u2663',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: goldAccent,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bid exactly. Win exactly. Three to eight players.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 32),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        if (_fromLink) ...[
                          Text(
                            'Joining room ${_roomCode.text}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: goldAccent,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Enter a nickname to sit at the table',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                            ),
                          ),
                        ] else ...[
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                  value: false, label: Text('Create room')),
                              ButtonSegment(
                                  value: true, label: Text('Join room')),
                            ],
                            selected: {_joining},
                            onSelectionChanged: (selection) =>
                                setState(() => _joining = selection.first),
                          ),
                        ],
                        const SizedBox(height: 20),
                        TextField(
                          controller: _nickname,
                          autofocus: _fromLink,
                          maxLength: 24,
                          decoration: const InputDecoration(
                            labelText: 'Nickname',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Your avatar',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AvatarPicker(
                          selectedId: _selectedAvatarId,
                          onSelected: (id) =>
                              setState(() => _selectedAvatarId = id),
                        ),
                        if (_joining && !_fromLink) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _roomCode,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Room code',
                              hintText: 'e.g. XK7P2Q',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                        ] else if (!_joining)
                          _roomOptions(),
                        const SizedBox(height: 16),
                        LegalConsentCheckbox(
                          value: _legalAccepted,
                          onChanged: (v) => setState(() => _legalAccepted = v),
                        ),
                        const SizedBox(height: 16),
                        ListenableBuilder(
                          listenable: AppUpdateController.instance,
                          builder: (context, _) {
                            final updates = AppUpdateController.instance;
                            final blocked = _busy ||
                                !_legalAccepted ||
                                updates.awaitingInitialCheck ||
                                updates.updateAvailable;
                            return SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: FilledButton(
                                onPressed: blocked ? null : _submit,
                                child: _busy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        _joining ? 'Join game' : 'Create room',
                                      ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        const AppVersionBar(
                          autoReload: true,
                          blockWhenStale: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const LegalFooterLinks(),
                if (!_fromLink) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const LiveNowScreen(),
                      ));
                    },
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Watch live'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ScheduleEventScreen(),
                      ));
                    },
                    child: const Text('Schedule a game for later'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

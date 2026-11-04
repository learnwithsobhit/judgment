/// Ranked players. The rules stay folded so the names can fill the phone.
library;

import 'package:flutter/material.dart';

import '../auth/account_session.dart';
import '../networking/api_client.dart';
import 'player_avatar.dart';
import 'profile_sheet.dart';

typedef LeaderboardLoad = Future<LeaderboardReport> Function();
typedef FairPlayLeaderboardLoad = Future<FairPlayLeaderboardReport> Function();

LeaderboardLoad leaderboardLoad = () => ApiClient().getLeaderboard();
FairPlayLeaderboardLoad fairPlayLeaderboardLoad = () =>
    ApiClient().getFairPlayLeaderboard();

class LeaderboardSheet extends StatefulWidget {
  const LeaderboardSheet({super.key});

  @override
  State<LeaderboardSheet> createState() => _LeaderboardSheetState();
}

class _LeaderboardSheetState extends State<LeaderboardSheet> {
  late final Future<LeaderboardReport> _load = leaderboardLoad();
  late final Future<FairPlayLeaderboardReport> _fairPlayLoad =
      fairPlayLeaderboardLoad();
  late final Future<MeStats?> _place = _loadPlace();
  int _tab = 0;

  Future<MeStats?> _loadPlace() async {
    if (!AccountSession.instance.isSignedIn) return null;
    try {
      return await profileStatsLoad();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: constraints.maxHeight,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _tab == 0 ? 'Top players' : 'Fair play',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tab == 0
                        ? 'Gold 500, silver 100, bronze 20, then gold%, then bid%'
                        : 'Highest average, then matches rated',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Top players')),
                      ButtonSegment(
                        value: 1,
                        label: Text('Fair play'),
                        icon: Icon(Icons.handshake_outlined, size: 16),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (next) {
                      setState(() => _tab = next.first);
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _tab == 0
                        ? _TopPlayersTab(load: _load, place: _place)
                        : _FairPlayTab(load: _fairPlayLoad),
                  ),
                  if (_tab == 0) const _BoardKey() else const _FairPlayKey(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopPlayersTab extends StatelessWidget {
  const _TopPlayersTab({required this.load, required this.place});

  final Future<LeaderboardReport> load;
  final Future<MeStats?> place;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LeaderboardReport>(
      future: load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Couldn\'t load the board. You can still play.'),
            ),
          );
        }
        final report = snapshot.data ?? const LeaderboardReport(players: []);
        final rows = report.players;
        return Column(
          children: [
            _PulseBlock(pulse: report.pulse, place: place),
            if (rows.isEmpty)
              const Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No ranked games yet.'),
                  ),
                ),
              )
            else
              Expanded(child: _BoardTable(rows: rows)),
          ],
        );
      },
    );
  }
}

class _FairPlayTab extends StatelessWidget {
  const _FairPlayTab({required this.load});

  final Future<FairPlayLeaderboardReport> load;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FairPlayLeaderboardReport>(
      future: load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Couldn\'t load fair play. You can still play.'),
            ),
          );
        }
        final rows = snapshot.data?.players ?? const [];
        if (rows.isEmpty) {
          return const Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No fair play ratings yet.'),
            ),
          );
        }
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final row = rows[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  PlayerAvatar(
                    avatarId: row.avatarId,
                    nickname: row.displayName,
                    radius: 18,
                    signedIn: true,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${row.rank}. ${row.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    row.average.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    row.gamesRated == 1
                        ? '1 match'
                        : '${row.gamesRated} matches',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _FairPlayKey extends StatefulWidget {
  const _FairPlayKey();

  @override
  State<_FairPlayKey> createState() => _FairPlayKeyState();
}

class _FairPlayKeyState extends State<_FairPlayKey> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      height: 1.35,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_open)
          Text(
            'After each game, signed-in players rate each other from 0 to 10. '
            'Who gave what stays private. Only totals appear here.',
            style: style,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => setState(() => _open = !_open),
            child: Text(_open ? 'Hide the rules' : 'How fair play works'),
          ),
        ),
      ],
    );
  }
}

class _PulseBlock extends StatelessWidget {
  const _PulseBlock({required this.pulse, required this.place});

  final LeaderboardPulse? pulse;
  final Future<MeStats?> place;

  @override
  Widget build(BuildContext context) {
    final figures =
        pulse ??
        const LeaderboardPulse(
          gamesToday: 0,
          gamesWeek: 0,
          gamesAll: 0,
          playersWeek: 0,
        );
    final quiet = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      height: 1.35,
    );
    final leader = figures.weekLeaderName;
    final points = figures.weekLeaderPoints;
    final lastLeader = figures.lastWeekLeaderName;
    final lastPoints = figures.lastWeekLeaderPoints;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PulseFigure(label: 'Today', value: figures.gamesToday),
            _PulseFigure(label: 'Week', value: figures.gamesWeek),
            _PulseFigure(label: 'Last week', value: figures.gamesLastWeek),
            _PulseFigure(label: 'All', value: figures.gamesAll),
          ],
        ),
        const SizedBox(height: 6),
        Text(_pulseCaption(figures), style: quiet),
        if (leader != null && points > 0) ...[
          const SizedBox(height: 2),
          Text(
            '$leader leads this week with $points ${points == 1 ? 'point' : 'points'}.',
            style: quiet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (lastLeader != null && lastPoints > 0) ...[
          const SizedBox(height: 2),
          Text(
            '$lastLeader led last week with $lastPoints ${lastPoints == 1 ? 'point' : 'points'}.',
            style: quiet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (figures.openTables > 0) ...[
          const SizedBox(height: 2),
          Text('A table is filling up.', style: quiet),
        ],
        FutureBuilder<MeStats?>(
          future: place,
          builder: (context, snapshot) {
            final stats = snapshot.data;
            if (stats == null) return const SizedBox.shrink();
            final rank = stats.rank;
            final line = rank == null
                ? 'Finish a game with 3 or more players and your name can appear here.'
                : 'You are ${_ordinal(rank)}.';
            return Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(line, style: quiet),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PulseFigure extends StatelessWidget {
  const _PulseFigure({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$value',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

String _pulseCaption(LeaderboardPulse pulse) {
  if (pulse.since == null) {
    return 'Counting starts when the next ranked game finishes.';
  }
  final since =
      'Ranked games since ${_formatIstDate(pulse.since!)}. Today and this week use India time.';
  if (pulse.gamesWeek <= 0) return since;
  final games = pulse.gamesWeek == 1 ? '1 game' : '${pulse.gamesWeek} games';
  final players = pulse.playersWeek == 1
      ? '1 player'
      : '${pulse.playersWeek} players';
  return '$since $games this week, from $players.';
}

String _formatIstDate(DateTime instant) {
  final ist = instant.toUtc().add(const Duration(hours: 5, minutes: 30));
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${ist.day} ${months[ist.month - 1]} ${ist.year}';
}

String _pointsLabel(int points) {
  final digits = '$points';
  if (digits.length <= 3) return digits;
  final chars = <String>[];
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) chars.add(',');
    chars.add(digits[i]);
  }
  return chars.join();
}

String _ordinal(int rank) {
  final mod100 = rank % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${rank}th';
  return switch (rank % 10) {
    1 => '${rank}st',
    2 => '${rank}nd',
    3 => '${rank}rd',
    _ => '${rank}th',
  };
}

/// Phone sheets stack the name above the figures so Pts and medals can breathe.
class _BoardMetrics {
  const _BoardMetrics({required this.compact});

  final bool compact;

  static const compactBelow = 620.0;

  double get played => compact ? 40 : 56;
  double get pts => compact ? 58 : 72;
  double get medal => compact ? 30 : 40;
  double get rate => compact ? 48 : 58;
  double get groupGap => compact ? 10 : 20;
  double get rateGap => compact ? 6 : 8;
  double get medalInner => compact ? 6 : 8;
  double get clusterPad => compact ? 6 : 10;

  double get clusterWidth => clusterPad * 2 + medal * 3 + medalInner * 2;
}

class _BoardTable extends StatelessWidget {
  final List<LeaderboardEntry> rows;

  const _BoardTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _BoardMetrics(
          compact: constraints.maxWidth < _BoardMetrics.compactBelow,
        );
        final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.62),
        );
        final ptsHeader = headerStyle?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFFFFC857),
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: metrics.compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Name', style: headerStyle),
                        const SizedBox(height: 8),
                        _StatsRow.header(
                          metrics: metrics,
                          style: headerStyle,
                          ptsStyle: ptsHeader,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        const SizedBox(width: 44),
                        Expanded(child: Text('Name', style: headerStyle)),
                        _StatsRow.header(
                          metrics: metrics,
                          style: headerStyle,
                          ptsStyle: ptsHeader,
                        ),
                      ],
                    ),
            ),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                itemBuilder: (context, index) =>
                    _BoardRow(row: rows[index], metrics: metrics),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({required this.row, required this.metrics});

  final LeaderboardEntry row;
  final _BoardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onSurface;
    final number = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontSize: metrics.compact ? 13 : 14,
      height: 1.1,
      color: on.withValues(alpha: 0.88),
    );
    final muted = number?.copyWith(
      color: on.withValues(alpha: 0.68),
      fontSize: 12.5,
    );
    final ptsStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w800,
      letterSpacing: 0.1,
      height: 1.1,
      color: const Color(0xFFFFC857),
    );
    final stats = _StatsRow.data(
      metrics: metrics,
      played: '${row.games}',
      pts: _pointsLabel(row.medalPoints),
      gold: '${row.gold}',
      silver: '${row.silver}',
      bronze: '${row.bronze}',
      goldRate: row.goldRateLabel,
      bidRate: row.bidRateLabel,
      number: number,
      muted: muted,
      ptsStyle: ptsStyle,
    );
    final name = Row(
      children: [
        PlayerAvatar(
          avatarId: row.avatarId,
          nickname: row.displayName,
          radius: 16,
          boardRank: row.rank,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${row.rank}. ${row.displayName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(color: _rowFill(row.rank)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          0,
          metrics.compact ? 8 : 10,
          0,
          metrics.compact ? 8 : 10,
        ),
        child: metrics.compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [name, const SizedBox(height: 8), stats],
              )
            : Row(
                children: [
                  Expanded(child: name),
                  stats,
                ],
              ),
      ),
    );
  }

  Color _rowFill(int rank) {
    return switch (rank) {
      1 => const Color(0xFFF6C431).withValues(alpha: 0.07),
      2 => const Color(0xFFF3F4F6).withValues(alpha: 0.05),
      3 => const Color(0xFFE39A55).withValues(alpha: 0.06),
      _ => Colors.transparent,
    };
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow.header({
    required this.metrics,
    required this.style,
    required this.ptsStyle,
  }) : played = 'Played',
       pts = 'Pts',
       gold = '',
       silver = '',
       bronze = '',
       goldRate = '',
       bidRate = 'Bid',
       number = null,
       muted = null,
       header = true;

  const _StatsRow.data({
    required this.metrics,
    required this.played,
    required this.pts,
    required this.gold,
    required this.silver,
    required this.bronze,
    required this.goldRate,
    required this.bidRate,
    required this.number,
    required this.muted,
    required this.ptsStyle,
  }) : style = null,
       header = false;

  final _BoardMetrics metrics;
  final String played;
  final String pts;
  final String gold;
  final String silver;
  final String bronze;
  final String goldRate;
  final String bidRate;
  final TextStyle? style;
  final TextStyle? number;
  final TextStyle? muted;
  final TextStyle? ptsStyle;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _cell(played, metrics.played, header ? style : number),
        SizedBox(width: metrics.groupGap),
        _cell(pts, metrics.pts, ptsStyle, emphasize: true),
        SizedBox(width: metrics.groupGap),
        _medalCluster(context),
        SizedBox(width: metrics.groupGap),
        header ? _goldPercentHeader() : _cell(goldRate, metrics.rate, muted),
        SizedBox(width: metrics.rateGap),
        _cell(bidRate, metrics.rate, header ? style : muted),
      ],
    );
  }

  Widget _medalCluster(BuildContext context) {
    final children = header
        ? const [
            _PodiumMedal(place: 1, size: 15),
            _PodiumMedal(place: 2, size: 15),
            _PodiumMedal(place: 3, size: 15),
          ]
        : [
            _cell(gold, metrics.medal, number),
            _cell(silver, metrics.medal, number),
            _cell(bronze, metrics.medal, number),
          ];
    return Container(
      width: metrics.clusterWidth,
      padding: EdgeInsets.symmetric(
        horizontal: metrics.clusterPad,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: metrics.medalInner),
            if (header)
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: children[i],
                ),
              )
            else
              children[i],
          ],
        ],
      ),
    );
  }

  Widget _goldPercentHeader() {
    return SizedBox(
      width: metrics.rate,
      child: Tooltip(
        message: 'Gold percent',
        child: Semantics(
          label: 'Gold percent',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const _PodiumMedal(place: 1, size: 12, labelled: false),
              Flexible(
                child: Text(
                  '%',
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(
    String value,
    double width,
    TextStyle? cellStyle, {
    bool emphasize = false,
  }) {
    return SizedBox(
      width: width,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          value,
          style: cellStyle,
          textAlign: TextAlign.end,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          semanticsLabel: emphasize && !header ? '$value points' : null,
        ),
      ),
    );
  }
}

class _BoardKey extends StatefulWidget {
  const _BoardKey();

  @override
  State<_BoardKey> createState() => _BoardKeyState();
}

class _BoardKeyState extends State<_BoardKey> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      height: 1.35,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_open)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(
              child: Text(
                'Caps — gold is 1st, silver is 2nd, and bronze is 3rd on this board. '
                'The same cap shows on that player\'s seat.\n'
                'A ranked game is a finished table of at least 3 players with someone signed in. Guests do not count.\n'
                'Played — ranked games.\n'
                'Gold, silver, and bronze medals — first, second, and third-place finishes. A shared place counts for each player.\n'
                'Pts — gold 500, silver 100, bronze 20.\n'
                'Gold% — golds divided by played, to one decimal. 2 golds from 13 games is 15.3%.\n'
                'Bid — rounds where the bid matched the tricks taken, to one decimal.\n'
                'Order — most points, then more gold, silver, and bronze. '
                'When those match, higher gold%, then higher Bid.',
                style: style,
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => setState(() => _open = !_open),
            child: Text(_open ? 'Hide the rules' : 'How the board works'),
          ),
        ),
      ],
    );
  }
}

/// Compact gold, silver, or bronze medal for board column headers.
class _PodiumMedal extends StatelessWidget {
  const _PodiumMedal({
    required this.place,
    this.size = 15,
    this.labelled = true,
  });

  final int place;
  final double size;
  final bool labelled;

  @override
  Widget build(BuildContext context) {
    final (fill, edge, shine, label) = switch (place) {
      1 => (
        const Color(0xFFF6C431),
        const Color(0xFFC88810),
        const Color(0xFFFFF1A8),
        'Gold',
      ),
      2 => (
        const Color(0xFFF3F4F6),
        const Color(0xFF8A9096),
        const Color(0xFFFFFFFF),
        'Silver',
      ),
      _ => (
        const Color(0xFFE39A55),
        const Color(0xFFA85A28),
        const Color(0xFFF8C99A),
        'Bronze',
      ),
    };
    final mark = SizedBox(
      width: size,
      height: size + 2,
      child: CustomPaint(
        painter: _MedalPainter(fill: fill, edge: edge, shine: shine),
      ),
    );
    if (!labelled) return mark;
    return Tooltip(
      message: label,
      child: Semantics(label: label, child: mark),
    );
  }
}

class _MedalPainter extends CustomPainter {
  const _MedalPainter({
    required this.fill,
    required this.edge,
    required this.shine,
  });

  final Color fill;
  final Color edge;
  final Color shine;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = (w * 0.08).clamp(1.0, 1.6);

    final ribbon = Path()
      ..moveTo(w * 0.22, 0)
      ..lineTo(w * 0.50, h * 0.38)
      ..lineTo(w * 0.78, 0)
      ..lineTo(w * 0.62, 0)
      ..lineTo(w * 0.50, h * 0.22)
      ..lineTo(w * 0.38, 0)
      ..close();
    canvas.drawPath(ribbon, Paint()..color = edge);
    canvas.drawPath(
      ribbon,
      Paint()
        ..color = const Color(0xFF1A120C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.7
        ..strokeJoin = StrokeJoin.round,
    );

    final center = Offset(w * 0.50, h * 0.64);
    final radius = w * 0.36;
    canvas.drawCircle(center, radius, Paint()..color = fill);
    canvas.drawCircle(
      center.translate(-radius * 0.28, -radius * 0.28),
      radius * 0.28,
      Paint()..color = shine.withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF1A120C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _MedalPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.edge != edge ||
      oldDelegate.shine != shine;
}

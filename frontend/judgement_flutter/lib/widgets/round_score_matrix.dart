/// Horizontally scrollable round×player score matrix with a sticky round column.
library;

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import 'player_avatar.dart';

/// One player column in [RoundScoreMatrix].
class RoundScoreColumn {
  final String playerId;
  final String displayName;
  final String? avatarId;
  final bool highlightHeader;
  final int? total;

  const RoundScoreColumn({
    required this.playerId,
    required this.displayName,
    this.avatarId,
    this.highlightHeader = false,
    this.total,
  });
}

/// Compact player columns + sticky `Rnd` labels + visible horizontal scrollbar.
class RoundScoreMatrix extends StatefulWidget {
  final List<RoundScoreColumn> columns;
  final List<RoundScoreView> history;
  final bool showTotals;
  final String? emphasizePlayerId;
  final String Function(RoundScoreView round, String playerId)? cellTooltip;
  final String? footerHint;
  final String roundHeaderLabel;
  final String totalsLabel;

  const RoundScoreMatrix({
    super.key,
    required this.columns,
    required this.history,
    this.showTotals = true,
    this.emphasizePlayerId,
    this.cellTooltip,
    this.footerHint,
    this.roundHeaderLabel = 'Rnd',
    this.totalsLabel = 'Tot',
  });

  static const double stickyWidth = 52;
  static const double columnWidth = 60;
  static const double headerHeight = 52;
  static const double rowHeight = 32;
  static const double totalsHeight = 36;

  @override
  State<RoundScoreMatrix> createState() => _RoundScoreMatrixState();
}

class _RoundScoreMatrixState extends State<RoundScoreMatrix> {
  final ScrollController _scroll = ScrollController();
  bool _canScrollMore = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateFade);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFade());
  }

  @override
  void didUpdateWidget(covariant RoundScoreMatrix oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFade());
  }

  @override
  void dispose() {
    _scroll.removeListener(_updateFade);
    _scroll.dispose();
    super.dispose();
  }

  void _updateFade() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final more = pos.maxScrollExtent > 0.5 &&
        pos.pixels < pos.maxScrollExtent - 0.5;
    if (more != _canScrollMore && mounted) {
      setState(() => _canScrollMore = more);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final bodyW = (available - RoundScoreMatrix.stickyWidth)
            .clamp(120.0, double.infinity);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: RoundScoreMatrix.stickyWidth,
                  child: _StickyRoundColumn(
                    history: widget.history,
                    showTotals: widget.showTotals,
                    roundHeaderLabel: widget.roundHeaderLabel,
                    totalsLabel: widget.totalsLabel,
                  ),
                ),
                SizedBox(
                  width: bodyW,
                  child: Stack(
                    children: [
                      Scrollbar(
                        controller: _scroll,
                        thumbVisibility: true,
                        interactive: true,
                        scrollbarOrientation: ScrollbarOrientation.bottom,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          child: _PlayerScoreBody(
                            columns: widget.columns,
                            history: widget.history,
                            showTotals: widget.showTotals,
                            emphasizePlayerId: widget.emphasizePlayerId,
                            cellTooltip: widget.cellTooltip,
                          ),
                        ),
                      ),
                      if (_canScrollMore)
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          width: 28,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.45),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.footerHint != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.footerHint!,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StickyRoundColumn extends StatelessWidget {
  final List<RoundScoreView> history;
  final bool showTotals;
  final String roundHeaderLabel;
  final String totalsLabel;

  const _StickyRoundColumn({
    required this.history,
    required this.showTotals,
    required this.roundHeaderLabel,
    required this.totalsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: RoundScoreMatrix.headerHeight,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                roundHeaderLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        for (final r in history)
          SizedBox(
            height: RoundScoreMatrix.rowHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'R${r.roundIndex + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (showTotals)
          SizedBox(
            height: RoundScoreMatrix.totalsHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                totalsLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: goldAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlayerScoreBody extends StatelessWidget {
  final List<RoundScoreColumn> columns;
  final List<RoundScoreView> history;
  final bool showTotals;
  final String? emphasizePlayerId;
  final String Function(RoundScoreView round, String playerId)? cellTooltip;

  const _PlayerScoreBody({
    required this.columns,
    required this.history,
    required this.showTotals,
    required this.emphasizePlayerId,
    required this.cellTooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: RoundScoreMatrix.headerHeight,
          child: Row(
            children: [
              for (final col in columns) _HeaderCell(column: col),
            ],
          ),
        ),
        for (final r in history)
          SizedBox(
            height: RoundScoreMatrix.rowHeight,
            child: Row(
              children: [
                for (final col in columns)
                  _ScoreCell(
                    label: _scoreFor(r, col.playerId),
                    emphasize: emphasizePlayerId == col.playerId,
                    tooltip: cellTooltip?.call(r, col.playerId),
                  ),
              ],
            ),
          ),
        if (showTotals)
          SizedBox(
            height: RoundScoreMatrix.totalsHeight,
            child: Row(
              children: [
                for (final col in columns)
                  SizedBox(
                    width: RoundScoreMatrix.columnWidth,
                    child: Text(
                      '${col.total ?? 0}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: goldAccent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _scoreFor(RoundScoreView round, String playerId) {
    for (final e in round.entries) {
      if (e.playerId == playerId) return '${e.score}';
    }
    return '—';
  }
}

class _HeaderCell extends StatelessWidget {
  final RoundScoreColumn column;

  const _HeaderCell({required this.column});

  @override
  Widget build(BuildContext context) {
    final short = _shortName(column.displayName);
    return Tooltip(
      message: column.displayName,
      child: SizedBox(
        width: RoundScoreMatrix.columnWidth,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            PlayerAvatar(
              avatarId: column.avatarId,
              nickname: column.displayName,
              radius: 10,
              highlight: column.highlightHeader,
            ),
            const SizedBox(height: 2),
            Text(
              short,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: column.highlightHeader ? goldAccent : Colors.white54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortName(String name) {
    final cleaned = name.replaceAll(RegExp(r'\s*\(you\)\s*'), '').trim();
    if (cleaned.length <= 8) return cleaned;
    return '${cleaned.substring(0, 7)}…';
  }
}

class _ScoreCell extends StatelessWidget {
  final String label;
  final bool emphasize;
  final String? tooltip;

  const _ScoreCell({
    required this.label,
    required this.emphasize,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: emphasize ? goldAccent : null,
      ),
    );
    return SizedBox(
      width: RoundScoreMatrix.columnWidth,
      child: tooltip == null || tooltip!.isEmpty
          ? text
          : Tooltip(message: tooltip!, child: text),
    );
  }
}

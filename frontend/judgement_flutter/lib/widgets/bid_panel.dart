import 'package:flutter/material.dart';

import '../app/app.dart';

/// Bidding controls for the current player.
///
/// Tapping a legal number only selects it. The bid is sent when the player
/// taps Confirm, so a mis-tap can be changed before it is placed.
class BidPanel extends StatefulWidget {
  final int cards;
  final Set<int> legalBids;
  final bool dealerRestricted;
  final bool pending;
  final ValueChanged<int> onConfirm;

  const BidPanel({
    super.key,
    required this.cards,
    required this.legalBids,
    required this.dealerRestricted,
    required this.pending,
    required this.onConfirm,
  });

  @override
  State<BidPanel> createState() => _BidPanelState();
}

class _BidPanelState extends State<BidPanel> {
  int? _selectedBid;

  @override
  void didUpdateWidget(BidPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selectedBid;
    if (selected != null && !_stillLegal(selected)) {
      _selectedBid = null;
    }
  }

  bool _stillLegal(int bid) =>
      bid >= 0 && bid <= widget.cards && widget.legalBids.contains(bid);

  void _select(int bid) {
    if (widget.pending || !_stillLegal(bid)) return;
    setState(() => _selectedBid = bid);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedBid;
    final cards = widget.cards;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final gap = compact ? 4.0 : 8.0;
          return Column(
            children: [
              Text(
                widget.dealerRestricted
                    ? 'Your bid — as dealer, the total cannot equal $cards'
                    : 'Your bid — how many tricks will you win?',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                alignment: WrapAlignment.center,
                children: [
                  for (var bid = 0; bid <= cards; bid++)
                    _BidNumberButton(
                      bid: bid,
                      legal: widget.legalBids.contains(bid),
                      selected: selected == bid,
                      pending: widget.pending,
                      cards: cards,
                      compact: compact,
                      onSelect: () => _select(bid),
                    ),
                ],
              ),
              if (selected != null) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  label: 'Bid $selected tricks?',
                  child: Text(
                    'Bid $selected tricks?',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  button: true,
                  enabled: !widget.pending,
                  label: 'Confirm bid $selected tricks',
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: goldAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(48, 44),
                    ),
                    onPressed: widget.pending
                        ? null
                        : () => widget.onConfirm(selected),
                    child: const Text('Confirm bid'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BidNumberButton extends StatelessWidget {
  final int bid;
  final bool legal;
  final bool selected;
  final bool pending;
  final int cards;
  final bool compact;
  final VoidCallback onSelect;

  const _BidNumberButton({
    required this.bid,
    required this.legal,
    required this.selected,
    required this.pending,
    required this.cards,
    required this.compact,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = legal && !pending;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: !legal
          ? 'Bid $bid not allowed'
          : selected
          ? 'Selected bid $bid'
          : 'Select bid $bid',
      child: Tooltip(
        message: legal
            ? 'Bid $bid'
            : 'Not allowed: the dealer cannot make total bids equal $cards',
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: !legal
                ? Colors.white12
                : selected
                ? Colors.white
                : goldAccent,
            foregroundColor: legal ? Colors.black : Colors.white38,
            side: selected
                ? const BorderSide(color: goldAccent, width: 3)
                : null,
            minimumSize: compact ? const Size(40, 40) : const Size(48, 44),
            padding: compact ? EdgeInsets.zero : null,
            tapTargetSize: compact
                ? MaterialTapTargetSize.shrinkWrap
                : MaterialTapTargetSize.padded,
            visualDensity: compact
                ? VisualDensity.compact
                : VisualDensity.standard,
          ),
          onPressed: enabled ? onSelect : null,
          child: Text('$bid'),
        ),
      ),
    );
  }
}

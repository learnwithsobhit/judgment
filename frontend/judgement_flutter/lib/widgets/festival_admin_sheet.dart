import 'package:flutter/material.dart';

import '../networking/api_client.dart';
import '../theme/festival_catalog.dart';
import '../theme/festival_controller.dart';
import '../theme/judgement_palette.dart';

class FestivalAdminSheet extends StatefulWidget {
  const FestivalAdminSheet({super.key});

  @override
  State<FestivalAdminSheet> createState() => _FestivalAdminSheetState();
}

class _FestivalAdminSheetState extends State<FestivalAdminSheet> {
  late String _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selected = FestivalController.instance.festivalId;
  }

  Future<void> _confirm() async {
    final previous = FestivalController.instance.festivalId;
    final next = FestivalTheme.byId(_selected);
    if (next.id == previous) {
      Navigator.of(context).pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Show ${next.label} to everyone?'),
        content: const Text(
          'Every table will use this look. Turn it off from the top of the table or from Table look.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Show it'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await FestivalController.instance.pushFestival(next.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      final unauthorized =
          error is ApiException &&
          (error.statusCode == 401 || error.code == 'UNAUTHORIZED');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unauthorized
                ? 'Sign in again to change the table look'
                : 'Could not change the table look',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = FestivalTheme.byId(_selected).palette;
    final media = MediaQuery.of(context);
    final bottomPad = media.padding.bottom > 0
        ? media.padding.bottom + 16
        : 48.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.72),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Table look', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _FeltPreview(palette: preview),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final theme in FestivalTheme.all)
                    ChoiceChip(
                      label: Text(theme.label),
                      selected: _selected == theme.id,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _selected = theme.id),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _confirm,
                child: Text(_busy ? 'Saving…' : 'Use this look'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeltPreview extends StatelessWidget {
  const _FeltPreview({required this.palette});

  final JudgementPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [palette.feltHighlight, palette.felt, palette.feltDark],
          stops: const [0.0, 0.65, 1.0],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.wood, width: 3),
      ),
      alignment: Alignment.center,
      child: Text(
        'Judgement',
        style: TextStyle(
          color: palette.title,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

import 'judgement_palette.dart';

/// Keep in sync with `judgement_protocol::FESTIVAL_IDS`.
enum FestivalMotif { none, lamp, snow, powder, spark, crescent }

class FestivalTheme {
  const FestivalTheme({
    required this.id,
    required this.label,
    required this.caption,
    required this.greeting,
    required this.wish,
    required this.palette,
    required this.motif,
  });

  final String id;
  final String label;
  final String caption;
  final String greeting;
  final String wish;
  final JudgementPalette palette;
  final FestivalMotif motif;

  static const off = FestivalTheme(
    id: 'off',
    label: 'Classic',
    caption: '',
    greeting: '',
    wish: '',
    palette: JudgementPalette.off,
    motif: FestivalMotif.none,
  );

  static const diwali = FestivalTheme(
    id: 'diwali',
    label: 'Diwali',
    caption: 'Diwali at the table.',
    greeting: 'Happy Diwali',
    wish: 'Wishing you and your family light, luck, and exact bids.',
    palette: JudgementPalette.diwali,
    motif: FestivalMotif.lamp,
  );

  static const christmas = FestivalTheme(
    id: 'christmas',
    label: 'Christmas',
    caption: 'Christmas at the table.',
    greeting: 'Merry Christmas',
    wish: 'Warm seats and a kind table for you and yours.',
    palette: JudgementPalette.christmas,
    motif: FestivalMotif.snow,
  );

  static const holi = FestivalTheme(
    id: 'holi',
    label: 'Holi',
    caption: 'Holi at the table.',
    greeting: 'Happy Holi',
    wish: 'Colour, company, and a fair hand.',
    palette: JudgementPalette.holi,
    motif: FestivalMotif.powder,
  );

  static const halloween = FestivalTheme(
    id: 'halloween',
    label: 'Halloween',
    caption: 'Halloween at the table.',
    greeting: 'Happy Halloween',
    wish: 'Tricks at the table, treats for the bid.',
    palette: JudgementPalette.halloween,
    motif: FestivalMotif.spark,
  );

  static const newYear = FestivalTheme(
    id: 'new_year',
    label: 'New Year',
    caption: 'New Year at the table.',
    greeting: 'Happy New Year',
    wish: 'New round, same exact tricks.',
    palette: JudgementPalette.newYear,
    motif: FestivalMotif.spark,
  );

  static const eid = FestivalTheme(
    id: 'eid',
    label: 'Eid',
    caption: 'Eid at the table.',
    greeting: 'Eid Mubarak',
    wish: 'Peace at home and a fair table.',
    palette: JudgementPalette.eid,
    motif: FestivalMotif.crescent,
  );

  static const List<FestivalTheme> all = [
    off,
    diwali,
    christmas,
    holi,
    halloween,
    newYear,
    eid,
  ];

  static FestivalTheme byId(String? id) {
    if (id == null || id.isEmpty) return off;
    for (final theme in all) {
      if (theme.id == id) return theme;
    }
    return off;
  }
}

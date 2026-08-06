import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:judgement_flutter/util/game_reclaim_store.dart';

import '../models/game_catalog.dart';
import '../profile/shell_profile.dart';
import '../profile/shell_profile_store.dart';
import '../state/pending_invite.dart';
import '../theme/table_games_theme.dart';
import '../ux/copy.dart';
import '../widgets/brand_hero.dart';
import '../widgets/continue_rail.dart';
import '../widgets/game_stage_card.dart';
import '../widgets/profile_chip.dart';

class HomeScreen extends StatefulWidget {
  final List<GameEntry>? catalog;

  const HomeScreen({super.key, this.catalog});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _tablesKey = GlobalKey();
  ShellProfile? _profile;
  GameReclaimBlob? _reclaim;
  String? _inviteCode;

  @override
  void initState() {
    super.initState();
    _profile = readShellProfile();
    _reclaim = peekGameReclaim();
    _inviteCode = pendingJoinCode;
  }

  void _scrollToTables() {
    final ctx = _tablesKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _saveProfile(ShellProfile profile) {
    writeShellProfile(profile);
    setState(() => _profile = profile);
  }

  Future<void> _playJudgement({String? joinCode}) async {
    if (joinCode != null && joinCode.isNotEmpty) {
      context.push('/j/r/$joinCode');
    } else {
      context.push('/j');
    }
  }

  void _onNotify(GameEntry game) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          TableGamesCopy.notifySoon.replaceFirst('this table', game.name),
          style: GoogleFonts.sourceSans3(),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: feltGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final games = widget.catalog ?? defaultGameCatalog();
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100
        ? 4
        : width >= 720
            ? 2
            : 1;
    final reclaim = _reclaim;
    final invite = _inviteCode;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF123A18),
              feltGreenDark,
              Color(0xFF07140A),
            ],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    width < 720 ? 16 : 40,
                    8,
                    width < 720 ? 16 : 40,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ProfileChip(
                      profile: _profile,
                      onChanged: _saveProfile,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: BrandHero(onBrowseTables: _scrollToTables),
              ),
              if (invite != null && invite.isNotEmpty)
                SliverToBoxAdapter(
                  child: ContinueRail(
                    title: 'Join Judgement room',
                    subtitle: 'Invite · $invite',
                    onResume: () => _playJudgement(joinCode: invite),
                  ),
                )
              else if (reclaim != null)
                SliverToBoxAdapter(
                  child: ContinueRail(
                    roomCode: reclaim.roomCode,
                    onResume: () =>
                        _playJudgement(joinCode: reclaim.roomCode),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  key: _tablesKey,
                  padding: EdgeInsets.fromLTRB(
                    width < 720 ? 20 : 48,
                    20,
                    width < 720 ? 20 : 48,
                    8,
                  ),
                  child: Text(
                    TableGamesCopy.yourTables,
                    style: GoogleFonts.playfairDisplay(
                      color: suitLight,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  width < 720 ? 20 : 48,
                  8,
                  width < 720 ? 20 : 48,
                  24,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: columns == 1 ? 1.45 : 0.95,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final game = games[index];
                      final isJudgement = game.id == 'judgement';
                      final joinInvite =
                          isJudgement && invite != null && invite.isNotEmpty;
                      return GameStageCard(
                        game: game,
                        playLabel: joinInvite ? 'Join room' : null,
                        onPlay: isJudgement
                            ? () => _playJudgement(
                                  joinCode: joinInvite ? invite : null,
                                )
                            : null,
                        onNotify: () => _onNotify(game),
                      );
                    },
                    childCount: games.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  child: Column(
                    children: [
                      Text(
                        'Host a night · Share one link · No real-money play',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.sourceSans3(
                          color: suitLight.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        TableGamesCopy.trustLine,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.sourceSans3(
                          color: goldAccent.withValues(alpha: 0.75),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

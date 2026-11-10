/// Admin-selected festival. Never rebuilds [MaterialApp] or the game socket.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/account_session.dart';
import '../networking/api_client.dart';
import 'festival_catalog.dart';
import 'judgement_palette.dart';

const festivalIdPrefsKey = 'judgement.festive.id';
const festivalCalmPrefsKey = 'judgement.festive.calm';
const festivalCaptionPrefsPrefix = 'judgement.festive.caption.';

typedef FestivalConfigLoad = Future<String> Function();
typedef FestivalSet = Future<String> Function(String id);

FestivalConfigLoad festivalConfigLoad = () => ApiClient().getConfig();
FestivalSet festivalSet = (id) => adminFestivalClient().setFestival(id);

/// PATCH /admin/festival must use the signed-in bearer. A bare [ApiClient]
/// has no token and the server returns 401.
ApiClient adminFestivalClient() =>
    ApiClient()..token = AccountSession.instance.token;

class FestivalController extends ChangeNotifier {
  FestivalController._();

  static final FestivalController instance = FestivalController._();

  String _appliedId = FestivalTheme.off.id;
  String? _pendingId;
  bool playLocked = false;
  bool celebrationLocked = false;
  bool calm = false;
  final Set<String> _dismissedCaptions = {};
  bool _refreshing = false;
  bool pushing = false;
  int _failures = 0;
  bool greetingPlayed = false;

  String get festivalId => _appliedId;

  FestivalTheme get theme => FestivalTheme.byId(_appliedId);

  JudgementPalette get palette => theme.palette;

  bool get overlayAllowed =>
      theme.motif != FestivalMotif.none &&
      !calm &&
      !playLocked &&
      !celebrationLocked;

  bool get showGreeting {
    if (theme.greeting.isEmpty) return false;
    return !_dismissedCaptions.contains(_appliedId);
  }

  bool get showLandingCaption => showGreeting;

  void markGreetingPlayed() {
    greetingPlayed = true;
  }

  Future<void> restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      calm = prefs.getBool(festivalCalmPrefsKey) ?? false;
      final cached = prefs.getString(festivalIdPrefsKey);
      if (cached != null && cached.isNotEmpty) {
        _appliedId = FestivalTheme.byId(cached).id;
      }
      for (final theme in FestivalTheme.all) {
        if (prefs.getBool('$festivalCaptionPrefsPrefix${theme.id}') == true) {
          _dismissedCaptions.add(theme.id);
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refresh() async {
    if (playLocked) return;
    if (_refreshing) return;
    _refreshing = true;
    try {
      final id = FestivalTheme.byId(await festivalConfigLoad()).id;
      _failures = 0;
      _applyRemote(id);
    } catch (_) {
      _failures += 1;
    } finally {
      _refreshing = false;
    }
  }

  /// Landing visible or app resume. One retry after a failure, then wait.
  Future<void> refreshIfIdle() async {
    if (playLocked) return;
    if (_failures > 1) return;
    await refresh();
  }

  void onResumed() {
    if (_failures > 1) _failures = 1;
    refreshIfIdle();
  }

  void setPlayLocked(bool locked) {
    if (playLocked == locked) return;
    playLocked = locked;
    if (!locked) _flushPending();
    notifyListeners();
  }

  void setCelebrationLocked(bool locked) {
    if (celebrationLocked == locked) return;
    celebrationLocked = locked;
    notifyListeners();
  }

  Future<void> setCalm(bool value) async {
    calm = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(festivalCalmPrefsKey, value);
    } catch (_) {}
  }

  Future<void> dismissCaption() async {
    _dismissedCaptions.add(_appliedId);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$festivalCaptionPrefsPrefix$_appliedId', true);
    } catch (_) {}
  }

  /// Admin PATCH result. Respects the play lock so a live felt does not jump.
  void applyRemote(String id) => _applyRemote(FestivalTheme.byId(id).id);

  /// Admin chose a look. Apply now even during a hand — a bottom snackbar
  /// or a delayed revert looks like the control is broken.
  Future<String> pushFestival(String id) async {
    final next = FestivalTheme.byId(id).id;
    pushing = true;
    notifyListeners();
    try {
      final confirmed = FestivalTheme.byId(await festivalSet(next)).id;
      _pendingId = null;
      _setApplied(confirmed);
      return confirmed;
    } finally {
      pushing = false;
      notifyListeners();
    }
  }

  void resetForTest() {
    _appliedId = FestivalTheme.off.id;
    _pendingId = null;
    playLocked = false;
    celebrationLocked = false;
    calm = false;
    _dismissedCaptions.clear();
    _refreshing = false;
    pushing = false;
    _failures = 0;
    greetingPlayed = false;
  }

  void _applyRemote(String id) {
    if (playLocked) {
      _pendingId = id;
      return;
    }
    _setApplied(id);
  }

  void _flushPending() {
    final pending = _pendingId;
    _pendingId = null;
    if (pending != null) _setApplied(pending);
  }

  void _setApplied(String id) {
    final resolved = FestivalTheme.byId(id).id;
    if (_appliedId == resolved) return;
    _appliedId = resolved;
    notifyListeners();
    _persistId(resolved);
  }

  Future<void> _persistId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(festivalIdPrefsKey, id);
    } catch (_) {}
  }
}

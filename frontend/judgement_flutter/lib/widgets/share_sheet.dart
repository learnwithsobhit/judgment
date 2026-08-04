import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import '../state/game_controller.dart';
import '../util/avatar_pack.dart';
import '../util/share_analytics.dart';
import '../util/social_share.dart';
import '../util/web_file_share.dart';
import 'share_result_card.dart';

/// Bottom sheet: platform share + optional trophy card save.
Future<void> showSocialShareSheet({
  required BuildContext context,
  required String text,
  required String url,
  ShareCampaign campaign = ShareCampaign.resultWin,
  GameController? controller,
  List<RankedPlayer>? ranking,
  String? nightLine,
  String title = 'Share',
}) async {
  recordShareEvent('share_opened', {'campaign': campaign.utmValue});
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: feltGreenDark,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return _ShareSheetBody(
        title: title,
        text: text,
        url: url,
        controller: controller,
        ranking: ranking,
        nightLine: nightLine,
      );
    },
  );
}

class _ShareSheetBody extends StatefulWidget {
  final String title;
  final String text;
  final String url;
  final GameController? controller;
  final List<RankedPlayer>? ranking;
  final String? nightLine;

  const _ShareSheetBody({
    required this.title,
    required this.text,
    required this.url,
    this.controller,
    this.ranking,
    this.nightLine,
  });

  @override
  State<_ShareSheetBody> createState() => _ShareSheetBodyState();
}

class _ShareSheetBodyState extends State<_ShareSheetBody> {
  var _capturing = false;

  Future<void> _channel(ShareChannel channel) async {
    if (channel == ShareChannel.system) {
      final ok = await webShareText(widget.text, url: widget.url);
      if (!ok && mounted) {
        await shareToChannel(
          channel: ShareChannel.copy,
          text: widget.text,
          url: widget.url,
        );
        _toast('Copied — paste anywhere');
      } else if (ok) {
        recordShareEvent('share_channel_selected', {'channel': 'system'});
      }
      return;
    }
    final used = await shareToChannel(
      channel: channel,
      text: widget.text,
      url: widget.url,
    );
    if (!mounted) return;
    if (used == ShareChannel.copy && channel != ShareChannel.copy) {
      _toast('Copied — paste into the app');
    } else if (channel == ShareChannel.copy) {
      _toast('Copied');
    }
  }

  Future<void> _precacheAvatars(BuildContext overlayContext) async {
    final ranking = widget.ranking;
    final c = widget.controller;
    if (ranking == null || c == null) return;
    for (final r in ranking.take(3)) {
      final path = avatarAssetPath(c.avatarOf(r.playerId));
      if (path == null) continue;
      try {
        await precacheImage(AssetImage(path), overlayContext);
      } catch (_) {
        // Glyph fallback is fine if an asset is missing.
      }
    }
  }

  /// Mount the card on the root overlay so it paints (sheet clip skips paint on web).
  Future<Uint8List?> _captureTrophyCard() async {
    final c = widget.controller;
    final ranking = widget.ranking;
    if (c == null || ranking == null || ranking.isEmpty) return null;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return null;

    final cardKey = GlobalKey();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        // Fully opaque so the layer is definitely painted; covered by a scrim.
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: IgnorePointer(
                child: Material(
                  color: feltGreenDark,
                  child: ShareResultCard(
                    boundaryKey: cardKey,
                    controller: c,
                    ranking: ranking,
                    nightLine: widget.nightLine,
                  ),
                ),
              ),
            ),
            const ModalBarrier(dismissible: false, color: Color(0xCC0A1F14)),
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: goldAccent,
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(entry);
    try {
      await _precacheAvatars(context);
      for (var i = 0; i < 5; i++) {
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      return await captureShareCardPng(
        cardKey,
        pixelRatio: kIsWeb ? 2 : 3,
      ).timeout(const Duration(seconds: 10));
    } finally {
      entry.remove();
    }
  }

  Future<void> _saveImage() async {
    final c = widget.controller;
    final ranking = widget.ranking;
    if (c == null || ranking == null || ranking.isEmpty) {
      _toast('Results not ready for an image');
      return;
    }
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final bytes = await _captureTrophyCard();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) _toast('Could not create image — try again');
        return;
      }
      final ok = await shareOrDownloadPng(
        bytes,
        'judgement-win.png',
        text: widget.text,
      );
      recordShareEvent('share_image_saved', {
        'channel': ok ? 'download' : 'failed',
      });
      if (!mounted) return;
      _toast(ok
          ? 'Trophy card ready — share it to your Story'
          : 'Could not save image');
    } on TimeoutException {
      if (mounted) _toast('Image timed out — try again');
      recordShareEvent('share_image_saved', {'channel': 'timeout'});
    } catch (e) {
      if (kDebugMode) debugPrint('trophy card capture failed: $e');
      if (mounted) _toast('Could not create image — try again');
      recordShareEvent('share_image_saved', {'channel': 'error'});
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canImage =
        widget.controller != null && (widget.ranking?.isNotEmpty ?? false);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(Icons.chat, 'WhatsApp', () => _channel(ShareChannel.whatsapp)),
                _chip(Icons.send, 'Telegram', () => _channel(ShareChannel.telegram)),
                _chip(
                  Icons.camera_alt_outlined,
                  'Instagram',
                  canImage && !_capturing ? _saveImage : null,
                ),
                _chip(Icons.alternate_email, 'X', () => _channel(ShareChannel.x)),
                _chip(Icons.facebook, 'Facebook', () => _channel(ShareChannel.facebook)),
                _chip(Icons.ios_share, 'More', () => _channel(ShareChannel.system)),
                _chip(Icons.copy, 'Copy', () => _channel(ShareChannel.copy)),
              ],
            ),
            if (canImage) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _capturing ? null : _saveImage,
                icon: _capturing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined),
                label: Text(
                  _capturing ? 'Creating card…' : 'Save trophy card image',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, VoidCallback? onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: goldAccent),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Colors.black26,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/auth_service.dart';
import '../auth/auth_store.dart';
import '../networking/api_client.dart';
import '../util/avatar_pack.dart';
import '../util/avatar_upload.dart';
import 'avatar_picker.dart';
import 'player_avatar.dart';

Future<PersistedAuth?> showProfileSheet({
  required BuildContext context,
  required AuthService auth,
  bool inActiveGame = false,
}) {
  return showModalBottomSheet<PersistedAuth>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A2E1C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _ProfileSheet(auth: auth, inActiveGame: inActiveGame),
  );
}

class _ProfileSheet extends StatefulWidget {
  final AuthService auth;
  final bool inActiveGame;

  const _ProfileSheet({required this.auth, required this.inActiveGame});

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late final TextEditingController _name;
  bool _busy = false;

  PersistedAuth? get _profile => widget.auth.current;
  ApiClient get _api => widget.auth.api;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _profile?.nickname ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.characters.length > 24) {
      _toast('Name must be 1–24 characters');
      return;
    }
    setState(() => _busy = true);
    try {
      final me = await _api.patchMe(name);
      final updated = widget.auth.current!.copyWith(
        nickname: me.session.nickname,
        avatarId: me.session.avatarId ?? me.user?.avatarId,
        avatarUrl: me.session.avatarUrl ?? me.user?.avatarUrl,
      );
      widget.auth.current = updated;
      await savePersistedAuth(updated);
      if (mounted) Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPack() async {
    final id = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose avatar'),
        content: SizedBox(
          width: 360,
          child: AvatarPicker(
            selectedId: _profile?.avatarId ?? defaultAvatarId,
            onSelected: (id) => Navigator.of(context).pop(id),
          ),
        ),
      ),
    );
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await _api.setAvatar(id);
      final updated = widget.auth.current!.copyWith(
        avatarId: id,
        avatarUrl: null,
        avatarKind: 'pack',
      );
      widget.auth.current = updated;
      await savePersistedAuth(updated);
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload(ImageSource source) async {
    setState(() => _busy = true);
    try {
      final url = await uploadAvatarPhoto(_api, source: source);
      final updated = widget.auth.current!.copyWith(
        avatarUrl: url,
        avatarKind: 'upload',
      );
      widget.auth.current = updated;
      await savePersistedAuth(updated);
      if (mounted) setState(() {});
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    try {
      await widget.auth.logout(inActiveGame: widget.inActiveGame);
      if (mounted) Navigator.of(context).pop(null);
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your Judgement account and uploaded avatar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.auth.deleteAccount(inActiveGame: widget.inActiveGame);
      if (mounted) Navigator.of(context).pop(null);
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (profile == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Not signed in'),
      );
    }
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerAvatar(
            avatarId: profile.avatarId,
            avatarUrl: profile.avatarUrl,
            nickname: profile.nickname,
            radius: 40,
          ),
          const SizedBox(height: 8),
          if (profile.provider != null)
            Text(
              profile.provider!.toUpperCase(),
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
            maxLength: 24,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _pickPack,
                child: const Text('Pack avatar'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _upload(ImageSource.camera),
                child: const Text('Camera'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _upload(ImageSource.gallery),
                child: const Text('Gallery'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _saveName,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _logout,
            child: const Text('Log out'),
          ),
          TextButton(
            onPressed: _busy ? null : _delete,
            child: const Text(
              'Delete account',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
}

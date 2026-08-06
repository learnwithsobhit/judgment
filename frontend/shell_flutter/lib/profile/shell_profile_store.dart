import 'shell_profile.dart';
import 'shell_profile_store_stub.dart'
    if (dart.library.js_interop) 'shell_profile_store_web.dart' as impl;

const kShellProfileKey = 'table_games_profile_v1';

ShellProfile? readShellProfile() => impl.readShellProfile();

void writeShellProfile(ShellProfile profile) => impl.writeShellProfile(profile);

void clearShellProfile() => impl.clearShellProfile();

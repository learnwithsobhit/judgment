import 'package:dehla_flutter/dehla_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shell_flutter/game_picker_screen.dart';
import 'package:shell_flutter/uri_home.dart';

void main() {
  test('root path opens game picker', () {
    expect(resolveShellHome(Uri.parse('https://example.com/')), isA<GamePickerScreen>());
  });

  test('dp path opens Dehla home', () {
    expect(resolveShellHome(Uri.parse('https://example.com/dp')), isA<DehlaHomeScreen>());
  });

  test('dp room deep link opens Dehla home with join code', () {
    final home = resolveShellHome(Uri.parse('https://example.com/dp/r/ABCD12'));
    expect(home, isA<DehlaHomeScreen>());
    expect((home as DehlaHomeScreen).initialJoinCode, 'ABCD12');
  });
}

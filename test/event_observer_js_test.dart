import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zremote/services/event_observer.dart';

void main() {
  test('真实JavaScript引擎验证来源、nonce、消息及分片边界', () async {
    // Node is used only for this development-time JavaScript regression suite.
    final process = await Process.start('node', [
      'test/js/event_observer_security.cjs',
    ]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(jsonEncode(EventObserver.scriptFor('test-nonce')));
    await process.stdin.close();
    final exitCode = await process.exitCode;
    expect(exitCode, 0, reason: '${await output}\n${await errors}');
  });
}

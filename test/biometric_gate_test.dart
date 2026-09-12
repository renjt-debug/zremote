import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zremote/main.dart';
import 'package:zremote/services/biometric.dart';
import 'package:zremote/state/session_pool.dart';

class _FakeBiometricNotifier extends BiometricNotifier {
  _FakeBiometricNotifier(this.value);

  final bool value;

  @override
  bool build() => value;
}

class _MutableBiometricNotifier extends BiometricNotifier {
  _MutableBiometricNotifier(this._value);

  bool _value;

  @override
  bool build() => _value;

  @override
  Future<void> set(bool value) async {
    _value = value;
    state = value;
  }
}

Future<void> pumpGate(
  WidgetTester tester, {
  required bool enabled,
  required Duration relockAfter,
  required Future<bool> Function(String reason) authenticate,
  BiometricNotifier Function()? notifier,
  Widget child = const Text('SECRET'),
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        biometricProvider.overrideWith(
          () => notifier?.call() ?? _FakeBiometricNotifier(enabled),
        ),
      ],
      child: MaterialApp(
        home: BiometricGate(
          relockAfter: relockAfter,
          authenticate: authenticate,
          child: child,
        ),
      ),
    ),
  );
}

Finder get visibleSecret => find.text('SECRET').hitTestable();
Finder get visibleLock => find.text('已锁定').hitTestable();

void main() {
  testWidgets('冷启动首帧后自动验证，通过则进入内容', (tester) async {
    var calls = 0;
    await pumpGate(
      tester,
      enabled: true,
      relockAfter: const Duration(seconds: 10),
      authenticate: (reason) async {
        calls++;
        return true;
      },
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(visibleSecret, findsOneWidget);
    expect(visibleLock, findsNothing);
    expect(calls, 1);
  });

  testWidgets('验证被取消：停在锁屏，且不自动重弹', (tester) async {
    var calls = 0;
    await pumpGate(
      tester,
      enabled: true,
      relockAfter: const Duration(seconds: 10),
      authenticate: (reason) async {
        calls++;
        return false;
      },
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(seconds: 2));
    expect(visibleLock, findsOneWidget);
    expect(visibleSecret, findsNothing);
    expect(calls, 1, reason: '取消后不得循环重弹验证框');
  });

  testWidgets('短暂离开回前台免验证', (tester) async {
    var calls = 0;
    await pumpGate(
      tester,
      enabled: true,
      relockAfter: const Duration(hours: 1),
      authenticate: (reason) async {
        calls++;
        return true;
      },
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 100));
    expect(visibleSecret, findsNothing, reason: '宽限期内退到后台也必须遮挡内容');
    expect(find.text('SECRET'), findsOneWidget, reason: '遮挡不能卸载后台会话');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(visibleSecret, findsOneWidget);
    expect(calls, 1, reason: '宽限期内不得二次验证');
  });

  testWidgets('重新锁定后移除底层焦点，不能用硬件键盘输入或重新聚焦', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var authCalls = 0;
    var keyEvents = 0;
    await pumpGate(
      tester,
      enabled: true,
      relockAfter: Duration.zero,
      authenticate: (_) async => ++authCalls == 1,
      child: KeyboardListener(
        focusNode: focus,
        onKeyEvent: (_) => keyEvents++,
        child: const Text('SECRET'),
      ),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(focus.hasFocus, isTrue);
    expect(keyEvents, greaterThan(0));
    final eventsBeforeLock = keyEvents;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(visibleLock, findsOneWidget);
    expect(focus.canRequestFocus, isFalse);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    expect(focus.hasFocus, isFalse);
    expect(keyEvents, eventsBeforeLock);
  });

  testWidgets('原生快照防护跟随安全开关且前台就绪只在安全帧后发出', (tester) async {
    const channel = MethodChannel('zremote/privacy');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final mutable = _MutableBiometricNotifier(true);
    await pumpGate(
      tester,
      enabled: true,
      relockAfter: Duration.zero,
      authenticate: (_) async => false,
      notifier: () => mutable,
    );
    await tester.pump();
    expect(calls.last.method, 'setScreenPrivacy');
    expect(calls.last.arguments, {'enabled': true, 'foreground': true});

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(calls.last.arguments, {'enabled': true, 'foreground': false});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(visibleLock, findsOneWidget);
    expect(calls.last.arguments, {'enabled': true, 'foreground': true});

    await mutable.set(false);
    await tester.pump();
    expect(calls.last.arguments, {'enabled': false, 'foreground': true});
  });

  testWidgets('超时离开回前台重新上锁并验证', (tester) async {
    var calls = 0;
    await pumpGate(
      tester,
      enabled: true,
      relockAfter: Duration.zero,
      authenticate: (reason) async {
        calls++;
        return true;
      },
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(calls, 2, reason: '超过宽限期应重新验证');
    expect(visibleSecret, findsOneWidget);
  });

  testWidgets('验证 UI 引起的 inactive 不算离开（防慢速验证后二次弹框）', (tester) async {
    var calls = 0;
    final gate = Completer<bool>();
    await pumpGate(
      tester,
      enabled: true,
      relockAfter: const Duration(seconds: 10),
      authenticate: (reason) async {
        calls++;
        return gate.future;
      },
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(visibleLock, findsOneWidget);
    expect(calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 1, reason: '被自身验证 UI 盖住不算离开');

    gate.complete(true);
    await tester.pump();
    await tester.pump();
    expect(visibleSecret, findsOneWidget);
    expect(calls, 1);
  });

  for (final code in BiometricService.unavailableCodes) {
    testWidgets('认证不可用 $code：保持锁定和安全开关，恢复后可重试', (tester) async {
      final mutable = _MutableBiometricNotifier(true);
      var available = false;
      await pumpGate(
        tester,
        enabled: true,
        relockAfter: const Duration(seconds: 10),
        authenticate: (reason) async {
          if (available) return true;
          throw BiometricUnavailableException(LocalAuthException(code: code));
        },
        notifier: () => mutable,
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();

      expect(visibleSecret, findsNothing);
      expect(visibleLock, findsOneWidget);
      expect(mutable._value, isTrue, reason: '认证异常不得关闭安全开关');

      available = true;
      await tester.tap(find.byIcon(Icons.lock_open));
      await tester.pump();
      await tester.pump();

      expect(visibleSecret, findsOneWidget);
      expect(visibleLock, findsNothing);
      expect(mutable._value, isTrue);
    });
  }
}

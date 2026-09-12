import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zremote/l10n/app_localizations.dart';
import 'package:zremote/services/biometric.dart';
import 'package:zremote/services/device_store.dart';
import 'package:zremote/state/session_pool.dart';
import 'package:zremote/ui/settings_page.dart';

class _ScriptedPlatform extends LocalAuthPlatform {
  Object result = false;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    if (result is bool) return result as bool;
    throw result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('关闭安全开关的所有不可用异常均保持锁定，只有认证成功才保存关闭', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Use the public storage API so this test also verifies persisted state.
    await DeviceStore.instance.setBiometricEnabled(true);
    final previous = LocalAuthPlatform.instance;
    final auth = _ScriptedPlatform();
    LocalAuthPlatform.instance = auth;
    addTearDown(() => LocalAuthPlatform.instance = previous);
    const keepalive = MethodChannel('zremote/keepalive');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      keepalive,
      (_) async => false,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        keepalive,
        null,
      ),
    );
    const packageInfo = MethodChannel('dev.fluttercommunity.plus/package_info');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      packageInfo,
      (_) async => {
        'appName': 'ZRemote',
        'packageName': 'com.pjpv.zremote',
        'version': '1.4.0',
        'buildNumber': '7',
        'buildSignature': '',
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        packageInfo,
        null,
      ),
    );
    tester.view.physicalSize = const Size(760, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          biometricProvider.overrideWith(
            () => BiometricNotifier(initial: true),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = find.ancestor(
      of: find.byIcon(Icons.fingerprint),
      matching: find.byType(SwitchListTile),
    );
    for (final code in BiometricService.unavailableCodes) {
      auth.result = LocalAuthException(code: code);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(toggle).value,
        isTrue,
        reason: '$code',
      );
      expect(
        await DeviceStore.instance.biometricEnabled(),
        isTrue,
        reason: '$code',
      );
    }
    auth.result = false;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(await DeviceStore.instance.biometricEnabled(), isTrue);

    auth.result = true;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(await DeviceStore.instance.biometricEnabled(), isFalse);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zremote/l10n/app_localizations.dart';
import 'package:zremote/models/device.dart';
import 'package:zremote/ui/session_view.dart';

void main() {
  testWidgets('旧存储的非官方链接不创建WebView并说明拒绝原因', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SessionView(
            device: RemoteDevice(
              id: 'legacy-device',
              baseUrl: 'https://untrusted.example/remote/v4',
              params: const {'sid': 'legacy-sid', 'hash': 'legacy-hash'},
              label: '旧设备',
              createdAt: DateTime(2026),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(InAppWebView), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('仅接受 https://zcode.z.ai'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh).last);
    await tester.pump();
    expect(find.byType(InAppWebView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

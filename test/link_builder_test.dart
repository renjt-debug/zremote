import 'package:flutter_test/flutter_test.dart';
import 'package:zremote/models/device.dart';
import 'package:zremote/services/link_builder.dart';

void main() {
  const sampleUrl =
      'https://zcode.z.ai/remote/v4?sid=d_TestSid000000000000'
      '&hash=AbCdEf123%3D&t=1788059173414'
      '&mid=00000000-0000-4000-8000-000000000000'
      '&name=DESKTOP-ABC123&app_version=3.10.1';

  group('LinkBuilder.parse', () {
    test('官方链接：全部参数入库，label 取 name', () {
      final d = LinkBuilder.parse(sampleUrl)!;
      expect(d.sid, 'd_TestSid000000000000');
      expect(d.params['hash'], 'AbCdEf123=');
      expect(d.params['mid'], '00000000-0000-4000-8000-000000000000');
      expect(d.params['app_version'], '3.10.1');
      expect(d.label, 'DESKTOP-ABC123');
      expect(d.baseUrl, 'https://zcode.z.ai/remote/v4');
    });

    test('缺 sid 拒收', () {
      const url = 'https://zcode.z.ai/remote/v4?hash=x&t=1&mid=m&name=n';
      expect(LinkBuilder.parse(url), isNull);
    });

    test('缺 hash 拒收', () {
      const url = 'https://zcode.z.ai/remote/v4?sid=s&t=1';
      expect(LinkBuilder.parse(url), isNull);
    });

    test('空参数值视同缺失', () {
      const url = 'https://zcode.z.ai/remote/v4?sid=&hash=x';
      expect(LinkBuilder.parse(url), isNull);
    });

    test('非 http(s) 拒收', () {
      expect(LinkBuilder.parse('zcode://oauth/callback?sid=s&hash=h'), isNull);
      expect(LinkBuilder.parse('javascript:alert(1)?sid=s&hash=h'), isNull);
    });

    test('垃圾输入拒收', () {
      expect(LinkBuilder.parse(''), isNull);
      expect(LinkBuilder.parse('   '), isNull);
      expect(LinkBuilder.parse('随便什么文字'), isNull);
      expect(LinkBuilder.parse('http://'), isNull);
    });

    test('宽松：多余参数保留，name 缺省存空（默认名在渲染层本地化）', () {
      const url = 'https://zcode.z.ai/remote/v5?sid=s1&hash=h1&future=xyz';
      final d = LinkBuilder.parse(url)!;
      expect(d.params['future'], 'xyz');
      expect(d.label, '');
    });

    test('官方 HTTPS 默认端口可用', () {
      const url = 'https://zcode.z.ai:443/remote/v4?sid=s&hash=h';
      final d = LinkBuilder.parse(url)!;
      expect(Uri.parse(d.baseUrl).port, 443);
    });

    test('拒绝非官方来源、HTTP、非默认端口和userinfo', () {
      for (final base in [
        'http://zcode.z.ai/remote/v4',
        'https://relay.example.com/remote/v4',
        'https://zcode.z.ai.evil.example/remote/v4',
        'https://sub.zcode.z.ai/remote/v4',
        'https://zcode.z.ai./remote/v4',
        'https://zcode.z.ai:8443/remote/v4',
        'https://user@zcode.z.ai/remote/v4',
        'https://zcode.z.ai@evil.example/remote/v4',
      ]) {
        expect(LinkBuilder.parse('$base?sid=s&hash=h'), isNull, reason: base);
        expect(LinkBuilder.allowsNavigation(base), isFalse, reason: base);
      }
    });

    test('拒绝重复参数、畸形转义、控制字符和超长输入', () {
      for (final query in [
        'sid=s&sid=t&hash=h',
        'sid=s&hash=%',
        'sid=s&hash=%GG',
        'sid=s&hash=%0A',
        'sid=s&hash=${'a' * (LinkBuilder.maxParameterLength + 1)}',
        'sid=s&hash=h&name=${'a' * 257}',
      ]) {
        expect(LinkBuilder.parse('https://zcode.z.ai/?$query'), isNull);
      }
      expect(
        LinkBuilder.parse(
          'https://zcode.z.ai/${'a' * LinkBuilder.maxLinkLength}?sid=s&hash=h',
        ),
        isNull,
      );
    });

    test('导航仅允许官方HTTPS，包括同源片段', () {
      expect(
        LinkBuilder.allowsNavigation('https://zcode.z.ai/remote/v4#task'),
        isTrue,
      );
      for (final url in [
        'file:///data/x',
        'content://x',
        'javascript:alert(1)',
        'data:text/html,hi',
        'intent://zcode.z.ai',
        'about:blank',
        null,
      ]) {
        expect(LinkBuilder.allowsNavigation(url), isFalse);
      }
    });
  });

  group('LinkBuilder.buildUrl', () {
    test('t 刷新为指定时刻，其余参数与顺序原样', () {
      final d = LinkBuilder.parse(sampleUrl)!;
      final now = DateTime.fromMillisecondsSinceEpoch(1790000000000);
      final uri = LinkBuilder.buildUrl(d, now: now);

      expect(uri.queryParameters['t'], '1790000000000');
      expect(uri.queryParameters['sid'], d.sid);
      expect(uri.queryParameters['hash'], 'AbCdEf123=');
      expect(uri.queryParameters['mid'], d.params['mid']);
      expect(uri.queryParameters['name'], 'DESKTOP-ABC123');
      expect(uri.queryParameters['app_version'], '3.10.1');
      expect(uri.toString(), contains('hash=AbCdEf123%3D'));
      expect(uri.toString(), startsWith('https://zcode.z.ai/remote/v4?'));
      expect(uri.toString(), isNot(endsWith('?')));
    });

    test('不修改原设备对象（不可变性）', () {
      final d = LinkBuilder.parse(sampleUrl)!;
      final before = Map.of(d.params);
      LinkBuilder.buildUrl(d, now: DateTime.fromMillisecondsSinceEpoch(1));
      expect(d.params, before);
      expect(d.params.containsKey('t'), isTrue);
    });

    test('旧存储的非法来源或缺少凭据不能生成网络请求', () {
      final d = LinkBuilder.parse(sampleUrl)!;
      RemoteDevice stored(String baseUrl, Map<String, String> params) =>
          RemoteDevice(
            id: d.id,
            baseUrl: baseUrl,
            params: params,
            label: d.label,
            createdAt: d.createdAt,
          );
      for (final old in [
        stored('https://evil.example/', d.params),
        stored('http://zcode.z.ai/', d.params),
        stored(d.baseUrl, const {'sid': 's'}),
      ]) {
        expect(LinkBuilder.tryBuildUrl(old), isNull);
        expect(() => LinkBuilder.buildUrl(old), throwsFormatException);
      }
    });
  });

  group('RemoteDevice', () {
    test('JSON 往返无损', () {
      final d = LinkBuilder.parse(sampleUrl)!;
      final restored = RemoteDevice.fromJson(d.toJson());
      expect(restored.id, d.id);
      expect(restored.baseUrl, d.baseUrl);
      expect(restored.params, d.params);
      expect(restored.label, d.label);
      expect(restored.createdAt, d.createdAt);
    });

    test('sidSuffix 取尾部 6 位', () {
      final d = LinkBuilder.parse(sampleUrl)!;
      expect(d.sidSuffix, '000000');
    });

    test('rename 只改 label', () {
      final d = LinkBuilder.parse(sampleUrl)!;
      final r = d.copyWith(label: '工作机');
      expect(r.label, '工作机');
      expect(r.id, d.id);
      expect(r.params, d.params);
    });
  });
}

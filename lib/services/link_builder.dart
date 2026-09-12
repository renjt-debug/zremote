import 'dart:core';

import 'package:uuid/uuid.dart';

import '../models/device.dart';

class LinkBuilder {
  static const trustedOrigin = 'https://zcode.z.ai';
  static const maxLinkLength = 16384;
  static const maxParameterLength = 4096;
  static final _invalidEscape = RegExp(r'%(?![0-9a-fA-F]{2})');
  static final _rawWhitespace = RegExp(r'[\x00-\x20\x7f]');
  static final _controls = RegExp(r'[\x00-\x1f\x7f]');
  static const _sidKey = 'sid';
  static const _hashKey = 'hash';
  static const _tKey = 't';
  static const _nameKey = 'name';

  static RemoteDevice? parse(String input, {String? id, DateTime? now}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty ||
        trimmed.length > maxLinkLength ||
        _invalidEscape.hasMatch(trimmed) ||
        _rawWhitespace.hasMatch(trimmed)) {
      return null;
    }
    try {
      final uri = Uri.parse(trimmed);
      if (!isTrustedUri(uri)) return null;

      final params = <String, String>{};
      final allParams = uri.queryParametersAll;
      if (allParams.length > 64) return null;
      for (final entry in allParams.entries) {
        if (entry.key.length > 128 ||
            entry.value.length != 1 ||
            _controls.hasMatch(entry.key)) {
          return null;
        }
        final value = entry.value.single;
        if (value.length > maxParameterLength || _controls.hasMatch(value)) {
          return null;
        }
        if (entry.key.isNotEmpty && value.isNotEmpty) params[entry.key] = value;
      }

      final sid = params[_sidKey];
      final hash = params[_hashKey];
      if (sid == null || sid.isEmpty || hash == null || hash.isEmpty) {
        return null;
      }

      final base = uri.hasPort
          ? Uri(
              scheme: uri.scheme,
              userInfo: uri.userInfo,
              host: uri.host,
              port: uri.port,
              path: uri.path,
            )
          : Uri(
              scheme: uri.scheme,
              userInfo: uri.userInfo,
              host: uri.host,
              path: uri.path,
            );

      final label = params[_nameKey];
      if (label != null && label.length > 256) return null;
      return RemoteDevice(
        id: id ?? const Uuid().v4(),
        baseUrl: base.toString(),
        params: params,
        label: label ?? '',
        createdAt: now ?? DateTime.now(),
      );
    } on FormatException {
      return null;
    }
  }

  /// The same policy applies to imports, old stored devices and navigation.
  static bool isTrustedUri(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'zcode.z.ai' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty;

  static bool allowsNavigation(String? url) {
    if (url == null ||
        url.length > maxLinkLength ||
        _invalidEscape.hasMatch(url) ||
        _rawWhitespace.hasMatch(url)) {
      return false;
    }
    try {
      return isTrustedUri(Uri.parse(url));
    } on FormatException {
      return false;
    }
  }

  static Uri? tryBuildUrl(RemoteDevice device, {DateTime? now}) {
    try {
      return buildUrl(device, now: now);
    } on FormatException {
      return null;
    }
  }

  static Uri buildUrl(RemoteDevice device, {DateTime? now}) {
    if (!allowsNavigation(device.baseUrl) ||
        device.params.length > 64 ||
        device.params.entries.any(
          (e) => e.key.length > 128 || e.value.length > maxParameterLength,
        )) {
      throw const FormatException('Untrusted remote-control link');
    }
    final params = Map<String, String>.of(device.params);
    params[_tKey] = (now ?? DateTime.now()).millisecondsSinceEpoch.toString();
    final uri = Uri.parse(device.baseUrl).replace(queryParameters: params);
    if (parse(uri.toString(), id: device.id, now: device.createdAt) == null) {
      throw const FormatException('Invalid remote-control link');
    }
    return uri;
  }
}

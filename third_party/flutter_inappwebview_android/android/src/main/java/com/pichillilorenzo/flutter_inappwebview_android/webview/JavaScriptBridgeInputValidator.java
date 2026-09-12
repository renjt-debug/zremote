package com.pichillilorenzo.flutter_inappwebview_android.webview;

/** ZRemote validation for untrusted arguments entering the native JS bridge. */
final class JavaScriptBridgeInputValidator {
  static final int MAX_ARGS_BYTES = 8 * 1024 * 1024;
  private static final int MAX_CALLBACK_ID_LENGTH = 20;

  private JavaScriptBridgeInputValidator() {}

  static boolean isValid(String handlerName, String callbackId, String args) {
    if (handlerName == null || callbackId == null || args == null
        || callbackId.length() == 0 || callbackId.length() > MAX_CALLBACK_ID_LENGTH
        || args.length() > MAX_ARGS_BYTES) {
      return false;
    }
    for (int i = 0; i < callbackId.length(); i++) {
      char digit = callbackId.charAt(i);
      if (digit < '0' || digit > '9') {
        return false;
      }
    }

    // Count UTF-8 bytes without allocating a second attacker-sized buffer.
    // JSON.stringify escapes lone surrogates; reject malformed raw UTF-16.
    int bytes = 0;
    for (int i = 0; i < args.length(); i++) {
      char character = args.charAt(i);
      if (character <= 0x7f) {
        bytes++;
      } else if (character <= 0x7ff) {
        bytes += 2;
      } else if (Character.isHighSurrogate(character)) {
        if (i + 1 >= args.length() || !Character.isLowSurrogate(args.charAt(i + 1))) {
          return false;
        }
        bytes += 4;
        i++;
      } else if (Character.isLowSurrogate(character)) {
        return false;
      } else {
        bytes += 3;
      }
      if (bytes > MAX_ARGS_BYTES) {
        return false;
      }
    }
    return true;
  }
}

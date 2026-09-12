# ZRemote local security patch

This directory vendors the application-required sources of the published
`flutter_inappwebview_android` **1.1.3** package. Upstream package metadata is
retained in `pubspec.yaml`; the upstream repository path is
`flutter_inappwebview/flutter_inappwebview_android` at
<https://github.com/pichillilorenzo/flutter_inappwebview/tree/master/flutter_inappwebview_android>.
The retained `LICENSE` is Apache License 2.0. These local modifications are
identified below; the package version remains the upstream version for dependency
compatibility. ZRemote selects this copy through its root dependency override.

## Native JavaScript bridge input validation

Upstream `android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/JavaScriptBridgeInterface.java`
accepts `_callHandlerID` through an Android `@JavascriptInterface` and inserts it
directly into JavaScript evaluated in the WebView's main frame, both on success
and on error. Android exposes this interface to subframes as well. An untrusted
frame can therefore supply JavaScript syntax in place of a numeric callback ID;
application-level validation of the handler payload happens too late to secure
the native response construction.

The local guard runs at the very beginning of `_callHandler`, before accessing
the WebView, posting work to its looper, invoking internal handlers, or forwarding
anything to Flutter. It drops calls unless the callback ID consists of 1–20 ASCII
decimal digits, the handler name and argument string are non-null, and the argument
string is at most **8 MiB of UTF-8 data**. It counts UTF-8 size without allocating a
second payload buffer and rejects malformed raw UTF-16 surrogate sequences.
Ordinary `JSON.stringify` output, including escaped lone surrogates, is unaffected.

Changed or added files:

- `android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/JavaScriptBridgeInterface.java`
- `android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/JavaScriptBridgeInputValidator.java`
- `android/src/test/java/com/pichillilorenzo/flutter_inappwebview_android/webview/JavaScriptBridgeInputValidatorTest.java`
- `android/build.gradle` adds the test-only `junit:junit:4.13.2` dependency.

The JUnit tests cover normal calls, numeric ID boundaries, injected expressions,
non-ASCII digits, null values, ASCII and multibyte size boundaries, and surrogate
pairs. Run from ZRemote's `android` directory after resolving Flutter dependencies:

```text
gradlew.bat :flutter_inappwebview_android:testDebugUnitTest
```

This is a narrow patch for native response-script injection and oversized/null
bridge inputs. It does not authenticate frame origins, restrict all legitimate
subframe handler calls, validate arbitrary handler JSON schemas, or prevent an
untrusted page from attempting many individually valid calls. Those controls
belong to the embedding application's navigation and message policies. This copy
contains no iOS implementation; iOS requires a separate review.

When upgrading the upstream package, verify the equivalent native entry points
and both success/error response construction before removing or rebasing this
patch. Keep the regression tests while the local guard is needed.

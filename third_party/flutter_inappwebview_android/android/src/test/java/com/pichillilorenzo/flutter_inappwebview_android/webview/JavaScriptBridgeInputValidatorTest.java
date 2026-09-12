package com.pichillilorenzo.flutter_inappwebview_android.webview;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import org.junit.Test;

public class JavaScriptBridgeInputValidatorTest {
  @Test
  public void acceptsNormalBridgeCallsAndCallbackIdBoundaries() {
    assertTrue(valid("0", "[]"));
    assertTrue(valid("2147483647", "[{\"event\":\"完成\",\"value\":1}]"));
    assertTrue(valid("12345678901234567890", "[]"));
    assertTrue(valid("1", "[\"\uD83D\uDE00\"]"));
    assertTrue(valid("1", "[\"\\ud800\"]"));
  }

  @Test
  public void rejectsExecutableCallbackIdsAndNonAsciiDecimalForms() {
    for (String id : new String[] {
        "", "123456789012345678901", "-1", "+1", "1.0", "1e2", "0x1",
        " 1", "1 ", "1\n", "\uFF11", "\u0661", "1\u0000",
        "0];window.probe=1;//", "0] || (window.probe=1) || window.bridge[0",
        "'1'", "\"1\"", "null", "undefined"
    }) {
      assertFalse("Unsafe callback ID: " + id, valid(id, "[]"));
    }
  }

  @Test
  public void rejectsNullArgumentsBeforeDispatch() {
    assertFalse(JavaScriptBridgeInputValidator.isValid(null, "1", "[]"));
    assertFalse(JavaScriptBridgeInputValidator.isValid("handler", null, "[]"));
    assertFalse(JavaScriptBridgeInputValidator.isValid("handler", "1", null));
  }

  @Test
  public void boundsAsciiPayloadsAtEightMiB() {
    int limit = JavaScriptBridgeInputValidator.MAX_ARGS_BYTES;
    assertTrue(valid("1", repeat('a', limit)));
    assertFalse(valid("1", repeat('a', limit + 1)));
  }

  @Test
  public void boundsMultibytePayloadsByBytesInsteadOfCharacters() {
    int limit = JavaScriptBridgeInputValidator.MAX_ARGS_BYTES;
    String twoByte = repeat('\u00E9', limit / 2);
    assertTrue(valid("1", twoByte));
    assertFalse(valid("1", twoByte + "a"));
    String threeByte = repeat('\u4E2D', limit / 3);
    assertTrue(valid("1", threeByte + "aa"));
    assertFalse(valid("1", threeByte + "aaa"));
  }

  @Test
  public void countsSurrogatePairsAndRejectsUnpairedSurrogates() {
    char[] pairs = new char[JavaScriptBridgeInputValidator.MAX_ARGS_BYTES / 2];
    for (int i = 0; i < pairs.length; i += 2) {
      pairs[i] = '\uD83D';
      pairs[i + 1] = '\uDE00';
    }
    String fourByte = new String(pairs);
    assertTrue(valid("1", fourByte));
    assertFalse(valid("1", fourByte + "a"));
    assertFalse(valid("1", "\uD800"));
    assertFalse(valid("1", "\uD800a"));
    assertFalse(valid("1", "\uDC00"));
  }

  private static boolean valid(String callbackId, String args) {
    return JavaScriptBridgeInputValidator.isValid("handler", callbackId, args);
  }

  private static String repeat(char character, int count) {
    char[] characters = new char[count];
    Arrays.fill(characters, character);
    return new String(characters);
  }
}

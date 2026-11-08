package com.eroxii.tty_serial;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

import io.flutter.plugin.common.MethodCall;

/**
 * Reads MethodChannel arguments. Dart input is untrusted here: every value
 * is checked for presence, type, range and size before it is used, and a
 * bad one fails with invalidArgument instead of a ClassCastException.
 */
final class Arguments {

    static final int MAX_DATA_BYTES = 256;
    static final int MAX_REPLY_BYTES = 256;
    static final int MAX_TIMEOUT_MS = 30000;

    /**
     * A system program by full path. The name may not start with '.' or '-',
     * so it can be neither a path step nor an option on the su line.
     */
    private static final Pattern PROGRAM = Pattern.compile("^/system/(x)?bin/[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$");

    private Arguments() {
    }

    static int handle(MethodCall call) throws SerialError {
        return integer(call, "handle", 1, Integer.MAX_VALUE);
    }

    static String path(MethodCall call) throws SerialError {
        Object value = require(call, "path");
        if (!(value instanceof String)) throw SerialError.invalidArgument("path must be a String");
        return (String) value;
    }

    /** Checked with PortPaths.checkPrefixes, so they are safe to match paths against. */
    static List<String> prefixes(MethodCall call) throws SerialError {
        Object value = require(call, "prefixes");
        if (!(value instanceof List)) throw SerialError.invalidArgument("prefixes must be a List");
        List<?> raw = (List<?>) value;
        if (raw.size() > PortPaths.MAX_PREFIXES) {
            throw SerialError.invalidArgument("prefixes must have 1-" + PortPaths.MAX_PREFIXES + " items");
        }
        List<String> prefixes = new ArrayList<>(raw.size());
        for (Object item : raw) {
            if (!(item instanceof String)) throw SerialError.invalidArgument("prefixes must be Strings");
            prefixes.add((String) item);
        }
        PortPaths.checkPrefixes(prefixes);
        return prefixes;
    }

    static SerialConfig config(MethodCall call) throws SerialError {
        int baudRate = integer(call, "baudRate", 1, Integer.MAX_VALUE);
        int dataBits = integer(call, "dataBits", 1, 16);
        Object parity = require(call, "parity");
        if (!(parity instanceof String)) throw SerialError.invalidArgument("parity must be a String");
        int stopBits = integer(call, "stopBits", 1, 16);
        return SerialConfig.of(baudRate, dataBits, (String) parity, stopBits);
    }

    static byte[] data(MethodCall call) throws SerialError {
        Object value = require(call, "data");
        if (!(value instanceof byte[])) throw SerialError.invalidArgument("data must be a Uint8List");
        byte[] data = (byte[]) value;
        if (data.length < 1 || data.length > MAX_DATA_BYTES) {
            throw SerialError.invalidArgument("data must be 1-" + MAX_DATA_BYTES + " bytes");
        }
        return data;
    }

    static int replyLength(MethodCall call) throws SerialError {
        return integer(call, "replyLength", 1, MAX_REPLY_BYTES);
    }

    static int timeoutMs(MethodCall call) throws SerialError {
        return integer(call, "timeoutMs", 1, MAX_TIMEOUT_MS);
    }

    static String program(MethodCall call) throws SerialError {
        Object value = require(call, "program");
        if (!(value instanceof String) || !PROGRAM.matcher((String) value).matches()) {
            throw SerialError.invalidArgument("program must be a path like /system/bin/name");
        }
        return (String) value;
    }

    private static Object require(MethodCall call, String key) throws SerialError {
        if (!(call.arguments instanceof Map)) throw SerialError.invalidArgument("arguments must be a Map");
        Object value = ((Map<?, ?>) call.arguments).get(key);
        if (value == null) throw SerialError.invalidArgument(key + " is required");
        return value;
    }

    /** Dart ints above 32 bits arrive as Long; none of ours may be that large. */
    private static int integer(MethodCall call, String key, int min, int max) throws SerialError {
        Object value = require(call, key);
        if (!(value instanceof Integer)) throw SerialError.invalidArgument(key + " must be an int");
        int n = (Integer) value;
        if (n < min || n > max) throw SerialError.invalidArgument(key + " must be " + min + "-" + max);
        return n;
    }
}

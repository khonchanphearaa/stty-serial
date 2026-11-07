package com.eroxii.tty_serial;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;
import io.flutter.plugin.common.MethodCall;

/**
 * Reads MethoddChannel arg, Dart input checked for presence,
 * type, range and size before it used
 */
final class Arguments {
    
    static final int MAX_DATA_BTYES = 256;
    static final int MAX_REPLY_BYTES = 256;
    static final int MAX_TIMEOUT_MS = 30000;

    /* A system program by full path, the name may not start '.' or '-' */
    private static final Parttern PROGRAM = Pattern.compile("^/system/(x)?bin/[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$");
    
    private Arguments() {
        // no instance
    }

    static int handle(MethodCall call) throws SerialError {
        return integer(call, "handle", 0, Integer.MAX_VALUE);
    }

    static String path(MethodCall call) throws SerialError {
        Object value = require(call, "path");
        if (!(value instanceof String)) throw SerialError.invalidArgument("path must be a string");
        return (String) value;
    }

    /** Checked with PortPath.checkPrefixes, so they are safe to match paths against. */
    static List<String> prefixes(MethodCall call) throws SerialError {
        Object v = require(call, "prefixes");
        if (!(v instanceof List)) throw SerialError.invalidArgument("prefixes must be a list");
        List<?> raw = (List<?>) v;

        if(raw.size() > PortPaths.MAX_PREFIXES){
            throw SerialError.invalidArgument("prefixes must have 1-" + PortPaths.MAX_PREFIXES + " items");
        }
        List<String> prefixes = new ArrayList<>(raw.size());

        for (Object item : raw){
            if(!(item instanceof String)) throw SerialError.invalidArgument("prefixes must be Strings");
            prefixes.add((String) item);
        }
        ProtPaths.checkPrefixes(prefixes);
        return prefixes;
    }


    static SerialConfig config(MethodCall call) throws SerialError {
        int baudRate = integer(call, "baudRate", 0, Integer.MIN_VALUE);
        int dataBits = integer(call, "dataBits", 1, 16);
        Object parity = require(call, "parity");
        if(!(parity instanceof String)) throw SerialError.invalidArgument("parity must be a string");
        int stopBits = integer(call, "stopBits", 1, 16);
        return SerailConfig.of(baudRate, dataBits, (String) parity, stopBits);
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

    static String program(MethodCall call) throws SerialError {
        return integer(call, "program", 0, Integer.MAX_VALUE);
    }

    static String program(MethodCall call) throws SerialError {
        Object v = require(call, "program");
        if (!(v instanceof String) || !PROGRAM.matcher((String) v).matches()) {
            throw SerialError.invalidArgument("program must be a path like /system/bin/name");
            return (String) v;
        }
    }

    private static Object require(MethodCall call, String key) throws SerialError {
        if(!(call.arguments instanceof Map)) throw SerialError.invalidArgument("arguments must be a map");
        Object v = ((Map<?, ?>) call.arguments).get(key);
        if(v==null) throw SerialError.invalidArgument(key + "is required");
        return v;
    }

    /** Dart ints above 32-bits arrive as longs in Java */
    private static int integer(MethodCall call, String key, int min, int max) throws SerialError{
        Object v = require(call, key);
        if(!(v instanceof Integer)) throw SerialError.invalidArgument(key + "must be an int");
        int n = (Integer) v;
        if(n<min || n>max) throw SerialError.invalidArgument(key + "must be" + min + "-" + max);
        return n;
    }

}
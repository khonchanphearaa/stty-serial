package com.eroxii.tty_serial;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import org.junit.Test;

public class PluginArgumentsTest {

    @Test
    public void readsAValidOpenCall() throws SerialError {
        MethodCall call = new MethodCall("open", openArgs());
        assertEquals("/dev/ttyS1", Arguments.path(call));
        assertEquals(Arrays.asList("ttyS", "ttyUSB"), Arguments.prefixes(call));
        assertEquals("9600 8N1", Arguments.config(call).toString());
    }

    @Test
    public void rejectsMissingAndMistypedValues() {
        assertInvalid(() -> Arguments.path(new MethodCall("open", null)));
        assertInvalid(() -> Arguments.path(new MethodCall("open", "ttyS1")));
        assertInvalid(() -> Arguments.path(call("path", 1)));
        assertInvalid(() -> Arguments.handle(call("handle", 5000000000L)));
        assertInvalid(() -> Arguments.handle(call("handle", "1")));
        assertInvalid(() -> Arguments.handle(call("handle", 0)));
        assertInvalid(() -> Arguments.prefixes(call("prefixes", "ttyS")));
        assertInvalid(() -> Arguments.prefixes(call("prefixes", Arrays.asList("ttyS", 1))));
        assertInvalid(() -> Arguments.prefixes(call("prefixes", Arrays.asList("ttyS", "../sd"))));

        Map<String, Object> badBaud = openArgs();
        badBaud.put("baudRate", "9600");
        assertInvalid(() -> Arguments.config(new MethodCall("open", badBaud)));
        Map<String, Object> badParity = openArgs();
        badParity.put("parity", 0);
        assertInvalid(() -> Arguments.config(new MethodCall("open", badParity)));
    }

    @Test
    public void enforcesSizeLimits() throws SerialError {
        assertEquals(256, Arguments.data(call("data", new byte[256])).length);
        assertInvalid(() -> Arguments.data(call("data", new byte[0])));
        assertInvalid(() -> Arguments.data(call("data", new byte[257])));
        assertInvalid(() -> Arguments.data(call("data", Arrays.asList(1, 2))));

        assertEquals(256, Arguments.replyLength(call("replyLength", 256)));
        assertInvalid(() -> Arguments.replyLength(call("replyLength", 0)));
        assertInvalid(() -> Arguments.replyLength(call("replyLength", 257)));

        assertEquals(30000, Arguments.timeoutMs(call("timeoutMs", 30000)));
        assertInvalid(() -> Arguments.timeoutMs(call("timeoutMs", 0)));
        assertInvalid(() -> Arguments.timeoutMs(call("timeoutMs", 30001)));
    }

    @Test
    public void pluginRejectsBadCallsBeforeAnyIo() {
        TtySerialPlugin plugin = new TtySerialPlugin();

        Map<String, Object> disk = openArgs();
        disk.put("path", "/dev/block/sda");
        assertEquals(SerialError.INVALID_ARGUMENT, invoke(plugin, "open", disk).errorCode);

        Map<String, Object> write = new HashMap<>();
        write.put("handle", 7);
        write.put("data", new byte[]{1});
        assertEquals(SerialError.CLOSED, invoke(plugin, "write", write).errorCode);

        Recorder unknown = invoke(plugin, "getPlatformVersion", null);
        assertTrue(unknown.notImplemented);
    }

    @Test
    public void closingAnUnknownHandleSucceeds() {
        Recorder result = invoke(new TtySerialPlugin(), "close", args("handle", 42));
        assertTrue(result.succeeded);
        assertNull(result.value);
    }

    @Test
    public void bytesArriveUnchanged() throws SerialError {
        byte[] packet = {0x00, (byte) 0xFF, (byte) 0xDC, 0x23, 0x55, (byte) 0xAA};
        assertArrayEquals(packet, Arguments.data(call("data", packet)));
    }

    private static Map<String, Object> openArgs() {
        Map<String, Object> args = new HashMap<>();
        args.put("path", "/dev/ttyS1");
        args.put("prefixes", Arrays.asList("ttyS", "ttyUSB"));
        args.put("baudRate", 9600);
        args.put("dataBits", 8);
        args.put("parity", "none");
        args.put("stopBits", 1);
        return args;
    }

    private static Map<String, Object> args(String key, Object value) {
        Map<String, Object> args = new HashMap<>();
        args.put(key, value);
        return args;
    }

    private static MethodCall call(String key, Object value) {
        return new MethodCall("test", args(key, value));
    }

    private static Recorder invoke(TtySerialPlugin plugin, String method, Object arguments) {
        Recorder recorder = new Recorder();
        plugin.onMethodCall(new MethodCall(method, arguments), recorder);
        return recorder;
    }

    private static void assertInvalid(org.junit.function.ThrowingRunnable call) {
        SerialError e = assertThrows(SerialError.class, call);
        assertEquals(SerialError.INVALID_ARGUMENT, e.code);
    }

    /** Records what the plugin answered synchronously. */
    private static final class Recorder implements MethodChannel.Result {
        boolean succeeded;
        boolean notImplemented;
        Object value;
        String errorCode;

        @Override
        public void success(Object result) {
            succeeded = true;
            value = result;
        }

        @Override
        public void error(String code, String message, Object details) {
            errorCode = code;
        }

        @Override
        public void notImplemented() {
            notImplemented = true;
        }
    }
}

package com.eroxii.tty_serial;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import java.util.Arrays;

import org.junit.Test;

public class SerialConfigTest {

    @Test
    public void tcnBoardSettingsMatchTheVendingApp() throws SerialError {
        SerialConfig config = SerialConfig.of(9600, 8, "none", 1);
        assertEquals(
                "stty -F /dev/ttyS1 9600 cs8 -parenb -cstopb raw -echo -crtscts -ixon -ixoff clocal cread",
                config.sttyCommand("/dev/ttyS1"));
        assertEquals("9600 8N1", config.toString());
    }

    @Test
    public void parityAndStopBits() throws SerialError {
        assertEquals(
                Arrays.asList("-F", "/dev/ttyUSB0", "19200", "cs7", "parenb", "-parodd", "cstopb",
                        "raw", "-echo", "-crtscts", "-ixon", "-ixoff", "clocal", "cread"),
                SerialConfig.of(19200, 7, "even", 2).sttyArgs("/dev/ttyUSB0"));
        assertEquals(
                Arrays.asList("parenb", "parodd"),
                SerialConfig.of(9600, 8, "odd", 1).sttyArgs("/dev/ttyS0").subList(4, 6));
    }

    @Test
    public void rejectsValuesOutsideTheFixedLists() {
        assertCode(() -> SerialConfig.of(9601, 8, "none", 1));
        assertCode(() -> SerialConfig.of(0, 8, "none", 1));
        assertCode(() -> SerialConfig.of(9600, 6, "none", 1));
        assertCode(() -> SerialConfig.of(9600, 8, "mark", 1));
        assertCode(() -> SerialConfig.of(9600, 8, "none; reboot", 1));
        assertCode(() -> SerialConfig.of(9600, 8, null, 1));
        assertCode(() -> SerialConfig.of(9600, 8, "none", 3));
    }

    @Test
    public void refusesAPathThatCouldCarryShellText() throws SerialError {
        SerialConfig config = SerialConfig.of(9600, 8, "none", 1);
        assertThrows(IllegalArgumentException.class, () -> config.sttyCommand("/dev/ttyS1; reboot"));
        assertThrows(IllegalArgumentException.class, () -> config.sttyCommand("/dev/../system"));
    }

    private static void assertCode(org.junit.function.ThrowingRunnable call) {
        SerialError e = assertThrows(SerialError.class, call);
        assertEquals(SerialError.INVALID_ARGUMENT, e.code);
    }
}

package com.eroxii.tty_serial;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

public class PortPathsTest {

    private static final List<String> DEFAULT = Arrays.asList("ttyS", "ttyUSB", "ttyACM");

    @Rule
    public TemporaryFolder dir = new TemporaryFolder();

    @Test
    public void matchesOnlyAllowedPrefixesAndNumbers() {
        assertTrue(PortPaths.matches("/dev/ttyS1", DEFAULT));
        assertTrue(PortPaths.matches("/dev/ttyUSB0", DEFAULT));
        assertTrue(PortPaths.matches("/dev/ttyACM123", DEFAULT));

        assertFalse(PortPaths.matches("/dev/ttyS", DEFAULT));
        assertFalse(PortPaths.matches("/dev/ttyS1234", DEFAULT));
        assertFalse(PortPaths.matches("/dev/ttySAC0", DEFAULT));
        assertFalse(PortPaths.matches("/dev/ttyS1 ", DEFAULT));
        assertFalse(PortPaths.matches("/dev/ttyS1;reboot", DEFAULT));
        assertFalse(PortPaths.matches("/dev/../dev/ttyS1", DEFAULT));
        assertFalse(PortPaths.matches("/sdcard/ttyS1", DEFAULT));
        assertFalse(PortPaths.matches("ttyS1", DEFAULT));
        assertFalse(PortPaths.matches(null, DEFAULT));
        assertTrue(PortPaths.matches("/dev/ttySAC0", Collections.singletonList("ttySAC")));
    }

    @Test
    public void checksPrefixes() throws SerialError {
        PortPaths.checkPrefixes(DEFAULT);
        assertInvalid(Collections.<String>emptyList());
        assertInvalid(Collections.singletonList("ttyS.*"));
        assertInvalid(Collections.singletonList("sda"));
        assertInvalid(Collections.singletonList("tty"));
        assertInvalid(Collections.singletonList("ttyABCDEFGHI"));
        assertInvalid(Collections.<String>singletonList(null));
        assertInvalid(Arrays.asList("ttyA", "ttyB", "ttyC", "ttyD", "ttyE", "ttyF", "ttyG", "ttyH", "ttyI"));
    }

    @Test
    public void checkReportsShapeThenExistence() {
        assertEquals(SerialError.INVALID_ARGUMENT,
                assertThrows(SerialError.class, () -> PortPaths.check("/dev/sda", DEFAULT)).code);
        assertEquals(SerialError.NOT_FOUND,
                assertThrows(SerialError.class, () -> PortPaths.check("/dev/ttyS999", DEFAULT)).code);
    }

    @Test
    public void listSortsNaturallyAndSkipsOtherNodes() throws IOException {
        for (String name : new String[]{"ttyS10", "ttyS2", "ttyUSB0", "ttyS0", "sda", "ttySAC0", "tty"}) {
            dir.newFile(name);
        }
        assertEquals(Arrays.asList("/dev/ttyS0", "/dev/ttyS2", "/dev/ttyS10", "/dev/ttyUSB0"),
                PortPaths.list(dir.getRoot(), DEFAULT));
    }

    @Test
    public void listIsCapped() throws IOException {
        List<String> expected = new ArrayList<>();
        for (int i = 0; i < 40; i++) {
            dir.newFile("ttyS" + i);
            if (i < PortPaths.MAX_LISTED_PORTS) expected.add("/dev/ttyS" + i);
        }
        assertEquals(expected, PortPaths.list(dir.getRoot(), DEFAULT));
    }

    @Test
    public void listOfAMissingDirectoryIsEmpty() {
        assertTrue(PortPaths.list(new File(dir.getRoot(), "missing"), DEFAULT).isEmpty());
    }

    private static void assertInvalid(List<String> prefixes) {
        SerialError e = assertThrows(SerialError.class, () -> PortPaths.checkPrefixes(prefixes));
        assertEquals(SerialError.INVALID_ARGUMENT, e.code);
    }
}

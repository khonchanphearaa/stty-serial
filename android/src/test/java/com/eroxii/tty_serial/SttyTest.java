package com.eroxii.tty_serial;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import org.junit.Test;

/** The fallback order, without a device: a fake shell decides which commands succeed. */
public class SttyTest {

    private static final String LINE =
            "stty -F /dev/ttyS1 9600 cs8 -parenb -cstopb raw -echo -crtscts -ixon -ixoff clocal cread";

    /** Records every command; succeeds only for the ones listed. */
    private static final class FakeShell implements Shell.Runner {
        final List<String> commands = new ArrayList<>();
        final Set<String> working = new HashSet<>();

        @Override
        public Shell.Result run(String... command) {
            String text = String.join(" ", command);
            commands.add(text);
            return working.contains(text)
                    ? new Shell.Result(0, "", null)
                    : new Shell.Result(127, "not found", null);
        }
    }

    private static SerialConfig config() throws SerialError {
        return SerialConfig.of(9600, 8, "none", 1);
    }

    @Test
    public void triesEveryToolWithoutRootBeforeSu() throws SerialError {
        FakeShell shell = new FakeShell();
        SerialError e = assertThrows(SerialError.class,
                () -> new Stty(shell).configure("/dev/ttyS1", config()));
        assertEquals(SerialError.CONFIG_FAILED, e.code);
        assertEquals(Arrays.asList(
                "sh -c busybox " + LINE,
                "sh -c toybox " + LINE,
                "sh -c " + LINE,
                "su -c busybox " + LINE,
                "su -c toybox " + LINE,
                "su -c " + LINE), shell.commands);
        assertEquals("stty failed for /dev/ttyS1 (sh busybox: exit 127: not found; "
                + "sh toybox: exit 127: not found; sh system: exit 127: not found; "
                + "su busybox: exit 127: not found; su toybox: exit 127: not found; "
                + "su system: exit 127: not found)", e.getMessage());
    }

    @Test
    public void stopsAtTheFirstThatWorks() throws SerialError {
        FakeShell shell = new FakeShell();
        shell.working.add("sh -c toybox " + LINE);
        Stty.Attempt attempt = new Stty(shell).configure("/dev/ttyS1", config());
        assertEquals("toybox", attempt.tool);
        assertFalse(attempt.root);
        assertEquals(2, shell.commands.size());
    }

    @Test
    public void remembersWhatWorkedForLaterOpens() throws SerialError {
        FakeShell shell = new FakeShell();
        shell.working.add("su -c " + LINE);
        Stty stty = new Stty(shell);
        Stty.Attempt first = stty.configure("/dev/ttyS1", config());
        assertTrue(first.root);
        assertEquals(6, shell.commands.size());

        shell.commands.clear();
        stty.configure("/dev/ttyS1", config());
        assertEquals(Arrays.asList("su -c " + LINE), shell.commands);
        assertEquals("su system", stty.order().get(0).toString());
        assertEquals(6, stty.order().size());
    }

    @Test
    public void fallsBackWhenTheRememberedOneStopsWorking() throws SerialError {
        FakeShell shell = new FakeShell();
        shell.working.add("sh -c toybox " + LINE);
        Stty stty = new Stty(shell);
        stty.configure("/dev/ttyS1", config());
        shell.working.clear();
        shell.working.add("su -c busybox " + LINE);
        shell.commands.clear();
        stty.configure("/dev/ttyS1", config());
        assertEquals(Arrays.asList(
                "sh -c toybox " + LINE,
                "sh -c busybox " + LINE,
                "sh -c " + LINE,
                "su -c busybox " + LINE), shell.commands);
    }

    @Test
    public void keepsLongErrorsShort() {
        Shell.Runner chatty = new Shell.Runner() {
            @Override
            public Shell.Result run(String... command) {
                return new Shell.Result(1, new String(new char[1000]).replace('\0', 'x'), null);
            }
        };
        SerialError e = assertThrows(SerialError.class,
                () -> new Stty(chatty).configure("/dev/ttyS1", config()));
        assertTrue(e.getMessage().length() < 6 * 230);
    }
}

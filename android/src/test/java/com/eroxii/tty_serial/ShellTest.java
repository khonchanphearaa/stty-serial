package com.eroxii.tty_serial;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** Runs on the build machine's /bin/sh, which behaves like Android's for these commands. */
public class ShellTest {

    @Test
    public void successAndOutput() {
        Shell.Result result = Shell.run("sh", "-c", "echo hello; echo world");
        assertTrue(result.succeeded());
        assertNull(result.error());
        assertEquals("hello world", result.output);
    }

    @Test
    public void exitCodeAndErrorOutputAreReported() {
        Shell.Result result = Shell.run("sh", "-c", "echo bad >&2; exit 3");
        assertFalse(result.succeeded());
        assertEquals(3, result.exitCode);
        assertEquals("exit 3: bad", result.error());
    }

    @Test
    public void aMissingProgramFailsWithoutThrowing() {
        Shell.Result result = Shell.run("/no/such/program");
        assertFalse(result.succeeded());
        assertNotNull(result.failure);
    }
}

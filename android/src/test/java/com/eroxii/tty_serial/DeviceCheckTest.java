package com.eroxii.tty_serial;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

/** The report is built from a fake root folder and a fake shell: no device needed. */
public class DeviceCheckTest {

    private static final List<String> PREFIXES = Arrays.asList("ttyS", "ttyUSB");

    @Rule
    public TemporaryFolder root = new TemporaryFolder();

    /** Answers each probe script from a table; anything else fails. */
    private static final class FakeShell implements Shell.Runner {
        final List<String> commands = new ArrayList<>();
        final Map<String, Shell.Result> answers = new HashMap<>();

        @Override
        public Shell.Result run(String... command) {
            commands.add(String.join(" ", command));
            Shell.Result answer = answers.get(command[command.length - 1]);
            return answer != null ? answer : new Shell.Result(1, "", null);
        }

        void succeed(String script, String output) {
            answers.put(script, new Shell.Result(0, output, null));
        }
    }

    private DeviceCheck check(FakeShell shell) {
        return new DeviceCheck(root.getRoot(), shell,
                new DeviceCheck.BuildInfo(25, "7.1.2", "K518", Arrays.asList("armeabi-v7a", "armeabi")));
    }

    @Test
    public void reportsEverything() throws IOException {
        file("dev/ttyS1", "");
        File locked = file("dev/ttyS3", "");
        assertTrue(locked.setReadable(false) && locked.setWritable(false));
        file("dev/sda", "");
        file("system/xbin/su", "");
        file("sys/fs/selinux/enforce", "1\n");
        file("proc/147/cmdline", "/system/bin/eGTouchD\0/data/eGTouchA.ini\0");
        file("proc/200/cmdline", "/system/bin/sh\0");
        FakeShell shell = new FakeShell();
        shell.succeed(DeviceCheck.PROBE_TOYBOX, "");

        Map<String, Object> report = check(shell).report(PREFIXES);

        assertEquals(25, report.get("sdkInt"));
        assertEquals("7.1.2", report.get("release"));
        assertEquals("K518", report.get("model"));
        assertEquals(Arrays.asList("armeabi-v7a", "armeabi"), report.get("abis"));
        assertEquals(Arrays.asList(port("/dev/ttyS1", true, true), port("/dev/ttyS3", false, false)),
                report.get("ports"));
        assertEquals("toybox", report.get("stty"));
        assertEquals(true, report.get("suFound"));
        assertEquals("enforcing", report.get("selinux"));
        Map<String, Object> scanner = new HashMap<>();
        scanner.put("program", "/system/bin/eGTouchD");
        scanner.put("pids", Collections.singletonList(147));
        assertEquals(Collections.singletonList(scanner), report.get("scanners"));
    }

    @Test
    public void anEmptyDeviceReportsNothingAndUnknown() {
        Map<String, Object> report = check(new FakeShell()).report(PREFIXES);
        assertEquals(Collections.emptyList(), report.get("ports"));
        assertNull(report.get("stty"));
        assertTrue(report.containsKey("stty"));
        assertEquals(false, report.get("suFound"));
        assertEquals("unknown", report.get("selinux"));
        assertEquals(Collections.emptyList(), report.get("scanners"));
    }

    @Test
    public void sttyFollowsTheOpenOrderAndSelinuxFallsBackToGetenforce() throws IOException {
        FakeShell shell = new FakeShell();
        shell.succeed(DeviceCheck.PROBE_BUSYBOX, "");
        shell.succeed(DeviceCheck.PROBE_TOYBOX, "");
        shell.succeed(DeviceCheck.PROBE_SELINUX, "Permissive");
        Map<String, Object> report = check(shell).report(PREFIXES);
        assertEquals("busybox", report.get("stty"));
        assertEquals("permissive", report.get("selinux"));

        file("sys/fs/selinux/enforce", "0");
        assertEquals("permissive", check(new FakeShell()).report(PREFIXES).get("selinux"));
    }

    @Test
    public void neverRunsSuOrStty() {
        FakeShell shell = new FakeShell();
        check(shell).report(PREFIXES);
        assertFalse(shell.commands.isEmpty());
        for (String command : shell.commands) {
            assertTrue(command, command.startsWith("sh -c "));
            assertFalse(command, command.contains("stty -F"));
        }
    }

    private File file(String path, String content) throws IOException {
        File file = new File(root.getRoot(), path);
        assertTrue(file.getParentFile().isDirectory() || file.getParentFile().mkdirs());
        try (FileOutputStream out = new FileOutputStream(file)) {
            out.write(content.getBytes(StandardCharsets.UTF_8));
        }
        return file;
    }

    private static Map<String, Object> port(String path, boolean readable, boolean writable) {
        Map<String, Object> port = new HashMap<>();
        port.put("path", path);
        port.put("exists", true);
        port.put("readable", readable);
        port.put("writable", writable);
        return port;
    }
}

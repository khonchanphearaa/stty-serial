package com.eroxii.tty_serial;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.MethodCall;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

public class ProcessStopperTest {

    @Rule
    public TemporaryFolder proc = new TemporaryFolder();

    @Test
    public void findsProcessesByProgramOnly() throws IOException {
        cmdline("147", "/system/bin/eGTouchD\0/data/eGTouchA.ini\0");
        cmdline("200", "/system/bin/eGTouchDx\0");
        cmdline("201", "sh\0/system/bin/eGTouchD\0");
        cmdline("self", "/system/bin/eGTouchD\0");
        assertEquals(Collections.singletonList("147"),
                ProcessStopper.running(proc.getRoot(), "/system/bin/eGTouchD"));
    }

    @Test
    public void programMustBeASystemBinary() throws SerialError {
        assertEquals("/system/bin/eGTouchD", Arguments.program(call("/system/bin/eGTouchD")));
        assertEquals("/system/xbin/a.b-c_d", Arguments.program(call("/system/xbin/a.b-c_d")));
        for (String bad : new String[]{"eGTouchD", "/data/local/tmp/x", "/system/bin/", "/system/bin/..",
                "/system/bin/-x", "/system/bin/a;reboot", "/system/bin/a b", "/system/bin/sub/x"}) {
            SerialError e = assertThrows(SerialError.class, () -> Arguments.program(call(bad)));
            assertEquals(SerialError.INVALID_ARGUMENT, e.code);
        }
    }

    private void cmdline(String pid, String content) throws IOException {
        File dir = proc.newFolder(pid);
        try (FileOutputStream out = new FileOutputStream(new File(dir, "cmdline"))) {
            out.write(content.getBytes(StandardCharsets.UTF_8));
        }
    }

    private static MethodCall call(String program) {
        Map<String, Object> args = new HashMap<>();
        args.put("program", program);
        return new MethodCall("stopProcess", args);
    }
}

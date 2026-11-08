package com.eroxii.tty_serial;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * Sets a port's line settings with the first stty that works on this ROM.
 * Android 4.4 kiosk ROMs usually ship busybox; Android 7+ ROMs may have only
 * toybox, or a plain stty. All three are tried without root first, and only
 * then through su, which may show a root prompt.
 *
 * The attempt that worked is remembered for the life of the process, so
 * later opens try it first.
 */
final class Stty {

    /** Longest error kept per attempt, so six failures stay readable. */
    private static final int MAX_ERROR_CHARS = 200;

    /** One way to run stty: which binary, and whether through su. */
    static final class Attempt {
        /** "busybox", "toybox" or "system" (the stty on PATH). */
        final String tool;
        final boolean root;
        private final String prefix;

        private Attempt(String tool, String prefix, boolean root) {
            this.tool = tool;
            this.prefix = prefix;
            this.root = root;
        }

        /** [sttyLine] comes from SerialConfig.sttyCommand, built from checked values only. */
        String[] command(String sttyLine) {
            return new String[]{root ? "su" : "sh", "-c", prefix + sttyLine};
        }

        @Override
        public String toString() {
            return (root ? "su " : "sh ") + tool;
        }
    }

    /** The default order: every tool without root, then every tool with su. */
    static final List<Attempt> ORDER = Collections.unmodifiableList(Arrays.asList(
            new Attempt("busybox", "busybox ", false),
            new Attempt("toybox", "toybox ", false),
            new Attempt("system", "", false),
            new Attempt("busybox", "busybox ", true),
            new Attempt("toybox", "toybox ", true),
            new Attempt("system", "", true)));

    private static final Stty SHARED = new Stty(Shell.SYSTEM);

    private final Shell.Runner shell;
    /** Ports open on several threads; the last success wins, which is fine. */
    private volatile Attempt worked;

    Stty(Shell.Runner shell) {
        this.shell = shell;
    }

    static Stty shared() {
        return SHARED;
    }

    /** The order the next configure uses: the attempt that last worked first. */
    List<Attempt> order() {
        Attempt first = worked;
        if (first == null) return ORDER;
        List<Attempt> order = new ArrayList<>(ORDER.size());
        order.add(first);
        for (Attempt attempt : ORDER) {
            if (attempt != first) order.add(attempt);
        }
        return order;
    }

    /**
     * Returns the attempt that worked. Throws configFailed listing every
     * attempt and its error when none did.
     */
    Attempt configure(String path, SerialConfig config) throws SerialError {
        String line = config.sttyCommand(path);
        List<String> failures = new ArrayList<>();
        for (Attempt attempt : order()) {
            Shell.Result result = shell.run(attempt.command(line));
            if (result.succeeded()) {
                worked = attempt;
                return attempt;
            }
            failures.add(attempt + ": " + shorten(result.error()));
        }
        StringBuilder message = new StringBuilder("stty failed for ").append(path).append(" (");
        for (int i = 0; i < failures.size(); i++) {
            if (i > 0) message.append("; ");
            message.append(failures.get(i));
        }
        throw new SerialError(SerialError.CONFIG_FAILED, message.append(')').toString());
    }

    private static String shorten(String error) {
        if (error == null) return "failed";
        return error.length() > MAX_ERROR_CHARS ? error.substring(0, MAX_ERROR_CHARS) + "..." : error;
    }
}

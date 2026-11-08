package com.eroxii.tty_serial;


import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;


/**
 * Runs one command and gives up after a timeout. A stalled su (for example
 * waiting on a root prompt) must not block a port's thread, and every later
 * command on it, forever. Ported from the vending app's SerialPort.execute.
 */
final class Shell {

    /** stty takes well under a second; su may wait on a root prompt. */
    static final long TIMEOUT_MS = 10000;
    private static final long POLL_MS = 20;
    private static final long OUTPUT_WAIT_MS = 500;
    /** Enough for an error line; a chatty command cannot fill memory. */
    private static final int MAX_OUTPUT_CHARS = 2048;

    private Shell() {
    }

    /** Runs one command. Code that shells out takes one, so tests can pass a fake. */
    interface Runner {
        Result run(String... command);
    }

    /** The real shell. */
    static final Runner SYSTEM = new Runner() {
        @Override
        public Result run(String... command) {
            return Shell.run(command);
        }
    };

    static final class Result {
        final int exitCode;
        final String output;
        /** Set when the command did not run to the end (could not start, timed out, interrupted). */
        final String failure;

        Result(int exitCode, String output, String failure) {
            this.exitCode = exitCode;
            this.output = output;
            this.failure = failure;
        }

        boolean succeeded() {
            return failure == null && exitCode == 0;
        }

        /** A short reason for logs and error messages, or null on success. */
        String error() {
            if (failure != null) return failure;
            return exitCode == 0 ? null : "exit " + exitCode + ": " + output;
        }
    }

    /**
     * Polls exitValue() because Process.waitFor(timeout) needs API 26, and
     * this package supports API 19.
     */
    static Result run(String... command) {
        final Process process;
        try {
            process = new ProcessBuilder(command).redirectErrorStream(true).start();
        } catch (IOException e) {
            return new Result(-1, "", e.toString());
        }
        // Read on a daemon thread: a killed su can leave a child holding the
        // pipe open, so this read may never end.
        final StringBuffer output = new StringBuffer();
        Thread reader = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    BufferedReader lines = new BufferedReader(new InputStreamReader(process.getInputStream()));
                    String line;
                    while ((line = lines.readLine()) != null) {
                        if (output.length() < MAX_OUTPUT_CHARS) {
                            output.append(line).append(' ');
                        }
                    }
                } catch (IOException ignored) {
                    // The process ended or was destroyed; what we have is enough.
                }
            }
        }, "tty_serial-shell-output");
        reader.setDaemon(true);
        reader.start();

        long deadline = System.nanoTime() + TIMEOUT_MS * 1000000L;
        try {
            while (true) {
                try {
                    int exitCode = process.exitValue();
                    reader.join(OUTPUT_WAIT_MS);
                    return new Result(exitCode, trimmed(output), null);
                } catch (IllegalThreadStateException running) {
                    if (System.nanoTime() >= deadline) {
                        process.destroy();
                        return new Result(-1, trimmed(output), "timed out after " + TIMEOUT_MS + " ms");
                    }
                }
                Thread.sleep(POLL_MS);
            }
        } catch (InterruptedException e) {
            process.destroy();
            Thread.currentThread().interrupt();
            return new Result(-1, trimmed(output), "interrupted");
        }
    }

    private static String trimmed(StringBuffer output) {
        String text = output.toString().trim();
        return text.length() > MAX_OUTPUT_CHARS ? text.substring(0, MAX_OUTPUT_CHARS) : text;
    }
}

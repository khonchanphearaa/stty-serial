package com.eroxii.tty_serial;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Line settings for one port, checked against fixed lists. Only values from
 * those lists can reach the stty command line, so Dart can never inject shell
 * text through them.
 */
final class SerialConfig {

    private static final int[] BAUD_RATES = {1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200};

    /** Same shape as PortPaths allows; checked again here because this builds a shell command. */
    private static final Pattern SAFE_PATH = Pattern.compile("^/dev/tty[A-Za-z]{1,8}[0-9]{1,3}$");

    enum Parity {
        NONE("none", "-parenb"),
        EVEN("even", "parenb", "-parodd"),
        ODD("odd", "parenb", "parodd");

        final String wireName;
        final List<String> sttyArgs;

        Parity(String wireName, String... sttyArgs) {
            this.wireName = wireName;
            this.sttyArgs = Collections.unmodifiableList(Arrays.asList(sttyArgs));
        }

        static Parity fromWireName(String name) throws SerialError {
            for (Parity p : values()) {
                if (p.wireName.equals(name)) return p;
            }
            throw SerialError.invalidArgument("parity must be none, even or odd");
        }
    }

    final int baudRate;
    final int dataBits;
    final Parity parity;
    final int stopBits;

    private SerialConfig(int baudRate, int dataBits, Parity parity, int stopBits) {
        this.baudRate = baudRate;
        this.dataBits = dataBits;
        this.parity = parity;
        this.stopBits = stopBits;
    }

    static SerialConfig of(int baudRate, int dataBits, String parity, int stopBits) throws SerialError {
        if (Arrays.binarySearch(BAUD_RATES, baudRate) < 0) {
            throw SerialError.invalidArgument("baudRate " + baudRate + " is not supported");
        }
        if (dataBits != 7 && dataBits != 8) {
            throw SerialError.invalidArgument("dataBits must be 7 or 8");
        }
        if (stopBits != 1 && stopBits != 2) {
            throw SerialError.invalidArgument("stopBits must be 1 or 2");
        }
        return new SerialConfig(baudRate, dataBits, Parity.fromWireName(parity), stopBits);
    }

    /**
     * Arguments after "stty": raw bytes, no echo, no flow control. The order
     * and flags are the ones verified on the dg3188 with the TCN board.
     */
    List<String> sttyArgs(String path) {
        if (!SAFE_PATH.matcher(path).matches()) {
            throw new IllegalArgumentException("Not a checked port path");
        }
        List<String> args = new ArrayList<>();
        args.add("-F");
        args.add(path);
        args.add(Integer.toString(baudRate));
        args.add("cs" + dataBits);
        args.addAll(parity.sttyArgs);
        args.add(stopBits == 2 ? "cstopb" : "-cstopb");
        args.addAll(Arrays.asList("raw", "-echo", "-crtscts", "-ixon", "-ixoff", "clocal", "cread"));
        return args;
    }

    /**
     * "stty -F ..." for sh -c / su -c; Stty puts the binary in front
     * ("busybox ", "toybox " or nothing). Safe because every part is checked
     * above.
     */
    String sttyCommand(String path) {
        StringBuilder command = new StringBuilder("stty");
        for (String arg : sttyArgs(path)) {
            command.append(' ').append(arg);
        }
        return command.toString();
    }

    @Override
    public String toString() {
        return baudRate + " " + dataBits + parity.wireName.substring(0, 1).toUpperCase() + stopBits;
    }
}

package com.eroxii.tty_serial;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Which device nodes the app may open: /dev/ followed by one of the allowed
 * name prefixes (for example ttyS) and a 1-3 digit number. Nothing else, so
 * Dart can never point the plugin at a disk, /proc, or a shell string.
 */
final class PortPaths {

    static final int MAX_PREFIXES = 8;
    static final int MAX_LISTED_PORTS = 32;

    private static final String DEV = "/dev/";
    private static final Pattern PREFIX = Pattern.compile("^tty[A-Za-z]{1,8}$");
    private static final Pattern NUMBER = Pattern.compile("^[0-9]{1,3}$");

    private PortPaths() {
    }

    static void checkPrefixes(List<String> prefixes) throws SerialError {
        if (prefixes.isEmpty() || prefixes.size() > MAX_PREFIXES) {
            throw SerialError.invalidArgument("prefixes must have 1-" + MAX_PREFIXES + " items");
        }
        for (String prefix : prefixes) {
            if (prefix == null || !PREFIX.matcher(prefix).matches()) {
                throw SerialError.invalidArgument("prefix must look like ttyS: " + prefix);
            }
        }
    }

    /** True when [path] is /dev/ + one of [prefixes] + a number. Prefixes are already checked. */
    static boolean matches(String path, List<String> prefixes) {
        if (path == null || !path.startsWith(DEV)) return false;
        String name = path.substring(DEV.length());
        for (String prefix : prefixes) {
            // Compare the prefix as plain text, never as a regex built from input.
            if (name.startsWith(prefix) && NUMBER.matcher(name.substring(prefix.length())).matches()) {
                return true;
            }
        }
        return false;
    }

    /** Fails with a code Dart can show: bad shape, missing node, or no read/write access. */
    static File check(String path, List<String> prefixes) throws SerialError {
        if (!matches(path, prefixes)) {
            throw SerialError.invalidArgument("Not an allowed serial port: " + path);
        }
        File device = new File(path);
        if (!device.exists()) {
            throw new SerialError(SerialError.NOT_FOUND, path + " does not exist");
        }
        if (!device.canRead() || !device.canWrite()) {
            throw new SerialError(SerialError.PERMISSION_DENIED, "No read/write permission on " + path);
        }
        return device;
    }

    /** Matching nodes in [dir] that this app can read and write, in natural order (ttyS2 before ttyS10). */
    static List<String> list(File dir, List<String> prefixes) {
        List<String> ports = new ArrayList<>();
        for (String name : matchingNames(dir, prefixes)) {
            File node = new File(dir, name);
            if (node.canRead() && node.canWrite()) {
                ports.add(DEV + name);
                if (ports.size() == MAX_LISTED_PORTS) break;
            }
        }
        return ports;
    }

    /** Matching nodes in [dir] whatever their permissions, in natural order; at most MAX_LISTED_PORTS. */
    static List<String> matching(File dir, List<String> prefixes) {
        List<String> names = matchingNames(dir, prefixes);
        List<String> ports = new ArrayList<>();
        for (int i = 0; i < names.size() && i < MAX_LISTED_PORTS; i++) {
            ports.add(DEV + names.get(i));
        }
        return ports;
    }

    private static List<String> matchingNames(File dir, List<String> prefixes) {
        List<String> matching = new ArrayList<>();
        String[] names = dir.list();
        if (names == null) return matching;
        for (String name : names) {
            if (matches(DEV + name, prefixes)) matching.add(name);
        }
        Collections.sort(matching, NATURAL);
        return matching;
    }

    /** Letters first, then the number: every name here ends in 1-3 digits. */
    private static final Comparator<String> NATURAL = new Comparator<String>() {
        @Override
        public int compare(String a, String b) {
            int byName = stem(a).compareTo(stem(b));
            if (byName != 0) return byName;
            return Integer.compare(number(a), number(b));
        }
    };

    private static int digitsStart(String name) {
        int i = name.length();
        while (i > 0 && Character.isDigit(name.charAt(i - 1))) i--;
        return i;
    }

    private static String stem(String name) {
        return name.substring(0, digitsStart(name));
    }

    private static int number(String name) {
        return Integer.parseInt(name.substring(digitsStart(name)));
    }
}

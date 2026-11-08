package com.eroxii.tty_serial;

import java.util.HashSet;
import java.util.Set;

/**
 * Device paths open in this app. One owner per port: two writers on one
 * wire garble each other's bytes, and a packet meant for one device could
 * make another one act (a vending board command reaching a bill acceptor).
 *
 * Shared by every Flutter engine in the process, so a second engine cannot
 * open a port the first one holds.
 */
final class PortRegistry {

    private static final PortRegistry SHARED = new PortRegistry();

    private final Set<String> openPaths = new HashSet<>();

    static PortRegistry shared() {
        return SHARED;
    }

    synchronized void claim(String path) throws SerialError {
        if (!openPaths.add(path)) {
            throw new SerialError(SerialError.BUSY, path + " is already open in this app");
        }
    }

    synchronized void release(String path) {
        openPaths.remove(path);
    }
}

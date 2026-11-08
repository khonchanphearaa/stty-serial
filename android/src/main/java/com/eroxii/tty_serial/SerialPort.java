package com.eroxii.tty_serial;

import java.io.Closeable;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;

/**
 * A serial device node opened as a plain file and configured with stty, so
 * no native code is needed. Not thread-safe: PortHandle runs every call on
 * the port's own thread. Ported from the vending app's SerialPort.
 */
final class SerialPort {

    private final String path;
    private final FileInputStream in;
    private final FileOutputStream out;
    private final PortRegistry registry;
    private boolean closed;

    private SerialPort(String path, FileInputStream in, FileOutputStream out, PortRegistry registry) {
        this.path = path;
        this.in = in;
        this.out = out;
        this.registry = registry;
    }

    /** [device] must come from PortPaths.check. Blocks while stty (and maybe su) runs. */
    static SerialPort open(File device, SerialConfig config, PortRegistry registry) throws SerialError {
        String path = device.getPath();
        registry.claim(path);
        FileOutputStream out = null;
        FileInputStream in = null;
        try {
            out = new FileOutputStream(device);
            in = new FileInputStream(device);
        } catch (IOException e) {
            closeQuietly(in);
            closeQuietly(out);
            registry.release(path);
            String code = device.exists() ? SerialError.IO : SerialError.NOT_FOUND;
            throw new SerialError(code, "Could not open " + path + ": " + e.getMessage());
        }
        SerialPort port = new SerialPort(path, in, out, registry);
        try {
            // While our file descriptor is open: when the last one closes,
            // the driver may reset the line settings.
            Stty.shared().configure(path, config);
        } catch (SerialError e) {
            port.close();
            throw e;
        }
        return port;
    }

    String path() {
        return path;
    }

    /** Bytes that can be read without blocking. */
    int available() throws IOException {
        return in.available();
    }

    /** Call only when available() is above 0, or it blocks until a byte arrives. */
    int read(byte[] buffer, int offset, int length) throws IOException {
        return in.read(buffer, offset, length);
    }

    void write(byte[] data) throws IOException {
        out.write(data);
        out.flush();
    }

    /** Safe to call twice. Frees the path for the next open. */
    void close() {
        synchronized (this) {
            if (closed) return;
            closed = true;
        }
        closeQuietly(in);
        closeQuietly(out);
        registry.release(path);
    }

    private static void closeQuietly(Closeable stream) {
        if (stream == null) return;
        try {
            stream.close();
        } catch (IOException ignored) {
            // Nothing useful to do: the port is being given up anyway.
        }
    }
}

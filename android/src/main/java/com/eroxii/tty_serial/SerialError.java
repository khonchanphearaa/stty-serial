package com.eroxii.tty_serial;

/**
 * A failure with a stable code that Dart maps to a SerialException type.
 * Checked, so every native path that can fail has to decide what to report.
 */
final class SerialError extends Exception {

    static final String INVALID_ARGUMENT = "invalidArgument";
    static final String NOT_FOUND = "notFound";
    static final String PERMISSION_DENIED = "permissionDenied";
    static final String BUSY = "busy";
    static final String CONFIG_FAILED = "configFailed";
    static final String CLOSED = "closed";
    static final String IO = "io";

    final String code;

    SerialError(String code, String message) {
        super(message);
        this.code = code;
    }

    static SerialError invalidArgument(String message) {
        return new SerialError(INVALID_ARGUMENT, message);
    }
}

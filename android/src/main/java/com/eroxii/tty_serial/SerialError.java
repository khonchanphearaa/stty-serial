package com.eroxii.tty_serial;



/**  A failure that define serial error with a stable code that Dart map SerialException type */
final class SerialError extends Exception {

    static final String INVALID_ARGUMENT = "invalidArgument";
    static final String NOT_FOUND = "notFound";
    static final String PERMISSION_DENIED = "permissionDenied";
    static final String BUSY = "busy";
    static final String CONFIG_FAILED = "configFailed";
    static final String CLOSED = "closed";
    static final String IO = "io";
    
    final String code;

    SerialError(String code, String msg) {
        super(msg);
        this.code = code;
    }

    static SerialError invalidArgument(String msg) {
        return new SerialError(INVALID_ARGUMENT, msg);
    }
}
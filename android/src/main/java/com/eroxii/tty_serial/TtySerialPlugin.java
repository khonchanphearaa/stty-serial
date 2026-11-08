package com.eroxii.tty_serial;

import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * The tty_serial MethodChannel. Arguments are checked on the main thread;
 * blocking work runs on the port's own thread (or one shared thread for
 * listPorts, stopProcess and checkDevice); every reply goes back on the main thread.
 *
 * [handles] and [nextHandle] are only touched on the main thread, so they
 * need no lock.
 */
public final class TtySerialPlugin implements FlutterPlugin, MethodCallHandler {

    private static final String CHANNEL = "tty_serial";
    private static final File DEV = new File("/dev");

    private final Map<Integer, PortHandle> handles = new HashMap<>();
    private int nextHandle = 1;
    private boolean attached;

    private MethodChannel channel;
    private Handler main;
    private ExecutorService shared;

    /** A blocking job whose value (or SerialError) goes back to Dart. */
    interface Task {
        Object run() throws SerialError;
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        main = new Handler(Looper.getMainLooper());
        shared = PortHandle.newExecutor("shared");
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
        attached = true;
    }

    /** Closes every port this engine opened and stops every thread. */
    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        attached = false;
        channel.setMethodCallHandler(null);
        for (PortHandle handle : handles.values()) {
            handle.close(null);
        }
        handles.clear();
        shared.shutdown();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        try {
            switch (call.method) {
                case "listPorts":
                    listPorts(call, result);
                    break;
                case "open":
                    open(call, result);
                    break;
                case "write":
                    write(call, result);
                    break;
                case "transact":
                    transact(call, result);
                    break;
                case "close":
                    close(call, result);
                    break;
                case "stopProcess":
                    stopProcess(call, result);
                    break;
                case "checkDevice":
                    checkDevice(call, result);
                    break;
                default:
                    result.notImplemented();
            }
        } catch (SerialError e) {
            result.error(e.code, e.getMessage(), null);
        }
    }

    private void listPorts(MethodCall call, Result result) throws SerialError {
        final List<String> prefixes = Arguments.prefixes(call);
        submit(shared, result, new Task() {
            @Override
            public Object run() {
                return new ArrayList<>(PortPaths.list(DEV, prefixes));
            }
        });
    }

    private void open(MethodCall call, final Result result) throws SerialError {
        final String path = Arguments.path(call);
        final List<String> prefixes = Arguments.prefixes(call);
        final SerialConfig config = Arguments.config(call);
        if (!PortPaths.matches(path, prefixes)) {
            throw SerialError.invalidArgument("Not an allowed serial port: " + path);
        }
        // The new port's own thread, so a slow stty or su prompt never
        // delays commands on ports that are already open.
        final ExecutorService executor = PortHandle.newExecutor(path);
        executor.execute(new Runnable() {
            @Override
            public void run() {
                final SerialPort port;
                try {
                    port = SerialPort.open(PortPaths.check(path, prefixes), config, PortRegistry.shared());
                } catch (final SerialError e) {
                    executor.shutdown();
                    postError(result, e.code, e.getMessage());
                    return;
                } catch (final RuntimeException e) {
                    executor.shutdown();
                    postError(result, SerialError.IO, "Open failed: " + e);
                    return;
                }
                main.post(new Runnable() {
                    @Override
                    public void run() {
                        opened(new PortHandle(port, executor), result);
                    }
                });
            }
        });
    }

    /** Main thread. An engine that went away while the port opened must not leak it. */
    private void opened(PortHandle handle, Result result) {
        if (!attached) {
            handle.close(null);
            result.error(SerialError.CLOSED, "The plugin was detached while the port opened", null);
            return;
        }
        int id = nextHandle++;
        handles.put(id, handle);
        result.success(id);
    }

    private void write(MethodCall call, Result result) throws SerialError {
        final PortHandle handle = lookup(call);
        final byte[] data = Arguments.data(call);
        submit(handle.executor(), result, new Task() {
            @Override
            public Object run() throws SerialError {
                handle.write(data);
                return null;
            }
        });
    }

    private void transact(MethodCall call, Result result) throws SerialError {
        final PortHandle handle = lookup(call);
        final byte[] data = Arguments.data(call);
        final int replyLength = Arguments.replyLength(call);
        final int timeoutMs = Arguments.timeoutMs(call);
        submit(handle.executor(), result, new Task() {
            @Override
            public Object run() throws SerialError {
                return handle.transact(data, replyLength, timeoutMs);
            }
        });
    }

    /** Closing an unknown or closed handle succeeds, so Dart can always clean up. */
    private void close(MethodCall call, final Result result) throws SerialError {
        PortHandle handle = handles.remove(Arguments.handle(call));
        if (handle == null) {
            result.success(null);
            return;
        }
        handle.close(new Runnable() {
            @Override
            public void run() {
                postSuccess(result, null);
            }
        });
    }

    /** Root. Only when the app asks; open never calls it. */
    private void stopProcess(MethodCall call, Result result) throws SerialError {
        final String program = Arguments.program(call);
        submit(shared, result, new Task() {
            @Override
            public Object run() {
                return ProcessStopper.stop(program);
            }
        });
    }

    /** No side effects: never opens a port, never writes, never runs su. */
    private void checkDevice(MethodCall call, Result result) throws SerialError {
        final List<String> prefixes = Arguments.prefixes(call);
        submit(shared, result, new Task() {
            @Override
            public Object run() {
                return DeviceCheck.onDevice().report(prefixes);
            }
        });
    }

    private PortHandle lookup(MethodCall call) throws SerialError {
        PortHandle handle = handles.get(Arguments.handle(call));
        if (handle == null) throw new SerialError(SerialError.CLOSED, "The port is not open");
        return handle;
    }

    private void submit(ExecutorService executor, final Result result, final Task task) {
        try {
            executor.execute(new Runnable() {
                @Override
                public void run() {
                    try {
                        postSuccess(result, task.run());
                    } catch (SerialError e) {
                        postError(result, e.code, e.getMessage());
                    } catch (RuntimeException e) {
                        postError(result, SerialError.IO, e.toString());
                    }
                }
            });
        } catch (RejectedExecutionException e) {
            result.error(SerialError.CLOSED, "The port is closing", null);
        }
    }

    private void postSuccess(final Result result, final Object value) {
        main.post(new Runnable() {
            @Override
            public void run() {
                result.success(value);
            }
        });
    }

    private void postError(final Result result, final String code, final String message) {
        main.post(new Runnable() {
            @Override
            public void run() {
                result.error(code, message, null);
            }
        });
    }
}

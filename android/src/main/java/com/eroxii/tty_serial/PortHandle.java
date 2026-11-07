package com.eroxii.tty_serial;


import java.io.IOException;
import java.util.Arrays;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Executor;
import java.util.concurrent.ThreadFactory;

/**
 * @PortHandle
 * One open port and the signle thread that runs every command on it,
 * so command one one port stay in order and a slow port never blocked
 */
final class PortHandle {
    
    private static final int MAX_STALE_BYTES = 256;
    private static final long POLL_MS = 10;
    
    private final SerialPort port;
    private final ExecutorService executor;

    PortHandle(SerialPort port, ExecutorService executor){
        this.port = port;
        this.executor = executor;
    }

    static ExecutorService newExecutor(final String path) {
        return Executors.newSingleThreadExecutor(new ThreadFactory() {
            @Override
            public Thread newThread(Runnable task) {
                Thread thread = new Thread(task, "tty_serial " + path);
                thread.setDaemon(true);
                return thread;
            }
        });
    }
        ExecutorService executor(){
            return  executor;
        }

        /** Runs on the port's thread */
        void write(byte[] data) throws SerialError{
            try {
                port.write(data);
            } catch (Exception e) {
                throw new SerialError(SerialError.IO, "Write failed: " + e.getMessage());
            }
        }


        /**
         * Runs one the port's thread. Drops items input, write [data]
         * then collects up to [replyLength] bytes until the deadline.
         * Polls available instead of blocking in read(), So a silent device can never hang
         * the thread, A short result is not an errorL the caller decides
         */
        byte[] transact(byte[] data, int replyLength, long timeoutMs) throws SerialError{

            try {
                discardStaleInput();
                port.write(data);
                byte[] reply = new byte[replyLength];
                int count=0;
                long deadline = SystemClock.uptimeMillis() + timeoutMs;
                
                while (count < replyLength && SystemClock.uptimeMillis() < deadline) {
                    int available = port.available();
                    if(available<=0){
                        sleep();
                        continue;
                    }
                    int n = port.read(reply, count, Math.min(available, replyLength - count));
                    if(n<0) throw new SerialError(SerialError.IO, "Port closed while reading");
                    count += n;
                }
                return  Arrays.copyOf(reply, count);
            } catch (Exception e) {
                throw new SerialError(SerialError.IO, "Transact failed: " + e.getMessage());
            }
        }


        private static void sleep() throws SerialError{
            try {
                Thread.sleep(POLL_MS);
            } catch (Exception e) {
                Thread.currentThread().interrupt();
                throw new SerialError(SerialError.IO, "Interrupted after writing; the outcome is unknown");
            }
        }


        /** A late relay to an earlier command must not be read as this one's */
        private void discardStaleInput() throws IOException{
            byte[] scratch = new byte[64];
            int disabled = 0;

            while (disabled < MAX_STALE_BYTES) {
                int available = port.available();
                if(available <=0) return;
                int n = port.read(scratch, 0, Math.min(available, scratch.length));
                disabled += n;
            }
        }

        
        /**
         * Close after any command already queued, then stops the thread
         * [then] runs on the port's thread once the port is closed, or not at all when null
         */
        void close(final Runnable then){
            executor.execute(new Runnable() {
                
                @Override 
                public void run(){
                    port.close();
                    if(then != null) then.run();
                }
            });
            executor.shutdown();
        }
        
}

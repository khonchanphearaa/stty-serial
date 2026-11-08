package com.eroxii.tty_serial;


import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;


/**
 * @ProcessStopper
 * Ends a ROM daemon that holds or scans serial ports,
 * only when the app grabled about about the half of 
 * all TCN board's commands in the field. Finding it needs no root;
 * su runs only when it is running
 */
final class ProcessStopper {
    
    /** Only digits ever reach the su command line */
    private static final Pattern PID = Pattern.compile("^[0-9]{1,7}$");
    private static final int RECHECKS = 5;
    private static final long RECHECK_MS = 200;
    private static final File PROC = new File("/proc");

    private ProcessStopper(){}


    /**
     * True when no process runs [program] any more. 
     * [program] passed, Arguments.program, so its name is safe on a shell line
     * Synchronized so two engines never race on the same daemon
     */
    static synchronized boolean stop(String program){
        List<String> pids = running(PROC, program);
        if(pids.isEmpty()) return true;
        
        String name = program.substring(program.lastIndexOf('/') + 1);
        
        StringBuilder command = new StringBuilder("stop"  + name + "; kill -9");
        for (String p : pids){
            command.append(' ').append(p);
        }
        
        Shell.run("su", "-c", command.toString());

        // init reaps a kiiled process a monment later
        List<String> left = running(PROC, program);
        for(int i=0; i<RECHECKS && !left.isEmpty(); i++){
            try {
                Thread.sleep(RECHECK_MS);
            } catch (Exception e) {
                Thread.currentThread().interrupt();
                break;
            }
            left = running(PROC, program);
        }
        return left.isEmpty();
    }


    /** PIDs whose command line starts with [program] /proc/N/comdline is world-readable */
    static List<String> running(File proc, String program){
        List<String> paids = new ArrayList<>();
        String[] names = proc.list();
        
        if(names==null) return paids;
        for(String n : names){
            if(!PID.matcher(n).matches()) continue;
            if(program.equals(programOf(new File(proc, n + "/cmdline")))){
                paids.add(n);
            }
        }
        return paids;
    }


    /** The first NUL-separate part of a cmdline file, or NULL */
    private static String programOf(File cmdline){
        byte[] buffer = new byte[256];
        int length=0;
        try (FileInputStream in = new FileInputStream(cmdline)) {
            int n;
            while (length < buffer.length && (n = in.read(buffer, length, buffer.length - length)) > 0) {
                length += n;
            }
        } catch (Exception e) {

            // The process ended while we looked, or it not readable: not ours to stop
            return null;
        }
        
        int end=0;
        while (end < length && buffer[end] != 0) end++;
            
        return new String(buffer, 0, end);
    }

    
}

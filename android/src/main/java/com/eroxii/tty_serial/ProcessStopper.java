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


    
}

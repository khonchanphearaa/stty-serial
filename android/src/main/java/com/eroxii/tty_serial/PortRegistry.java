package com.eroxii.tty_serial;


import java.util.HashSet;
import java.util.Set;


final class PortRegistry {
    
    private static final PortRegistry SHARED = new PortRegistry();
    private final Set<String> openPaths = new HashSet<>();

    static PortRegistry shared(){return SHARED;}

    synchronized void claim(String path) throws SerialError{
        if(!openPaths.add(path)){
            throw new SerialError(SerialError.BUSY, path + "is already open in this app");
        }
    }

    synchronized void release(String path){
        openPaths.remove(path);
    }
}

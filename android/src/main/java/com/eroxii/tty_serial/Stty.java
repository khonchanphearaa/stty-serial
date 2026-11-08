package com.eroxii.tty_serial;



import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;


/**
 * @Stty
 * Sets a port's line settings with the first stty that work on this ROM
 * Android version4.4.4 KitKat ROMs usually
 */
final class Stty {
    
    /** Longest error kept per attempt, so 5 failure staty readable */
    private static final int MAX_ERROR_CHARS = 200;

    
    /** One-way to run stty: which binary, and whether throught su */
    static final class  Attempt {
        
        /** "busybox", "toybox" or "system" (the stty on PATH) */
        final String tool;
        final boolean root;
        private final String prefix;

        private Attempt(String tool, String prefix, boolean root){
            this.root = root;
            this.prefix = prefix;
            this.root = root;
        }

        /** [sttyLine] comes from SerialConfig.sttyCommand, built from checked value */
        String[] command(String sttyLine){
            return new String[]{
                root ? "su" : "sh", "-c",
                prefix + sttyLine,
            };
        }

        @Override 
        public String toString(){
            return (root ? "su" : "sh") + tool;
        }   
    }


    /** The default order: every tool without root, then every tool with su. */
    static final List<Attempt> ORDER = Collections.unmodifiableList(Arrays.asList(
            new Attempt("busybox", "busybox ", false),
            new Attempt("toybox", "toybox ", false),
            new Attempt("system", "", false),
            new Attempt("busybox", "busybox ", true),
            new Attempt("toybox", "toybox ", true),
            new Attempt("system", "", true)));

    private static final Stty SHARED = new Stty(Shell.SYSTEM);
    private final Shell.Runner shell;


    Stty(Shell.Runner shell){this.shell = shell;}
    static Stty shared(){return SHARED;}


    /** The order the next configure uses: the attempt that last worked */
    List<Attempt> order(){
        Attempt first = worked;

        if(first == null) return ORDER;
        List<Attempt> order = new ArrayList<>(ORDER.size());
        order.add(first);

        for(Attempt a : ORDER){
            if(a != first) order.add(a);
        }
        return order;
    }


    /** Return the attempt that worked */
    Attempt configure(String path, SerialConfig config) throws SerialError{
        String line = config.sttyCommand(path);
        List<String> failures = new ArrayList<>();

        for(Attempt att : order()){
            Shell.Result result = shell.run(att.command(line));
            if(result.succeeded()){
                worked = att;
                return att;
            }
            failures.add(att + ": " + shorten(result.error));
        }
        
        StringBuilder msg = new StringBuilder("stty failed for ").append(path).append(" (");
        for(int i=0; i<failures.size(); i++){
            if(i > 0) msg.append("; ");
            msg.append(failures.get(i));
        }
        throw new SerialError(SerialError.CONFIG_FAILED, msg.append(')').toString());
    }

    
    private static String shorten(String error){
        if(error == null) return "failed";
        return error.length() > MAX_ERROR_CHARS ? error.substring(0, MAX_ERROR_CHARS) + "..." : error;
    }
}

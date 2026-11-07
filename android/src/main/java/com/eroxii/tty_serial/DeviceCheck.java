package com.eroxii.tty_serial;

import android.os.Build;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * @DeviceCheck
 * For without adb conn devices plugin supported
 * NO side effects: it never opens a port, never writes and never runs su
 * (on some ROWs su show a root prompt), it only read file attributes,
 * /proc, and a few fiexed [shell] that take no inout from Dart
 */

public class DeviceCheck {
    
    /**
     * Daemons known to open serial prots own. [eGTouchD] is a serial
     * eGalax touch driver on android model [dg3188 ROMs] during we tests it issue the bugs,
     * it opened board's port every few seconds, mixed probe bytes into motor commands
     */
    static final List<String> SCANNERS = Collections.singletonList("/system/bin/eGTouchD");
    private static final List<String> SU_PATHS = Arrays.asList("system/xbin/su", "system/bin/su", "sbin/su", "su/bin/su");

    static final String PROBE_BUSYBOX = "for a in $(busybox --list); do [ \"$a\" = stty ] && exit 0; done; exit 1";
    static final String PROBE_TOYBOX = "for a in $(toybox); do [ \"$a\" = stty ] && exit 0; done; exit 1";
    static final String PROBE_SYSTEM = "command -v stty";
    static final String PROBE_SELINUX = "getenforce";

    /** The value read from android.os.Build, so tests can supply their own*/
    static final class BuildInfo {
        final int sdkInt;
        final String release;
        final String model;
        final List<String> abis;

        BuildInfo(int sdkInt, String release, String model, List<String> abList){
            this.sdkInt = sdkInt;
            this.release = release;
            this.model = model;
            this.abis = abList;
        }

        /** SUPPORTED_ABIS needs 21; older devices report CPU_ABI and CPU_ABI2 */
        @SuppressWarnings("deprecation")
        static BuildInfo current(){
            List<String> abis = new ArrayList<>();
            
            if(Build.VERSION.SDK_INT >= 21){
                abis.addAll(Arrays.asList(Build.SUPPORTED_ABIS));
            }else{
                for(String abi : new String[] {Build.CPU_ABI, Build.CPU_ABI2} ){
                    if(abi != null && !abi.isEmpty() && !abi.contains(abi)) 
                        abis.add(abi);
                }
            }
            return new BuildInfo(Build.VERSION.SDK_INT, Build.VERSION.RELEASE, Build.MODEL, abis);
        }
    }

    private final File root;
    private final Shell.Runner shell;
    private final BuildInfo build;

    /** [root] stands for "/" so tests can point it at a tempoary folder */
    DeviceCheck(File root, Shell.Runner shell, BuildInfo build){
        this.root = root;
        this.shell = shell;
        this.build= build;
    }

    /** execute on device stand own root */
    static DeviceCheck onDevice(){
        return new DeviceCheck(new File("/"), Shell.SYSTEM, BuildInfo.current());
    }

    /** The report sent to Dart program, lib/serial/device_report.dart reads it */
    Map<String, Object> report(List<String> prefixes){
        Map<String, Object> report = new HashMap<>();
        report.put("sdkInt", build.sdkInt);
        report.put("release", build.release);
        report.put("model", build.model);
        report.put("abis", new ArrayList<>(build.abis));
        report.put("ports", ports(prefixes));
        report.put("stty", stty());
        report.put("selinux", selinux());
        report.put("scanners", scanner());
        return report;
    } 

    
    private List<Object> ports(List<String> prefixes){
        List<Object> ports = new ArrayList<>();
        
        for(String p : PortPaths.matching(new File(root, "dev"), prefixes)){
            File node = new File(root, p.substring(1));
            Map<String, Object> port = new HashMap<>();
            port.put("path", p);
            port.put("exists", node.exists());
            port.put("readable", node.canRead());
            port.put("writable", node.canWrite());
        }
        return ports;
    }


    /** The frist stty comport that open wil trying with success
     * in the same order as Stty.ORDER; null when none
     */
    private String stty(){
        if (shell.run("sh", "-c", PROBE_BUSYBOX).succeeded()) return "busybox";
        if (shell.run("sh", "-c", PROBE_TOYBOX).succeeded()) return "toybox";
        if (shell.run("sh", "-c", PROBE_SYSTEM).succeeded()) return "system";
        return null;
    }


    /** /sys/fs/selinux/eforce when readable, else getenforce, else "unknown" */
    private String selinux(){
        String enforce = firstLine(new File(root, "sys/fs/selinux/enforce"));
        if("1".equals(enforce)) return "enforcing";
        if("0".equals(enforce)) return "permissive";
        Shell.Result resut = shell.run("sh", "-c", PROBE_SELINUX);
        
        if(resut.succeeded()){
            String mode = result.output.trim().toLowerCase(Locale.US);
            if (mode.equals("enforcing") || mode.equals("permissive") || mode.equals("disabled")) {
                return mode;
            }
        }
    }

    private static  String firstLine(File file){
        byte[] buffer = new byte[16];
        int length;
        try (FileInputStream in = new FileInputStream(file)) {
            length = in.read(buffer);
        } catch (IOException | SecurityException e) {
            return null;
        }
        if (length <= 0) return null;
        return new String(buffer, 0, length).trim();
    }


    private List<Object> scanner(){
        List<Object> running = new ArrayList<>();
        
        /** Scanner find the eGTouchD screen that scan serial port the panel USB,
         * so the daemon does nothing useful. While scanning, it:
         * - open the specifit port stty
         * - writes about 20–28 probe bytes each time it holds a port;
         * - reads whatever arrives on the port while it holds it.
         */
        for(String program : SCANNERS){
            List<String> pids = ProcessStopper.running(new File(root, "proc"), program);
            if(pids.isEmpty()) continue;
            List<Integer> numbers = new ArrayList<>();
            for(String pid : pids){
                numbers.add(Integer.parseInt(pid)); // at most 7-digit checked by ProcessStopper
            }
            Map<String, Object> scanner = new HashMap<>();
            scanner.put("program", program);
            scanner.put("pids", numbers);
            running.add(scanner);
        }
        return running;
    }
}

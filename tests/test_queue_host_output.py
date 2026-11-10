"""Run the shipped Host stderr drainer against real JDK child pipes."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = r'''
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.CompletableFuture;

public class HostOutputChecks {
    static String java;
    static String classpath;
    static void require(boolean value, String reason) {
        if (!value) throw new AssertionError(reason);
    }
    static ProcessBuilder builder(String... command) {
        var builder = new ProcessBuilder(command);
        for (String key : new String[]{"JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS"}) builder.environment().remove(key);
        return builder;
    }
    static String line(BufferedReader reader) throws Exception {
        return CompletableFuture.supplyAsync(()->{
            try { return reader.readLine(); } catch(IOException error) { throw new UncheckedIOException(error); }
        }).get(5,TimeUnit.SECONDS);
    }
    static void rejected(Runnable action) {
        try { action.run(); throw new AssertionError("unproved/duplicate stream accepted"); }
        catch (IllegalStateException expected) { }
    }
    static class Witness extends Process {
        final ProcessHandle handle;
        final long pid;
        final InputStream source;
        int reads;
        Witness(ProcessHandle handle, long pid, InputStream source) { this.handle=handle; this.pid=pid; this.source=source; }
        public long pid() { return pid; }
        public ProcessHandle toHandle() { return handle; }
        public InputStream getErrorStream() { reads++; return source; }
        public InputStream getInputStream() { throw new AssertionError("stdout touched"); }
        public OutputStream getOutputStream() { throw new AssertionError("stdin touched"); }
        public int waitFor() { return 0; }
        public int exitValue() { return 0; }
        public void destroy() { throw new AssertionError("child destroyed by drainer"); }
    }
    static void identityAndFailure() throws Exception {
        var p=builder(java,"-cp",classpath,"HostOutputChecks","sleep").start();
        try {
            var bytes=new ByteArrayOutputStream(); var sink=new PrintStream(bytes,true,StandardCharsets.UTF_8);
            var wrongPid=new Witness(p.toHandle(),p.pid()+1,new ByteArrayInputStream(new byte[0]));
            rejected(()->ToolkitHostOutput.start(wrongPid,p.toHandle(),sink));
            require(wrongPid.reads==0,"wrong PID read stderr");
            var unrelated=new Witness(ProcessHandle.current(),ProcessHandle.current().pid(),new ByteArrayInputStream(new byte[0]));
            rejected(()->ToolkitHostOutput.start(unrelated,ProcessHandle.current(),sink));
            require(unrelated.reads==0,"wrong parent read stderr");
            var wrongChild=new Witness(p.toHandle(),p.pid(),new ByteArrayInputStream(new byte[0]));
            rejected(()->ToolkitHostOutput.start(wrongChild,ProcessHandle.current(),sink));
            require(wrongChild.reads==0,"wrong child read stderr");
            var eof=new Witness(p.toHandle(),p.pid(),new ByteArrayInputStream("preserved".getBytes(StandardCharsets.UTF_8)));
            var drain=ToolkitHostOutput.start(eof,p.toHandle(),sink);drain.await(3000);
            rejected(()->ToolkitHostOutput.start(eof,p.toHandle(),sink));
            require(eof.reads==1 && bytes.toString(StandardCharsets.UTF_8).equals("preserved"),"duplicate read or lost EOF output");
            bytes.reset();
            var broken=new Witness(p.toHandle(),p.pid(),new InputStream(){public int read() throws IOException { throw new IOException("terminal-pipe-broken"); }});
            var failed=ToolkitHostOutput.start(broken,p.toHandle(),sink);
            try { failed.await(3000);throw new AssertionError("terminal failure hidden"); }
            catch(IOException expected) { require(expected.getCause()!=null,"failure cause lost"); }
            require(bytes.toString(StandardCharsets.UTF_8).contains("[QUEUE_TEST] FAIL host stderr")
                && bytes.toString(StandardCharsets.UTF_8).contains("terminal-pipe-broken"),"terminal failure not visible in audit output");
            bytes.reset();
            var pipe=new PipedInputStream();var writer=new PipedOutputStream(pipe);
            var waiting=new Witness(p.toHandle(),p.pid(),pipe);
            var pending=ToolkitHostOutput.start(waiting,p.toHandle(),sink);
            try { pending.await(1);throw new AssertionError("missing EOF accepted"); }
            catch(IOException expected) { require(expected.getMessage().contains("EOF"),"timeout reason hidden"); }
            writer.write("late-tail".getBytes(StandardCharsets.UTF_8));writer.close();pending.await(3000);
            require(bytes.toString(StandardCharsets.UTF_8).equals("late-tail"),"await timeout lost later tail");
            System.out.println("PASS identity rejects before read, once-only EOF, bounded wait and visible terminal failure");
        } finally { p.destroyForcibly();p.waitFor(); }
    }
    static void notice(int size) throws Exception {
        String options="-Dprobe="+"x".repeat(size-8);
        var builder=builder(java,"-cp",classpath,"HostOutputChecks","notice-child");builder.environment().put("JDK_JAVA_OPTIONS",options);
        var p=builder.start();
        try {
            Thread.sleep(1000);
            boolean reachedMain=p.getInputStream().available()>0;
            int pending=p.getErrorStream().available();
            var bytes=new ByteArrayOutputStream();var sink=new PrintStream(bytes,true,StandardCharsets.UTF_8);
            var output=ToolkitHostOutput.start(p,p.toHandle(),sink);
            var stdout=new BufferedReader(new InputStreamReader(p.getInputStream(),StandardCharsets.UTF_8));
            require("NOTICE_READY".equals(line(stdout)),"env notice entered stdout");
            p.getOutputStream().write('\n');p.getOutputStream().flush();
            require(p.waitFor(5,TimeUnit.SECONDS),"env notice child stalled with drain");output.await(3000);
            String actual=bytes.toString(StandardCharsets.UTF_8);
            require(p.exitValue()==0 && actual.contains("NOTE: Picked up JDK_JAVA_OPTIONS: "+options)
                && actual.contains("terminal-notice-stderr"),"env notice or terminal JVM stderr lost");
            System.out.println("PASS env notice size="+size+" blockedBeforeMain="+!reachedMain+" pending="+pending+" exit="+p.exitValue());
        } finally { if(p.isAlive()){p.destroyForcibly();p.waitFor();} }
    }
    static byte[] payload() {
        byte[] bytes=new byte[2*1024*1024];for(int i=0;i<bytes.length;i++)bytes[i]=(byte)(i%256);return bytes;
    }
    static void handshake() throws Exception {
        var builder=builder(java,"-cp",classpath,"HostOutputChecks","child");
        String options="-Dprobe="+"x".repeat(707);builder.environment().put("JDK_JAVA_OPTIONS",options);
        var p=builder.start();
        try {
            require(!p.waitFor(300,TimeUnit.MILLISECONDS),"large undrained child unexpectedly exited");
            require(p.getInputStream().available()==0,"stderr entered native stdout handshake");
            var bytes=new ByteArrayOutputStream();var sink=new PrintStream(bytes,true,StandardCharsets.UTF_8);
            var output=ToolkitHostOutput.start(p,p.toHandle(),sink);
            var stdout=new BufferedReader(new InputStreamReader(p.getInputStream(),StandardCharsets.UTF_8));
            require("REAL_READY".equals(line(stdout)),"native stdout readiness changed");
            p.getOutputStream().write("ping\n".getBytes(StandardCharsets.US_ASCII));p.getOutputStream().flush();
            require("ACK:ping".equals(line(stdout)),"native stdin/stdout handshake changed");
            require(p.waitFor(5,TimeUnit.SECONDS),"large stderr child stalled");output.await(3000);
            require(p.exitValue()==7 && line(stdout)==null,"child exit/stdout changed");
            var expected=new ByteArrayOutputStream();
            expected.write(("NOTE: Picked up JDK_JAVA_OPTIONS: "+options+"\n").getBytes(StandardCharsets.UTF_8));
            expected.write(payload());expected.write("terminal-tail\n".getBytes(StandardCharsets.UTF_8));
            require(Arrays.equals(expected.toByteArray(),bytes.toByteArray()),"binary stderr payload or exit tail lost");
            System.out.println("PASS large binary stderr lossless, exit intact, native stdout/stdin handshake isolated");
        } finally { if(p.isAlive()){p.destroyForcibly();p.waitFor();} }
    }
    public static void main(String[] args) throws Exception {
        if(args.length==1 && args[0].equals("sleep")){Thread.sleep(30000);return;}
        if(args.length==1 && args[0].equals("notice-child")){
            System.out.println("NOTICE_READY");System.out.flush();System.in.read();
            System.err.println("terminal-notice-stderr");return;
        }
        if(args.length==1 && args[0].equals("child")){
            System.err.write(payload());System.err.flush();System.out.println("REAL_READY");System.out.flush();
            String command=new BufferedReader(new InputStreamReader(System.in)).readLine();
            System.out.println("ACK:"+command);System.out.flush();System.err.print("terminal-tail\n");System.err.flush();System.exit(7);
        }
        java=args[0];classpath=args[1];identityAndFailure();notice(100);notice(715);handshake();
        require(Thread.getAllStackTraces().keySet().stream().noneMatch(t->t.isAlive()&&t.getName().startsWith("toolkit-owned-host-stderr-")),"stderr thread leaked after EOF/failure");
    }
}
'''


class HostOutputTests(unittest.TestCase):
    def test_actual_helper_drains_owned_child_without_touching_protocol(self):
        configured = os.environ.get('PZ_JDK') or os.environ.get('JAVA_HOME')
        javac = str(Path(configured) / 'bin/javac') if configured else shutil.which('javac')
        java = str(Path(configured) / 'bin/java') if configured else shutil.which('java')
        if not javac or not java:
            self.skipTest('Host output regression needs a JDK')
        environment = {key: value for key, value in os.environ.items()
                       if key not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS')}
        with tempfile.TemporaryDirectory(prefix='queue-host-output-') as directory:
            source = Path(directory) / 'HostOutputChecks.java'
            source.write_text(SOURCE)
            compiled = subprocess.run([javac, '-d', directory, str(source),
                str(ROOT / 'tests/native_queue/support/ToolkitHostOutput.java')],
                env=environment, text=True, capture_output=True, timeout=30)
            self.assertEqual(0, compiled.returncode, compiled.stdout + compiled.stderr)
            result = subprocess.run([java, '-cp', directory, 'HostOutputChecks', java, directory],
                env=environment, text=True, capture_output=True, timeout=30)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIn('PASS large binary stderr lossless', result.stdout)
            self.assertIn('PASS identity rejects before read', result.stdout)

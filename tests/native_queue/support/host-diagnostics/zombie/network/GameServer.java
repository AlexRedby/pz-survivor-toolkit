package zombie.network;

/** Offline process/pipe fixture. This class must never share the real game's classpath. */
public final class GameServer {
    public static void main(String[] args) throws Exception {
        var input = new java.io.BufferedReader(new java.io.InputStreamReader(System.in));
        if (!"go".equals(input.readLine())) throw new IllegalStateException("owner command missing");
        byte[] chunk = new byte[8192]; java.util.Arrays.fill(chunk, (byte)'E');
        boolean small = java.util.Arrays.asList(args).contains("--small-stderr");
        if (small) System.err.write('E');
        else for (int written = 0; written < 3 * 256 * 1024; written += chunk.length) System.err.write(chunk);
        System.err.flush();
        System.out.println("READY"); System.out.flush();
        System.out.println("ECHO " + input.readLine()); System.out.flush();
        if (java.util.Arrays.asList(args).contains("--exit=7")) System.exit(7);
    }
}

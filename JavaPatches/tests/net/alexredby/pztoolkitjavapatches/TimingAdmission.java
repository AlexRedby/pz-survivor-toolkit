package net.alexredby.pztoolkitjavapatches;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** Live admission for development timing banks; deliberately has no game dependencies. */
public final class TimingAdmission {
    private static final int TIMEOUT_MILLIS = 2000;
    private static final int MAX_RESPONSE_BYTES = 512;

    private TimingAdmission() {}

    public static boolean requested(String[] args, String bank) {
        if (!Arrays.asList(args).contains("--measure")) return false;
        require(bank);
        return true;
    }

    public static String require(String bank) {
        if (bank == null || bank.length() > 256
                || !bank.matches("[A-Za-z_$][A-Za-z0-9_$]*(\\.[A-Za-z_$][A-Za-z0-9_$]*)+")) {
            throw rejected("invalid bank name");
        }
        if (!bank.equals(System.getProperty("pz.timing.bank"))) {
            throw rejected("missing or mismatched pz.timing.bank for " + bank);
        }
        String token = System.getProperty("pz.timing.token", "");
        if (!token.matches("[0-9a-f]{64}")) throw rejected("missing or invalid pz.timing.token");
        int port;
        long owner;
        try {
            String portValue = System.getProperty("pz.timing.port", "");
            String ownerValue = System.getProperty("pz.timing.owner", "");
            if (!portValue.matches("[0-9]+") || !ownerValue.matches("[0-9]+")) {
                throw new NumberFormatException();
            }
            port = Integer.parseInt(portValue);
            owner = Long.parseLong(ownerValue);
            if (port < 1 || port > 65535 || owner <= 0) throw new NumberFormatException();
        } catch (NumberFormatException error) {
            throw rejected("missing or invalid pz.timing.port/pz.timing.owner");
        }
        ProcessHandle ancestor = ProcessHandle.current().parent().orElse(null);
        while (ancestor != null && ancestor.pid() != owner) {
            ancestor = ancestor.parent().orElse(null);
        }
        if (ancestor == null) throw rejected("timing owner is not an ancestor of this JVM");
        long pid = ProcessHandle.current().pid();
        String response;
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress("127.0.0.1", port), TIMEOUT_MILLIS);
            socket.setSoTimeout(TIMEOUT_MILLIS);
            socket.getOutputStream().write(
                    ("PZ_TIMING_V1\t" + token + "\t" + bank + "\t" + pid + "\n")
                            .getBytes(StandardCharsets.US_ASCII));
            socket.getOutputStream().flush();
            StringBuilder line = new StringBuilder();
            long deadline = System.nanoTime() + TIMEOUT_MILLIS * 1_000_000L;
            while (true) {
                long remaining = deadline - System.nanoTime();
                if (remaining <= 0) throw new SocketTimeoutException("Timing admission response timed out");
                socket.setSoTimeout((int) Math.max(1, (remaining + 999_999L) / 1_000_000L));
                int value = socket.getInputStream().read();
                if (value == '\n') break;
                if (value < 0 || value > 127 || line.length() >= MAX_RESPONSE_BYTES) {
                    throw rejected("invalid or incomplete timing service response");
                }
                line.append((char) value);
            }
            response = line.toString();
        } catch (IOException error) {
            throw new IllegalStateException("JVM timing admission rejected: timing service unavailable", error);
        }
        String[] fields = response.split("\t", -1);
        if (fields.length != 4 || !fields[0].equals("PZ_TIMING_OK")
                || !fields[1].matches("[0-9a-f]{32}") || !fields[2].equals(bank)
                || !fields[3].equals(Long.toString(pid))) {
            throw rejected("timing service refused or mismatched this bank/process");
        }
        System.out.println("TIMING_ADMISSION " + fields[1] + " " + bank + " pid=" + pid);
        return fields[1];
    }

    private static IllegalStateException rejected(String reason) {
        return new IllegalStateException("JVM timing admission rejected: " + reason);
    }
}

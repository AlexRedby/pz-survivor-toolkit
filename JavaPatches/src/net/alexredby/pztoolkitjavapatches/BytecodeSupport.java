package net.alexredby.pztoolkitjavapatches;

import java.security.MessageDigest;
import java.util.HexFormat;

/** Checks the installed class bytes without loading or initializing the game class. */
public final class BytecodeSupport {
    private BytecodeSupport() { }

    public static boolean supports(String resource, String expected) {
        try (var stream = BytecodeSupport.class.getClassLoader().getResourceAsStream(resource)) {
            return stream != null && expected.equals(HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(stream.readAllBytes())));
        } catch (Exception error) {
            System.err.println("[PZToolkitJavaPatches] Disabled: cannot check " + resource + ": " + error);
            return false;
        }
    }
}

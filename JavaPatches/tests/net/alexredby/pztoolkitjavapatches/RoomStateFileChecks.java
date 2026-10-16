package net.alexredby.pztoolkitjavapatches;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Comparator;
import java.util.concurrent.TimeUnit;

public final class RoomStateFileChecks {
    static final byte[] ORIGINAL = new byte[100003], NEXT = new byte[180007], LATER = new byte[200009];
    static {
        Arrays.fill(ORIGINAL, (byte) 17); Arrays.fill(NEXT, (byte) 29); Arrays.fill(LATER, (byte) 43);
    }
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static Path backup(Path target) { return target.resolveSibling("map_meta.bin.toolkit-original"); }
    static boolean equals(Path path, byte[] expected) throws IOException { return Arrays.equals(Files.readAllBytes(path), expected); }
    static Path fixture(Path root, String name) throws IOException {
        Path target = Files.createDirectory(root.resolve(name)).resolve("map_meta.bin");
        Files.write(target, ORIGINAL); return target;
    }
    static void noTemporary(Path directory) throws IOException {
        try (var files = Files.list(directory)) {
            require(files.noneMatch(path -> path.getFileName().toString().endsWith(".tmp")), "own temporary file leaked");
        }
    }
    static void expectFailure(Path target, ByteBuffer bytes) throws IOException {
        try { RoomStateFiles.write(target, bytes); throw new AssertionError("unsafe path accepted"); }
        catch (IOException expected) { }
    }
    static void phases(Path root) throws Exception {
        for (RoomStateFiles.Phase failure : RoomStateFiles.Phase.values()) {
            Path target = fixture(root, failure.name());
            int[] called = {0};
            try {
                RoomStateFiles.write(target, ByteBuffer.wrap(NEXT), (phase, temporary) -> {
                    called[0]++;
                    require(equals(backup(target), ORIGINAL), "backup not complete before callback");
                    if (temporary != null) require(temporary.getParent().equals(target.getParent()), "temporary outside save directory");
                    if (phase == RoomStateFiles.Phase.AFTER_TEMP_FORCE || phase == RoomStateFiles.Phase.BEFORE_PUBLISH)
                        require(equals(temporary, NEXT) && equals(target, ORIGINAL), "unforced/partial publication");
                    if (phase == failure) throw new IOException("injected " + phase);
                });
                throw new AssertionError("injected failure ignored");
            } catch (IOException expected) { require(expected.getMessage().equals("injected " + failure), "unexpected failure"); }
            require(called[0] == failure.ordinal() + 1, "callbacks continued after failure");
            require(equals(target, failure == RoomStateFiles.Phase.AFTER_PUBLISH ? NEXT : ORIGINAL), "partial target after failure");
            require(equals(backup(target), ORIGINAL), "first backup changed on failure");
            noTemporary(target.getParent());
            RoomStateFiles.write(target, ByteBuffer.wrap(LATER));
            require(equals(target, LATER) && equals(backup(target), ORIGINAL), "retry changed backup or payload");
            noTemporary(target.getParent());
        }
        Path target = fixture(root, "atomic-unsupported");
        try {
            RoomStateFiles.write(target, ByteBuffer.wrap(NEXT), (phase, temporary) -> {
                if (phase == RoomStateFiles.Phase.BEFORE_PUBLISH)
                    throw new AtomicMoveNotSupportedException(temporary.toString(), target.toString(), "injected");
            });
            throw new AssertionError("atomic move failure ignored");
        } catch (AtomicMoveNotSupportedException expected) { }
        require(equals(target, ORIGINAL) && equals(backup(target), ORIGINAL), "atomic failure used unsafe fallback");
        noTemporary(target.getParent());
    }
    static void buffersAndPaths(Path root) throws Exception {
        Path target = fixture(root, "buffers");
        ByteBuffer original = ByteBuffer.allocateDirect(NEXT.length + 11).order(ByteOrder.LITTLE_ENDIAN);
        original.position(7); original.mark(); original.put(NEXT); original.limit(original.position()); original.position(7);
        ByteBuffer readable = original.asReadOnlyBuffer().order(ByteOrder.LITTLE_ENDIAN); readable.mark();
        RoomStateFiles.write(target, readable);
        require(readable.position() == 7 && readable.limit() == NEXT.length + 7 && readable.order() == ByteOrder.LITTLE_ENDIAN,
            "caller buffer state changed");
        readable.reset(); require(readable.position() == 7 && equals(target, NEXT), "caller mark or readable bytes changed");
        RoomStateFiles.write(target, ByteBuffer.wrap(LATER));
        require(equals(target, LATER) && equals(backup(target), ORIGINAL), "multiple writes replaced original backup");
        Path foreign = target.resolveSibling(".map_meta.bin.foreign.tmp"); Files.write(foreign, new byte[]{77});
        RoomStateFiles.write(target, ByteBuffer.wrap(NEXT));
        require(equals(foreign, new byte[]{77}), "foreign temporary file deleted");
        Path wrongName = target.resolveSibling("other.bin"); Files.write(wrongName, ORIGINAL);
        expectFailure(wrongName, ByteBuffer.wrap(NEXT)); require(equals(wrongName, ORIGINAL), "wrong filename overwritten");
        Path linked = Files.createDirectory(root.resolve("target-symlink")).resolve("map_meta.bin");
        Files.createSymbolicLink(linked, target); expectFailure(linked, ByteBuffer.wrap(LATER));
        require(Files.isSymbolicLink(linked) && equals(target, NEXT) && !Files.exists(backup(linked)), "target symlink followed/replaced");
        Path backupLink = fixture(root, "backup-symlink"); Files.createSymbolicLink(backup(backupLink), target);
        expectFailure(backupLink, ByteBuffer.wrap(LATER));
        require(equals(backupLink, ORIGINAL) && Files.isSymbolicLink(backup(backupLink)) && equals(target, NEXT), "backup symlink followed/replaced");
        Path existing = fixture(root, "existing-backup"); Files.write(backup(existing), new byte[]{55, 66});
        RoomStateFiles.write(existing, ByteBuffer.wrap(NEXT));
        require(equals(backup(existing), new byte[]{55, 66}), "existing backup overwritten");
    }
    static void newWorld(Path root) throws Exception {
        for (RoomStateFiles.Phase failure : RoomStateFiles.Phase.values()) {
            Path target = Files.createDirectory(root.resolve("new-" + failure)).resolve("map_meta.bin");
            try {
                RoomStateFiles.write(target, ByteBuffer.wrap(NEXT), (phase, temporary) -> {
                    require(!Files.exists(backup(target)), "new world created a fake original backup");
                    if (phase == failure) throw new IOException("new world " + phase);
                });
                throw new AssertionError("new-world failure ignored");
            } catch (IOException expected) { require(expected.getMessage().equals("new world " + failure), "unexpected new-world failure"); }
            if (failure == RoomStateFiles.Phase.AFTER_PUBLISH) require(equals(target, NEXT), "new-world publication incomplete");
            else require(!Files.exists(target), "failed initial save created a target");
            require(!Files.exists(backup(target)), "failed initial save invented original backup");
            noTemporary(target.getParent());
        }
        Path target = Files.createDirectory(root.resolve("new-world")).resolve("map_meta.bin");
        RoomStateFiles.write(target, ByteBuffer.wrap(NEXT));
        require(equals(target, NEXT) && !Files.exists(backup(target)), "first creation failed or created fake backup");
        RoomStateFiles.write(target, ByteBuffer.wrap(LATER));
        require(equals(target, LATER) && equals(backup(target), NEXT), "first overwrite did not preserve initial file");
        Files.delete(target);
        expectFailure(target, ByteBuffer.wrap(ORIGINAL));
        require(!Files.exists(target) && equals(backup(target), NEXT), "missing managed file was silently recreated");
        noTemporary(target.getParent());
        Path appeared = Files.createDirectory(root.resolve("new-target-appeared")).resolve("map_meta.bin");
        try {
            RoomStateFiles.write(appeared, ByteBuffer.wrap(NEXT), (phase, temporary) -> {
                if (phase == RoomStateFiles.Phase.BEFORE_PUBLISH) Files.write(appeared, ORIGINAL);
            });
            throw new AssertionError("newly appeared target overwritten without backup");
        } catch (IOException expected) { }
        require(equals(appeared, ORIGINAL) && !Files.exists(backup(appeared)), "newly appeared target damaged");
        noTemporary(appeared.getParent());
    }
    static void abrupt(Path root) throws Exception {
        for (RoomStateFiles.Phase phase : new RoomStateFiles.Phase[]{RoomStateFiles.Phase.AFTER_TEMP_FORCE,
                RoomStateFiles.Phase.BEFORE_PUBLISH, RoomStateFiles.Phase.AFTER_PUBLISH}) {
            Path target = fixture(root, "halt-" + phase);
            Process process = new ProcessBuilder(Path.of(System.getProperty("java.home"), "bin", "java").toString(),
                "-cp", System.getProperty("java.class.path"), RoomStateFileChecks.class.getName(),
                "halt", target.toString(), phase.name()).inheritIO().start();
            if (!process.waitFor(20, TimeUnit.SECONDS)) { process.destroyForcibly(); throw new AssertionError("halt child hung"); }
            require(process.exitValue() == 71, "halt child did not reach phase " + phase);
            require(equals(target, phase == RoomStateFiles.Phase.AFTER_PUBLISH ? NEXT : ORIGINAL)
                && equals(backup(target), ORIGINAL), "abrupt exit left partial file/backup");
            RoomStateFiles.write(target, ByteBuffer.wrap(LATER));
            require(equals(target, LATER) && equals(backup(target), ORIGINAL), "restart write lost original backup");
        }
    }
    public static void main(String[] args) throws Exception {
        if (args.length == 3 && args[0].equals("halt")) {
            RoomStateFiles.write(Path.of(args[1]), ByteBuffer.wrap(NEXT), (phase, temporary) -> {
                if (phase == RoomStateFiles.Phase.valueOf(args[2])) Runtime.getRuntime().halt(71);
            });
            throw new AssertionError("halt phase not reached");
        }
        Path root = Files.createTempDirectory("room-state-files-checks-");
        try { phases(root); buffersAndPaths(root); newWorld(root); abrupt(root); }
        finally {
            try (var paths = Files.walk(root)) {
                for (Path path : paths.sorted(Comparator.reverseOrder()).toList()) Files.delete(path);
            }
        }
        System.out.println("ROOM_STATE_FILE_CHECKS_PASS (all fault phases, original backup, atomic publication,"
            + " new-world creation, buffer state, symlink refusal, foreign temps, abrupt child exits and restart)");
    }
}

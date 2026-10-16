package net.alexredby.pztoolkitjavapatches;

import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.file.AccessDeniedException;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.NoSuchFileException;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.BasicFileAttributes;

public final class RoomStateFiles {
    private RoomStateFiles() { }

    enum Phase { AFTER_BACKUP, AFTER_TEMP_FORCE, BEFORE_PUBLISH, AFTER_PUBLISH }
    interface Hook { void at(Phase phase, Path temporary) throws IOException; }

    public static void write(Path target, ByteBuffer readable) throws IOException {
        write(target, readable, (phase, temporary) -> { });
    }

    static synchronized void write(Path target, ByteBuffer readable, Hook hook) throws IOException {
        ByteBuffer bytes = readable.duplicate();
        if (!target.getFileName().toString().equals("map_meta.bin")) throw new IOException("Expected map_meta.bin");
        target = target.toAbsolutePath();
        Path directory = target.getParent(), backup = directory.resolve("map_meta.bin.toolkit-original");
        boolean hasTarget = regularOrMissing(target), hasBackup = regularOrMissing(backup);
        if (!hasTarget && hasBackup) throw new IOException("Original backup exists but map_meta.bin is missing");
        if (hasTarget && !hasBackup) backup(target, backup, directory);
        hook.at(Phase.AFTER_BACKUP, null);
        Path temporary = Files.createTempFile(directory, ".map_meta.bin.", ".tmp");
        try {
            try (FileChannel output = FileChannel.open(temporary, StandardOpenOption.WRITE, LinkOption.NOFOLLOW_LINKS)) {
                while (bytes.hasRemaining()) output.write(bytes);
                output.force(true);
            }
            hook.at(Phase.AFTER_TEMP_FORCE, temporary);
            hook.at(Phase.BEFORE_PUBLISH, temporary);
            if (hasTarget) { regular(target); regular(backup); }
            else if (regularOrMissing(target) || regularOrMissing(backup))
                throw new IOException("New save target changed before publication");
            Files.move(temporary, target, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            forceDirectory(directory);
            hook.at(Phase.AFTER_PUBLISH, temporary);
        } finally { removeTemporary(temporary); }
    }

    private static void regular(Path path) throws IOException {
        if (!Files.readAttributes(path, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS).isRegularFile())
            throw new IOException("Expected regular file without symlink: " + path);
    }

    private static boolean regularOrMissing(Path path) throws IOException {
        try { regular(path); return true; }
        catch (NoSuchFileException absent) { return false; }
    }

    private static void backup(Path target, Path backup, Path directory) throws IOException {
        Path temporary = Files.createTempFile(directory, ".map_meta.bin.toolkit-original.", ".tmp");
        try {
            try (FileChannel input = FileChannel.open(target, StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS);
                 FileChannel output = FileChannel.open(temporary, StandardOpenOption.WRITE, LinkOption.NOFOLLOW_LINKS)) {
                ByteBuffer bytes = ByteBuffer.allocate(65536);
                while (input.read(bytes) != -1) {
                    bytes.flip();
                    while (bytes.hasRemaining()) output.write(bytes);
                    bytes.clear();
                }
                output.force(true);
            }
            // A hard link publishes complete backup bytes exclusively; ATOMIC_MOVE may replace an existing name.
            try { Files.createLink(backup, temporary); }
            catch (FileAlreadyExistsException existing) { regular(backup); }
            catch (UnsupportedOperationException unsupported) { throw new IOException("Atomic original backup creation is unavailable", unsupported); }
            forceDirectory(directory);
        } finally { removeTemporary(temporary); }
    }

    private static void forceDirectory(Path directory) throws IOException {
        try (FileChannel channel = FileChannel.open(directory, StandardOpenOption.READ)) { channel.force(true); }
        catch (UnsupportedOperationException unsupported) { /* The provider does not support directory fsync. */ }
        catch (AccessDeniedException unsupported) {
            // Windows cannot open directories with FileChannel; payload force and atomic replacement still apply.
            if (File.separatorChar != '\\') throw unsupported;
        }
    }

    private static void removeTemporary(Path temporary) {
        try { Files.deleteIfExists(temporary); } catch (IOException ignored) { }
    }
}

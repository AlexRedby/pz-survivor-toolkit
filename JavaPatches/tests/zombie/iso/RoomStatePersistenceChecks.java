package zombie.iso;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.function.Consumer;
import me.zed_0xff.zombie_buddy.PatchEngine;
import net.alexredby.pztoolkitjavapatches.Main;
import net.alexredby.pztoolkitjavapatches.RoomStatePersistence;
import zombie.core.stash.StashSystem;

/** Runs the actual installed advice, native readers, direct file writer and queued snapshot writer. */
public final class RoomStatePersistenceChecks {
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static IsoMetaGrid grid(int first, int last) throws Exception {
        return RoomCollisionChecks.grid(RoomCollisionChecks.room(107, 786643, first),
            RoomCollisionChecks.room(200, 123456, 5), RoomCollisionChecks.room(306, 786643, last));
    }
    static RoomDef first(IsoMetaGrid grid) { return grid.getCellData(41, 37).roomList.get(0); }
    static RoomDef last(IsoMetaGrid grid) { return grid.getCellData(41, 37).roomList.get(2); }
    static void states(IsoMetaGrid grid, int a, int b) {
        require(RoomCollisionChecks.flags(first(grid)) == a && RoomCollisionChecks.flags(last(grid)) == b,
            "separate room states were lost");
    }
    static ByteBuffer save(IsoMetaGrid grid, ByteOrder order) {
        ByteBuffer bytes = ByteBuffer.allocate(8192).order(order);
        bytes.putLong(0x1122334455667788L); grid.save(bytes); bytes.flip(); bytes.position(8); return bytes;
    }
    static byte[] contents(ByteBuffer bytes) {
        byte[] value = new byte[bytes.remaining()]; bytes.duplicate().get(value); return value;
    }
    interface Attempt { void run() throws Exception; }
    static void refused(Attempt attempt) throws Exception {
        try { attempt.run(); throw new AssertionError("unsafe operation succeeded"); }
        catch (IllegalStateException expected) { }
    }
    static void fileSave(IsoMetaGrid grid, Consumer<ByteBuffer> writer) throws Exception {
        Method save = IsoMetaGrid.class.getDeclaredMethod("save", String.class, Consumer.class);
        save.setAccessible(true);
        try { save.invoke(grid, "map_meta.bin", writer); }
        catch (InvocationTargetException error) {
            if (error.getCause() instanceof Exception cause) throw cause;
            throw error;
        }
    }
    static void nativeCompatibility() throws Exception {
        IsoMetaGrid source = grid(3, 12);
        ByteBuffer bytes = RoomCollisionChecks.save(source, ByteOrder.BIG_ENDIAN);
        int end = bytes.limit(); bytes.position(end); bytes.limit(bytes.capacity());
        RoomStatePersistence.append(source, bytes, 8, true); bytes.flip(); bytes.position(8);
        IsoMetaGrid nativeReader = grid(0, 0); nativeReader.load(bytes);
        states(nativeReader, 0, 12);
        require(bytes.position() == end && bytes.remaining() == RoomStatePersistence.TRAILER_SIZE,
            "ordinary native reader did not ignore the appended provenance");
    }
    static void wovenRoundTrips() throws Exception {
        int cases = 0;
        for (ByteOrder order : new ByteOrder[]{ByteOrder.BIG_ENDIAN, ByteOrder.LITTLE_ENDIAN}) {
            for (int a = 0; a < 16; a++) for (int b = 0; b < 16; b++) {
                IsoMetaGrid source = grid(a, b);
                ByteBuffer nativePrefix = RoomCollisionChecks.save(source, order);
                ByteBuffer bytes = save(source, order), raw = RoomCollisionChecks.copy(bytes);
                require(RoomStatePersistence.hasTrailer(bytes), "woven writer omitted provenance");
                ByteBuffer prefix = bytes.duplicate(); prefix.limit(prefix.limit() - RoomStatePersistence.TRAILER_SIZE);
                require(prefix.equals(nativePrefix), "provenance changed native prefix bytes");
                IsoMetaGrid target = grid(0, 0);
                var cell = target.getCellData(41, 37);
                var list = new ArrayList<>(cell.roomList);
                var runtime = new java.util.HashMap<>(cell.rooms);
                var persistent = new gnu.trove.map.hash.TLongObjectHashMap<>(cell.roomByMetaId);
                var chunk = new IsoChunk((IsoCell)null); chunk.addSpawnedRoom(first(target).id); chunk.addSpawnedRoom(last(target).id);
                target.load(bytes); states(target, a, b);
                require(bytes.position() == bytes.limit() - RoomStatePersistence.TRAILER_SIZE,
                    "woven loader changed the native load boundary");
                require(cell.roomList.equals(list) && cell.rooms.equals(runtime) && cell.roomByMetaId.equals(persistent)
                    && chunk.isSpawnedRoom(first(target).id) && chunk.isSpawnedRoom(last(target).id), "room identities/indexes/spawn receipts changed");
                ByteBuffer second = save(target, order); require(second.equals(raw), "full second save differs");
                IsoMetaGrid third = grid(0, 0); third.load(second); states(third, a, b); cases++;
            }
        }
        require(cases == 512, "flag cases omitted");
        for (int value = 0; value < 16; value++) {
            IsoMetaGrid migrated = grid(0, 0);
            migrated.load(RoomCollisionChecks.save(grid(value, value), ByteOrder.BIG_ENDIAN)); states(migrated, value, value);
            RoomCollisionChecks.setFlags(first(migrated), 1); RoomCollisionChecks.setFlags(last(migrated), 14);
            IsoMetaGrid reloaded = grid(0, 0); reloaded.load(save(migrated, ByteOrder.BIG_ENDIAN)); states(reloaded, 1, 14);
        }
    }
    static void guards() throws Exception {
        ByteBuffer valid = save(grid(1, 14), ByteOrder.BIG_ENDIAN);
        for (int offset : new int[]{8, valid.limit() - 112, valid.limit() - 100, valid.limit() - 60,
                                    valid.limit() - 30, valid.limit() - 1}) {
            ByteBuffer bad = RoomCollisionChecks.copy(valid); bad.put(offset, (byte)(bad.get(offset) ^ 1));
            byte[] before = contents(bad); IsoMetaGrid target = grid(0, 0);
            refused(() -> target.load(bad));
            require(bad.position() == 8 && Arrays.equals(before, contents(bad)), "checksum rejection changed input");
            refused(() -> target.save(ByteBuffer.allocate(8192)));
            refused(() -> target.load(valid.duplicate()));
        }
        for (int missing : new int[]{1, 8, 60, 112}) {
            ByteBuffer bad = RoomCollisionChecks.copy(valid); bad.limit(bad.limit() - missing);
            IsoMetaGrid target = grid(0, 0); refused(() -> target.load(bad)); refused(() -> target.save(ByteBuffer.allocate(8192)));
        }
        ByteBuffer legacy = RoomCollisionChecks.save(grid(1, 14), ByteOrder.BIG_ENDIAN);
        IsoMetaGrid ambiguous = grid(0, 0); refused(() -> ambiguous.load(legacy)); require(legacy.position() == 8, "ambiguous legacy input consumed");
        IsoMetaGrid changed = grid(0, 0); changed.load(valid.duplicate()); first(changed).name = "modified";
        refused(() -> changed.save(ByteBuffer.allocate(8192)));
        ByteBuffer readonly = ByteBuffer.allocateDirect(valid.remaining()); readonly.put(valid.duplicate()).flip();
        IsoMetaGrid direct = grid(0, 0); direct.load(readonly.asReadOnlyBuffer()); states(direct, 1, 14);
        IsoMetaGrid unsupported = grid(0, 0); refused(() -> RoomStatePersistence.prepare(unsupported, valid.duplicate(), false));
    }
    static void files() throws Exception {
        IsoWorld.instance.setGameMode("Sandbox"); IsoWorld.instance.setWorld("RoomStateNativeChecks");
        Path target = zombie.ZomboidFileSystem.instance.getFileInCurrentSave("map_meta.bin").toPath();
        Files.createDirectories(target.getParent());
        byte[] legacy = contents(RoomCollisionChecks.save(grid(0, 0), ByteOrder.BIG_ENDIAN));
        Files.write(target, legacy);
        IsoMetaGrid migrated = grid(0, 0); migrated.load(); states(migrated, 0, 0);
        RoomCollisionChecks.setFlags(first(migrated), 1); RoomCollisionChecks.setFlags(last(migrated), 14);
        fileSave(migrated, migrated::save);
        Path backup = target.resolveSibling("map_meta.bin.toolkit-original");
        require(Arrays.equals(legacy, Files.readAllBytes(backup)), "first native original was not preserved");
        IsoMetaGrid loaded = grid(0, 0); loaded.load(); states(loaded, 1, 14);
        var buffers = new SaveBufferMap(); loaded.saveToSaveBufferMap(buffers, target.toString(), loaded::save);
        byte[] before = Files.readAllBytes(target);
        RoomCollisionChecks.setFlags(first(loaded), 2); RoomCollisionChecks.setFlags(last(loaded), 13);
        buffers.save((name, pooled) -> { throw new AssertionError("native writer used for managed snapshot"); }); buffers.clear();
        require(Arrays.equals(before, Files.readAllBytes(target)), "queue read live flags instead of captured snapshot");
        require(Arrays.equals(legacy, Files.readAllBytes(backup)), "queued save replaced original backup");
        IsoMetaGrid queued = grid(0, 0); queued.load(); states(queued, 1, 14);
        fileSave(loaded, loaded::save); IsoMetaGrid updated = grid(0, 0); updated.load(); states(updated, 2, 13);
        before = Files.readAllBytes(target);
        refused(() -> fileSave(updated, bytes -> { bytes.putInt(99); throw new IllegalStateException("injected serializer failure"); }));
        require(Arrays.equals(before, Files.readAllBytes(target)), "serializer failure truncated original file");
        refused(updated::save);
        require(Arrays.equals(before, Files.readAllBytes(target)), "public native save swallowed refused state");
        before[before.length - 1] ^= 1; Files.write(target, before);
        IsoMetaGrid bad = grid(0, 0); refused(bad::load); refused(bad::save);
        require(Arrays.equals(before, Files.readAllBytes(target)), "refused outer native load/save changed file");
        IsoMetaGrid queueFailure = grid(0, 0); var failing = new SaveBufferMap();
        queueFailure.saveToSaveBufferMap(failing, target.toString(), queueFailure::save);
        Files.delete(target);
        try { failing.save((name, pooled) -> { throw new AssertionError("native writer used"); }); throw new AssertionError("queued write failure ignored"); }
        catch (java.io.IOException expected) { }
        failing.clear(); refused(queueFailure::save);
        require(Arrays.equals(legacy, Files.readAllBytes(backup)), "queued failure damaged immutable original");
    }
    public static void main(String[] args) throws Exception {
        String cache = System.getProperty("pz.test.cache"); require(cache != null, "isolated cache required");
        zombie.ZomboidFileSystem.instance.setCacheDir(cache); zombie.core.random.RandStandard.INSTANCE.init();
        zombie.ZomboidFileSystem.instance.base.set(Path.of(".").toFile());
        StashSystem.allStashes = new ArrayList<>(); StashSystem.possibleStashes = new ArrayList<>();
        IsoMetaGrid warmup = grid(0, 0); warmup.load(RoomCollisionChecks.initialFixture(warmup, ByteOrder.BIG_ENDIAN));
        nativeCompatibility(); Main.main(new String[0]); require(Main.roomStateSupported(), "native room guard disabled");
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", RoomStatePersistenceChecks.class.getClassLoader());
        wovenRoundTrips(); guards(); files();
        System.out.println("ROOM_STATE_PERSISTENCE_CHECKS_PASS (woven all512 pairs, native prefix/read compatibility, legacy divergence/reload, corrupt/ambiguous/layout guards, atomic native file and captured queued saves, swallowed load/save refusal, immutable original, IDs/indexes/spawn receipts)");
    }
}

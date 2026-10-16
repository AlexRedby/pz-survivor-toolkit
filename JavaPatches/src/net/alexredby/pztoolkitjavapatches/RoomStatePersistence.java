package net.alexredby.pztoolkitjavapatches;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;
import zombie.iso.IsoMetaCell;
import zombie.iso.IsoMetaGrid;
import zombie.iso.RoomDef;
import zombie.iso.RoomID;

public final class RoomStatePersistence {
    public static final int TRAILER_SIZE = 112;
    private static final long MAGIC = 0x505a544b524f4f4dL; // PZTKROOM
    private static final long END = 0x505a544b52454e44L; // PZTKREND
    private static final long META_ID = 786643;
    private static final Map<IsoMetaGrid, State> pending = new WeakHashMap<>();
    private static final Map<IsoMetaGrid, State> managed = new WeakHashMap<>();
    private static final Set<IsoMetaGrid> saveReported = Collections.newSetFromMap(new WeakHashMap<>());

    private RoomStatePersistence() { }

    public static final class State {
        private final byte[] raw;
        private RoomDef base, access;
        private byte[] layout;
        private int baseFlags, accessFlags, nativeEnd;
        private boolean extended;
        private String reason = "map_meta load has not completed";

        private State(ByteBuffer input) {
            if (input == null) raw = null;
            else {
                ByteBuffer copy = input.duplicate();
                raw = new byte[copy.remaining()];
                copy.get(raw);
            }
        }
    }

    public static synchronized boolean affected(IsoMetaGrid grid, boolean supported) {
        requireReady(grid);
        if (!supported) {
            if (managed.containsKey(grid)) {
                fail(grid, new IllegalStateException("managed room provenance support is unavailable"));
                requireReady(grid);
            }
            return false;
        }
        IsoMetaCell cell = grid.getCellData(41, 37);
        if (cell == null) return false;
        int matches = 0;
        for (RoomDef room : cell.roomList) if (room.metaId == META_ID) matches++;
        return matches >= 2;
    }

    public static boolean hasTrailer(ByteBuffer input) {
        ByteBuffer copy = input.duplicate().order(ByteOrder.BIG_ENDIAN);
        if (copy.remaining() >= 8 && copy.getLong(copy.limit() - 8) == END) return true;
        for (int index = Math.max(copy.position(), copy.limit() - TRAILER_SIZE); index <= copy.limit() - 8; index++)
            if (copy.getLong(index) == MAGIC) return true;
        return false;
    }

    public static synchronized State prepare(IsoMetaGrid grid, ByteBuffer input, boolean supported) {
        requireReady(grid);
        boolean trailer = hasTrailer(input);
        if (!supported && !trailer) return null;
        if (supported && !affected(grid, true) && !trailer) return null;
        int trailerStart = input.limit() - TRAILER_SIZE;
        State state = new State(input);
        pending.put(grid, state);
        try {
            require(supported, "extended map_meta requires supported room provenance loading");
            RoomDef[] owners = owners(grid);
            state.base = owners[0]; state.access = owners[1];
            state.layout = layout(grid);
            state.nativeEnd = input.limit();
            if (trailer) {
                require(trailerStart >= input.position(), "truncated room provenance trailer");
                readTrailer(input, trailerStart, state);
            }
            ByteBuffer nativeInput = input.duplicate().order(input.order());
            nativeInput.limit(state.nativeEnd);
            int[] flags = readRooms(grid, nativeInput, state.base, state.access);
            if (state.extended) {
                require(flags[0] == state.baseFlags && flags[1] == state.accessFlags,
                    "trailer room flags differ from native records");
            } else {
                require(flags[0] == flags[1],
                    "legacy duplicate flags differ; historical owner provenance is unavailable; explicit recovery required");
                state.baseFlags = flags[0]; state.accessFlags = flags[1];
            }
            return state;
        } catch (RuntimeException exception) {
            state.reason = "map_meta room state refused: " + exception;
            throw new IllegalStateException(message(state), exception);
        }
    }

    private static void readTrailer(ByteBuffer input, int start, State state) {
        ByteBuffer trailer = input.duplicate().order(ByteOrder.BIG_ENDIAN);
        trailer.position(start);
        require(trailer.getLong() == MAGIC && trailer.getInt() == 1 && trailer.getInt() == TRAILER_SIZE,
            "unsupported room provenance trailer");
        int length = trailer.getInt();
        require(length >= 24 && (long)input.position() + length == start, "invalid native prefix length");
        byte[] layout = new byte[32]; trailer.get(layout);
        require(MessageDigest.isEqual(layout, state.layout), "room layout fingerprint changed");
        require(trailer.getLong() == state.base.id, "base room identity changed");
        state.baseFlags = Short.toUnsignedInt(trailer.getShort());
        require(trailer.getLong() == state.access.id, "access room identity changed");
        state.accessFlags = Short.toUnsignedInt(trailer.getShort());
        require(((state.baseFlags | state.accessFlags) & ~15) == 0, "unknown provenance room flags");
        byte[] binding = new byte[32]; trailer.get(binding);
        require(trailer.getLong() == END, "room provenance end marker changed");
        require(MessageDigest.isEqual(binding, binding(input, input.position(), start)),
            "room provenance checksum mismatch");
        state.extended = true;
        state.nativeEnd = start;
    }

    private static int[] readRooms(IsoMetaGrid grid, ByteBuffer input, RoomDef base, RoomDef access) {
        require(input.get() == 77 && input.get() == 69 && input.get() == 84 && input.get() == 65,
            "unsupported map_meta signature");
        require(input.getInt() == 249, "unsupported map_meta version");
        int minX = input.getInt(), minY = input.getInt(), maxX = input.getInt(), maxY = input.getInt();
        require(minX == grid.minX && minY == grid.minY && maxX == grid.maxX && maxY == grid.maxY,
            "saved cell bounds changed");
        long width = (long)maxX - minX + 1, height = (long)maxY - minY + 1;
        require(width > 0 && height > 0 && width <= input.remaining() / 8
            && height <= input.remaining() / 8 && width * height <= input.remaining() / 8,
            "invalid saved cell count");
        int[] flags = {-1, -1};
        for (long x = minX; x <= maxX; x++) for (long y = minY; y <= maxY; y++) {
            int count = input.getInt();
            require(count >= 0 && count <= input.remaining() / 10, "invalid room record count");
            if (x == 41 && y == 37) {
                ArrayList<RoomDef> rooms = savedRooms(grid);
                require(count == rooms.size(), "target full-cell room count changed");
                for (RoomDef room : rooms) {
                    require(input.getLong() == room.metaId, "target full-cell ordered room IDs changed");
                    int value = Short.toUnsignedInt(input.getShort());
                    require((value & ~15) == 0, "unknown saved room flags");
                    if (room == base) flags[0] = value;
                    if (room == access) flags[1] = value;
                }
            } else input.position(input.position() + count * 10);
            int buildings = input.getInt();
            require(buildings >= 0 && buildings <= input.remaining() / 23, "invalid building record count");
            if (x == 41 && y == 37) require(buildings == grid.getCellData(41, 37).getBuildingCount(true),
                "target building count changed");
            input.position(input.position() + buildings * 23);
        }
        require(flags[0] >= 0 && flags[1] >= 0, "target room records missing");
        return flags;
    }

    public static synchronized void loaded(IsoMetaGrid grid, State state, ByteBuffer input) {
        if (state == null) return;
        require(pending.get(grid) == state, "room-state load transaction changed");
        try {
            require(input.position() == state.nativeEnd, "native load boundary differs; unknown or truncated extension");
            RoomDef[] owners = owners(grid);
            require(owners[0] == state.base && owners[1] == state.access
                && MessageDigest.isEqual(state.layout, layout(grid)), "room layout changed during load");
            flags(state.base, state.baseFlags); flags(state.access, state.accessFlags);
            pending.remove(grid);
            managed.put(grid, state);
            System.out.println("[PZToolkitJavaPatches] Room state persistence loaded: "
                + (state.extended ? "validated provenance" : "legacy equal flags; provenance will be added on save"));
        } catch (RuntimeException exception) {
            fail(grid, exception);
            throw new IllegalStateException(message(state), exception);
        }
    }

    public static synchronized void append(IsoMetaGrid grid, ByteBuffer output, int nativeStart, boolean supported) {
        requireReady(grid);
        if (!affected(grid, supported)) return;
        int nativeEnd = output.position();
        try {
            RoomDef[] owners = owners(grid);
            byte[] savedLayout = layout(grid);
            require(nativeStart >= 0 && nativeStart <= nativeEnd, "invalid native output start");
            ByteBuffer prefix = output.duplicate().order(output.order());
            prefix.position(nativeStart); prefix.limit(nativeEnd);
            require(!hasTrailer(prefix), "native output already contains room provenance");
            int[] savedFlags = readRooms(grid, prefix, owners[0], owners[1]);
            require(savedFlags[0] == flags(owners[0]) && savedFlags[1] == flags(owners[1]),
                "runtime room flags changed during save");
            ByteBuffer trailer = ByteBuffer.allocate(TRAILER_SIZE).order(ByteOrder.BIG_ENDIAN);
            trailer.putLong(MAGIC).putInt(1).putInt(TRAILER_SIZE).putInt(nativeEnd - nativeStart).put(savedLayout);
            trailer.putLong(owners[0].id).putShort((short)savedFlags[0]);
            trailer.putLong(owners[1].id).putShort((short)savedFlags[1]);
            // Build the trailer separately so a short output buffer cannot change native bytes or its position.
            MessageDigest digest = sha256();
            update(digest, output, nativeStart, nativeEnd);
            digest.update(trailer.array(), 0, 72);
            digest.update(ByteBuffer.allocate(8).putLong(END).array());
            trailer.put(digest.digest()).putLong(END);
            output.put(trailer.array());
            State saved = new State(slice(output, nativeStart, output.position()));
            saved.base = owners[0]; saved.access = owners[1]; saved.layout = savedLayout;
            require(MessageDigest.isEqual(savedLayout, layout(grid)), "room layout changed during save");
            saved.baseFlags = savedFlags[0]; saved.accessFlags = savedFlags[1];
            saved.extended = true; saved.nativeEnd = nativeEnd;
            managed.put(grid, saved);
            if (saveReported.add(grid)) System.out.println("[PZToolkitJavaPatches] Room state persistence serialized: bound owner provenance");
        } catch (RuntimeException exception) {
            State state = managed.get(grid);
            if (state == null) state = new State(slice(output, Math.min(nativeEnd, Math.max(0, nativeStart)), nativeEnd));
            state.reason = "room provenance save failed: " + exception;
            pending.put(grid, state);
            throw new IllegalStateException(message(state), exception);
        }
    }

    public static synchronized void fail(IsoMetaGrid grid, Throwable cause) {
        State state = pending.get(grid);
        if (state == null) {
            state = managed.get(grid);
            if (state == null) state = new State(null);
            pending.put(grid, state);
        }
        state.reason = "room state transaction failed: " + cause;
    }

    public static synchronized void requireReady(IsoMetaGrid grid) {
        State state = pending.get(grid);
        if (state != null) throw new IllegalStateException(message(state));
        state = managed.get(grid);
        if (state != null) {
            try {
                RoomDef[] owners = owners(grid);
                require(owners[0] == state.base && owners[1] == state.access
                    && MessageDigest.isEqual(state.layout, layout(grid)), "managed room layout changed");
            } catch (RuntimeException exception) {
                fail(grid, exception);
                throw new IllegalStateException(message(state), exception);
            }
        }
    }

    private static RoomDef[] owners(IsoMetaGrid grid) {
        IsoMetaCell cell = grid.getCellData(41, 37);
        require(cell != null && cell.info != null, "target cell header missing");
        RoomDef base = null, access = null;
        int matches = 0;
        for (RoomDef room : cell.roomList) {
            if (room.metaId != META_ID) continue;
            require(!room.userDefined && room.level == 0 && "hall".equals(room.name) && room.rects.size() == 1,
                "target room descriptor changed");
            RoomDef.RoomRect rect = room.rects.get(0);
            require(rect.x == 10707 && rect.y == 9484 && rect.w == 1 && rect.h == 4, "target room rectangle changed");
            require(RoomID.isSameCell(room.id, 41, 37) && cell.rooms.get(room.id) == room
                && room.building != null && cell.buildings.contains(room.building)
                && room.building.rooms.contains(room), "target room owner changed");
            if (matches++ == 0) base = room;
            else if (matches == 2) access = room;
        }
        require(matches == 2 && base != access, "target collision count changed");
        require(RoomID.getIndex(base.id) == 107 && RoomID.getIndex(access.id) >= 303
            && cell.roomList.indexOf(base) < cell.roomList.indexOf(access)
            && cell.roomByMetaId.get(META_ID) == access,
            "stock and appended room identity/order changed");
        return new RoomDef[]{base, access};
    }

    private static ArrayList<RoomDef> savedRooms(IsoMetaGrid grid) {
        ArrayList<RoomDef> rooms = new ArrayList<>();
        for (RoomDef room : grid.getCellData(41, 37).roomList) if (!room.userDefined) rooms.add(room);
        return rooms;
    }

    private static byte[] layout(IsoMetaGrid grid) {
        try {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            DataOutputStream output = new DataOutputStream(bytes);
            ArrayList<RoomDef> rooms = savedRooms(grid);
            output.writeInt(rooms.size());
            for (RoomDef room : rooms) {
                output.writeLong(room.id); output.writeLong(room.metaId); output.writeInt(room.level);
                byte[] name = room.name == null ? null : room.name.getBytes(StandardCharsets.UTF_8);
                output.writeInt(name == null ? -1 : name.length);
                if (name != null) output.write(name);
                output.writeInt(room.rects.size());
                for (RoomDef.RoomRect rect : room.rects) {
                    output.writeInt(rect.x); output.writeInt(rect.y); output.writeInt(rect.w); output.writeInt(rect.h);
                }
                output.writeBoolean(room.building != null);
                if (room.building != null) {
                    output.writeLong(room.building.id); output.writeLong(room.building.metaId);
                }
            }
            return sha256().digest(bytes.toByteArray());
        } catch (java.io.IOException exception) { throw new IllegalStateException(exception); }
    }

    private static byte[] binding(ByteBuffer input, int nativeStart, int trailerStart) {
        MessageDigest digest = sha256();
        update(digest, input, nativeStart, trailerStart + 72);
        update(digest, input, trailerStart + 104, trailerStart + TRAILER_SIZE);
        return digest.digest();
    }

    private static void update(MessageDigest digest, ByteBuffer input, int start, int end) {
        digest.update(slice(input, start, end));
    }

    private static ByteBuffer slice(ByteBuffer input, int start, int end) {
        ByteBuffer copy = input.duplicate(); copy.limit(end); copy.position(start); return copy;
    }

    private static MessageDigest sha256() {
        try { return MessageDigest.getInstance("SHA-256"); }
        catch (java.security.NoSuchAlgorithmException exception) { throw new IllegalStateException(exception); }
    }

    private static int flags(RoomDef room) {
        return (room.explored ? 1 : 0) | (room.lightsActive ? 2 : 0)
            | (room.doneSpawn ? 4 : 0) | (room.isRoofFixed() ? 8 : 0);
    }

    private static void flags(RoomDef room, int flags) {
        room.setExplored((flags & 1) != 0); room.lightsActive = (flags & 2) != 0;
        room.doneSpawn = (flags & 4) != 0; room.setRoofFixed((flags & 8) != 0);
    }

    private static String message(State state) {
        return "[PZToolkitJavaPatches] " + state.reason
            + (state.raw == null ? "; existing save must be retained" : "; original raw input retained") + "; saving blocked";
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }
}

package net.alexredby.lotstreamingfixture;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.ChunkMapFilenames;
import zombie.ZomboidFileSystem;
import zombie.characters.animals.AnimalZone;
import zombie.iso.IsoChunk;
import zombie.iso.IsoLot;
import zombie.iso.IsoMetaCell;
import zombie.iso.IsoWorld;
import zombie.iso.LotHeader;
import zombie.iso.MapFiles;
import zombie.iso.worldgen.WorldGenParams;
import zombie.iso.worldgen.zones.ZoneGenerator;
import zombie.iso.zones.Zone;
import zombie.network.GameClient;
import zombie.network.GameServer;

/** Owned native-run probe. No generation, RNG, world registration, or filesystem writes. */
public final class Main {
    private static final String CELL_HASH = "ccf99cd2b176b079da51f31a74ae9408b45255a328f6d1ab6fe536600226cdee";
    private static final String GENERATOR_HASH = "10ed8c0fef67cdbf3a0f355f2142bf35e401df82e0578b473206f3baccafba29";
    private static final int MAX_COORDS = 16, MAX_MAPS = 256, MAX_ZONES = 8192, MAX_POINTS = 65536;
    private Main() { }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }
    private static boolean sameCache(String value, Path actual) {
        return value != null && Path.of(value).isAbsolute()
            && Path.of(value).toAbsolutePath().normalize().equals(actual);
    }
    private static void disposable() {
        Path actual = Path.of(ZomboidFileSystem.instance.getCacheDir()).toAbsolutePath().normalize();
        String client = System.getenv("PZ_LOT_QUAL_CACHE");
        require(client != null && Path.of(client).isAbsolute(), "Owned runner cache environment required");
        require(sameCache(client, actual) || GameServer.server
                && sameCache(System.getenv("PZ_LOT_QUAL_SERVER_CACHE"), actual), "Owned runner cache differs");
    }
    private static List<int[]> coordinates(String value) {
        require(value != null && value.length() <= 512 && !value.isBlank(), "Supply 1..16 x,y coordinates");
        String[] entries = value.split(";", -1);
        require(entries.length <= MAX_COORDS, "At most 16 coordinates");
        List<int[]> result = new ArrayList<>();
        for (String entry : entries) {
            require(entry.matches("-?[0-9]{1,6},-?[0-9]{1,6}"), "Coordinates must be x,y;x,y");
            String[] pair = entry.split(",");
            int x = Integer.parseInt(pair[0]), y = Integer.parseInt(pair[1]);
            require(Math.abs(x) <= 100000 && Math.abs(y) <= 100000, "Coordinate bound exceeded");
            result.add(new int[]{x, y});
        }
        return result;
    }
    private static Map<String, Object> object(Object... fields) {
        Map<String, Object> result = new LinkedHashMap<>();
        for (int i = 0; i < fields.length; i += 2) result.put((String)fields[i], fields[i + 1]);
        return result;
    }
    private static String json(Object value) {
        if (value == null) return "null";
        if (value instanceof Boolean || value instanceof Number) return value.toString();
        if (value instanceof Map<?, ?> map) {
            List<String> parts = new ArrayList<>();
            for (var entry : map.entrySet()) parts.add(json(entry.getKey().toString()) + ":" + json(entry.getValue()));
            return "{" + String.join(",", parts) + "}";
        }
        if (value instanceof Iterable<?> list) {
            List<String> parts = new ArrayList<>();
            for (Object item : list) parts.add(json(item));
            return "[" + String.join(",", parts) + "]";
        }
        StringBuilder out = new StringBuilder("\"");
        for (char c : value.toString().toCharArray()) {
            if (c == '"' || c == '\\') out.append('\\').append(c);
            else if (c < 32) out.append(String.format("\\u%04x", (int)c));
            else out.append(c);
        }
        return out.append('"').toString();
    }
    private static String hash(String text) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8)));
    }
    private static String resourceHash(Class<?> type) throws Exception {
        String name = type.getName().replace('.', '/') + ".class";
        try (var stream = type.getClassLoader().getResourceAsStream(name)) {
            require(stream != null, "Missing class resource " + name);
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(stream.readAllBytes()));
        }
    }
    private static Field field(Class<?> owner, String name) throws Exception {
        Field field = owner.getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }
    private static Object privateValue(Object owner, String name) throws Exception {
        return field(owner.getClass(), name).get(owner);
    }
    private static Map<String, Object> failed(Throwable error) {
        Throwable cause = error.getCause() == null ? error : error.getCause();
        return object("format", 1, "ok", false, "error", cause.getClass().getSimpleName() + ": " + cause.getMessage());
    }
    private static List<MapFiles> maps() {
        require(IsoLot.MapFiles.size() <= MAX_MAPS, "Registered map bound exceeded");
        return new ArrayList<>(IsoLot.MapFiles);
    }
    private static Map<String, Object> mapIdentity(MapFiles map) {
        return map == null ? null : object("directory", map.mapDirectoryName, "priority", map.priority,
            "identity", System.identityHashCode(map));
    }
    private static Map<String, Object> headerIdentity(LotHeader header) {
        return header == null ? null : object("identity", System.identityHashCode(header),
            "map", mapIdentity(header.mapFiles), "minLevel", header.minLevel, "maxLevel", header.maxLevel,
            "tilesUsed", header.tilesUsed.size());
    }
    private static Map<String, Object> bootstrap() throws Exception {
        try {
            Class<?> type = Class.forName("net.alexredby.pztoolkitbootstrap.LotLocks", false, IsoLot.class.getClassLoader());
            Object proof = type.getMethod("snapshot").invoke(null);
            Map<String, Object> result = object("available", true);
            for (String name : List.of("active", "state", "lotInputHash", "poolInputHash", "transformations"))
                result.put(name, proof.getClass().getMethod(name).invoke(proof));
            return result;
        } catch (ClassNotFoundException absent) { return object("available", false); }
    }
    private static Map<String, Object> runtime() throws Exception {
        List<Object> methods = new ArrayList<>(), registered = new ArrayList<>();
        for (Class<?> integer : List.of(int.class, Integer.class)) {
            Method get = IsoLot.class.getMethod("get", MapFiles.class, integer, integer, integer, integer, IsoChunk.class);
            methods.add(object("overload", integer == int.class ? "primitive" : "boxed",
                "modifiers", get.getModifiers(), "synchronized", Modifier.isSynchronized(get.getModifiers())));
        }
        List<MapFiles> maps = maps();
        for (int i = 0; i < maps.size(); i++) {
            MapFiles map = maps.get(i);
            Map<String, Object> item = mapIdentity(map);
            item.put("index", i); item.put("indexMatchesPriority", i == map.priority);
            item.put("headers", map.infoHeaders.size()); item.put("lotpacks", map.infoFileNames.size());
            registered.add(item);
        }
        return object("format", 1, "ok", true, "server", GameServer.server, "client", GameClient.client,
            "coop", GameServer.coop, "thread", Thread.currentThread().getName(), "seed", WorldGenParams.INSTANCE.getSeed(),
            "seedString", WorldGenParams.INSTANCE.getSeedString(), "getMethods", methods,
            "bootstrap", bootstrap(), "mapFiles", registered,
            "isoLotResourceSha256", resourceHash(IsoLot.class), "zoneGeneratorResourceSha256", resourceHash(ZoneGenerator.class));
    }
    @LuaMethod(name="lotQualRuntime", global=true)
    public static String lotQualRuntime() {
        try { disposable(); return json(runtime()); }
        catch (Exception | LinkageError error) { return json(failed(error)); }
    }

    private static Map<String, Object> geometry(AnimalZone zone) throws Exception {
        require(zone.points.size() <= MAX_POINTS, "Animal zone point bound exceeded");
        List<Integer> points = new ArrayList<>();
        for (int i = 0; i < zone.points.size(); i++) points.add(zone.points.getQuick(i));
        return object("name", zone.name, "type", zone.type, "originalName", zone.getOriginalName(),
            "animalType", privateValue(zone, "animalType"), "action", zone.action,
            "x", zone.x, "y", zone.y, "z", zone.z, "w", zone.w, "h", zone.h,
            "geometryType", String.valueOf(zone.geometryType), "polylineWidth", zone.polylineWidth, "points", points);
    }
    @LuaMethod(name="lotQualSnapshot", global=true)
    public static String lotQualSnapshot(String cells) {
        try {
            disposable();
            require(CELL_HASH.equals(resourceHash(IsoMetaCell.class)), "Unsupported native meta-cell persistence");
            var grid = IsoWorld.instance.getMetaGrid();
            require(grid != null, "Native meta grid required");
            Field generated = field(IsoMetaCell.class, "animalZonesGenerated");
            List<Object> observations = new ArrayList<>();
            int totalZones = 0, totalPoints = 0;
            for (int[] position : coordinates(cells)) {
                int x = position[0], y = position[1];
                IsoMetaCell cell = grid.getCellData(x, y); // Does not create or load a missing cell.
                Map<String, Object> item = object("x", x, "y", y, "presence", String.valueOf(grid.hasCellData(x, y)),
                    "loaded", cell != null);
                String headerKey = ChunkMapFilenames.instance.getHeader(x, y);
                item.put("selectedHeader", headerIdentity(IsoLot.InfoHeaders.get(headerKey)));
                List<Object> headers = new ArrayList<>();
                for (MapFiles map : maps()) {
                    LotHeader header = map.infoHeaders.get(headerKey);
                    if (header != null) headers.add(object("map", mapIdentity(map), "header", headerIdentity(header),
                        "selectedByGlobal", header == IsoLot.InfoHeaders.get(headerKey)));
                }
                item.put("authoredHeaders", headers);
                if (cell != null) {
                    boolean before = generated.getBoolean(cell);
                    int size = cell.getAnimalZonesSize();
                    require(size <= MAX_ZONES, "Animal zone count bound exceeded");
                    totalZones += size;
                    require(totalZones <= MAX_ZONES, "Snapshot total zone bound exceeded");
                    List<String> canonical = new ArrayList<>();
                    List<Object> dynamic = new ArrayList<>();
                    for (int i = 0; i < size; i++) {
                        AnimalZone zone = cell.getAnimalZone(i);
                        totalPoints += zone.points.size();
                        require(totalPoints <= 262144, "Snapshot total point bound exceeded");
                        String geometry = json(geometry(zone));
                        canonical.add(geometry);
                        dynamic.add(object("geometrySha256", hash(geometry), "id", zone.id == null ? null : zone.id.toString(),
                            "spawnedAnimals", privateValue(zone, "spawnedAnimals"), "spawnAnimal", privateValue(zone, "spawnAnimal"),
                            "hourLastSeen", zone.hourLastSeen, "lastActionTimestamp", zone.lastActionTimestamp));
                    }
                    Collections.sort(canonical);
                    // Native current-version serialization is exactly one generated flag byte.
                    ByteBuffer buffer = ByteBuffer.allocate(1);
                    cell.save(buffer);
                    int savedBytes = buffer.position();
                    buffer.flip();
                    IsoMetaCell detached = new IsoMetaCell(x, y);
                    detached.load(null, buffer, IsoWorld.getWorldVersion());
                    boolean restored = generated.getBoolean(detached);
                    item.put("generated", before); item.put("animalZones", size);
                    item.put("cellHeader", headerIdentity(cell.info));
                    item.put("geometrySha256", hash(json(canonical))); item.put("dynamicZones", dynamic);
                    item.put("generatedBitRoundtrip", object("savedBytes", savedBytes, "restored", restored,
                        "matches", restored == before, "consumedBytes", buffer.position(), "detachedZoneCount", detached.getAnimalZonesSize()));
                    require(generated.getBoolean(cell) == before && cell.getAnimalZonesSize() == size, "Live cell changed during snapshot");
                }
                observations.add(item);
            }
            return json(object("format", 1, "ok", true, "runtime", runtime(), "cells", observations,
                "geometryHashFormat", "sha256(UTF8(JSON(sorted canonical zone JSON strings))); fields defined by geometry(); UUID/spawn/runtime fields excluded",
                "persistenceScope", "generated bit only; detached memory roundtrip, not world save/reload"));
        } catch (Exception | LinkageError error) { return json(failed(error)); }
    }

    private static String payloadHash(IsoLot lot) throws Exception {
        require(lot.data.size() <= 1000000, "Native chunk payload bound exceeded");
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        ByteBuffer word = ByteBuffer.allocate(4);
        for (int i = 0; i < lot.data.size(); i++) {
            word.clear(); word.putInt(lot.data.getQuick(i)); digest.update(word.array());
        }
        return HexFormat.of().formatHex(digest.digest());
    }
    @LuaMethod(name="lotQualTreeCounts", global=true)
    public static String lotQualTreeCounts(String chunks) {
        try {
            disposable();
            require(GENERATOR_HASH.equals(resourceHash(ZoneGenerator.class)), "Unsupported native tree counter");
            require(IsoWorld.instance.getBiomeMap() != null, "Live biome map required");
            List<int[]> requested = coordinates(chunks);
            int nativeLoads = 0;
            for (int[] position : requested) for (MapFiles map : maps())
                if (map.hasCell(Math.floorDiv(position[0], 32), Math.floorDiv(position[1], 32))) nativeLoads++;
            require(nativeLoads <= 128, "Authored native layer load bound exceeded");
            // This instance owns its private tree cache. No method of the live generator is called.
            ZoneGenerator generator = new ZoneGenerator(IsoWorld.instance.getBiomeMap());
            Method trees = ZoneGenerator.class.getDeclaredMethod("getTrees", int.class, int.class);
            Method place = ZoneGenerator.class.getDeclaredMethod("PlaceLot", IsoLot.class, int.class, boolean[].class, boolean[].class);
            trees.setAccessible(true); place.setAccessible(true);
            List<Object> observations = new ArrayList<>();
            for (int[] position : requested) {
                int x = position[0], y = position[1], cx = Math.floorDiv(x, 32), cy = Math.floorDiv(y, 32);
                String headerKey = ChunkMapFilenames.instance.getHeader(cx, cy);
                LotHeader selected = IsoLot.InfoHeaders.get(headerKey);
                Map<String, Object> item = object("wx", x, "wy", y, "cellX", cx, "cellY", cy,
                    "selectedHeader", headerIdentity(selected), "trees", trees.invoke(generator, x, y));
                List<Object> layers = new ArrayList<>();
                for (MapFiles map : maps()) {
                    if (!map.hasCell(cx, cy)) continue;
                    IsoLot lot = null;
                    try {
                        lot = IsoLot.get(map, cx, cy, x, y, null);
                        require(lot != null && lot.info != null, "Native authored chunk failed to load");
                        boolean[] foundTrees = new boolean[64], occupied = new boolean[64];
                        int occupiedCount = (int)place.invoke(generator, lot, lot.minLevel, foundTrees, occupied);
                        int treeCount = 0;
                        for (boolean tree : foundTrees) if (tree) treeCount++;
                        layers.add(object("map", mapIdentity(map), "header", headerIdentity(lot.info),
                            "selectedByGlobal", lot.info == selected, "minLevel", lot.minLevel, "maxLevel", lot.maxLevel,
                            "occupiedSquares", occupiedCount, "standaloneTrees", treeCount,
                            "dataIntegers", lot.data.size(), "payloadSha256", payloadHash(lot)));
                    } finally { if (lot != null) IsoLot.put(lot); }
                }
                item.put("authoredLayers", layers); observations.add(item);
            }
            return json(object("format", 1, "ok", true, "runtime", runtime(), "chunks", observations,
                "scope", "getTrees on new generator; standalone native PlaceLot per layer; actual reads mutate only native file pool/private caches"));
        } catch (Exception | LinkageError error) { return json(failed(error)); }
    }
}

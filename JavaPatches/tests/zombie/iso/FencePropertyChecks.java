package zombie.iso;

import java.util.*;
import java.util.function.Consumer;
import java.nio.file.Files;
import java.nio.file.Path;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.PatchEngine;
import net.alexredby.pztoolkitjavapatches.FenceProperties;
import net.alexredby.pztoolkitjavapatches.Main;
import zombie.ai.states.ClimbOverFenceState;
import zombie.ai.states.GrappledThrownOverFenceState;
import zombie.ai.states.animals.AnimalClimbOverFenceState;
import zombie.core.TilePropertyAliasMap;
import zombie.core.properties.PropertyContainer;
import zombie.iso.SpriteDetails.IsoFlagType;
import zombie.iso.objects.IsoThumpable;
import zombie.iso.sprite.IsoSprite;
import zombie.iso.sprite.IsoSpriteManager;
import zombie.scripting.ScriptBucketCollection;
import zombie.scripting.ScriptLoadMode;
import zombie.scripting.ScriptManager;
import zombie.scripting.ScriptParser;
import zombie.scripting.objects.ScriptModule;

public final class FencePropertyChecks {
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }

    static Map<String, String> values(PropertyContainer properties) {
        var result = new TreeMap<String, String>();
        for (String key : properties.getPropertyNames()) result.put(key, properties.get(key));
        return result;
    }

    static Object aliases() {
        var aliases = TilePropertyAliasMap.instance;
        var result = new ArrayList<Object>();
        result.add(new HashMap<>(aliases.propertyToId));
        for (var property : aliases.properties)
            result.add(List.of(property.propertyName, new ArrayList<>(property.possibleValues), new HashMap<>(property.idMap)));
        return result;
    }

    static IsoSprite copy(IsoSprite source) {
        var result = new IsoSprite(); result.name = source.name;
        result.getProperties().AddProperties(source.getProperties());
        return result;
    }

    static List<Object> selectors(IsoSprite sprite) throws Exception {
        var object = new IsoObject(); object.setSprite(sprite);
        var result = new ArrayList<Object>();
        for (Object state : List.of(ClimbOverFenceState.instance(), AnimalClimbOverFenceState.instance(), GrappledThrownOverFenceState.instance())) {
            for (String name : List.of("getFenceType", "getTripType")) {
                var method = state.getClass().getDeclaredMethod(name, IsoObject.class); method.setAccessible(true);
                result.add(method.invoke(state, object));
            }
        }
        result.add(IsoThumpable.GetBreakFurnitureSound(sprite));
        return result;
    }

    static void unchanged(IsoSprite stock, Consumer<IsoSprite> modify, boolean supported) {
        var manager = new IsoSpriteManager(); var sprite = copy(stock); modify.accept(sprite);
        manager.namedMap.put(sprite.name, sprite);
        var properties = sprite.getProperties(); var before = values(properties); var flags = properties.getFlagsList();
        var maps = new HashMap<>(manager.namedMap); var alias = aliases();
        require(FenceProperties.tilesLoaded(manager, supported) == 0, "modified/unsupported fence corrected: " + before);
        require(properties == sprite.getProperties() && values(properties).equals(before)
            && properties.getFlagsList().equals(flags) && manager.namedMap.equals(maps) && aliases().equals(alias),
            "modified/unsupported fence or global metadata changed");
    }

    static void loadNativeTiles() throws Exception {
        Path entityFile = Path.of("media/scripts/generated/entities/walls/entity_wood_fencelvl3.txt");
        var block = ScriptParser.parse(Files.readString(entityFile)).getBlock("module", "Base");
        var body = new StringBuilder();
        block.getBlock("entity", "WoodFenceLvl3").prettyPrint(0, body);
        var module = new ScriptModule();
        ScriptManager.instance.moduleMap.put("Base", module);
        var entities = ScriptManager.class.getDeclaredField("entities"); entities.setAccessible(true);
        ((ScriptBucketCollection<?>)entities.get(ScriptManager.instance)).registerModule(module);
        Accessor.trySet(ScriptManager.class, "currentLoadFileMod", "pz-vanilla");
        Accessor.trySet(ScriptManager.class, "currentLoadFileAbsPath", entityFile.toAbsolutePath().toString());
        module.Load(ScriptLoadMode.Init, "Base", body.toString());
        module.entities.LoadScripts(ScriptLoadMode.Init);
        require(!module.entities.isHasLoadErrors()
            && ScriptManager.instance.getAllGameEntities().contains(module.entities.get("WoodFenceLvl3")),
            "native wooden fence entity did not load into script collection");
        String[] files = {"newtiledefinitions.tiles", "tiledefinitions_erosion.tiles", "tiledefinitions_overlays.tiles",
            "tiledefinitions_b42chunkcaching.tiles", "tiledefinitions_noiseworks.patch.tiles", "jumbo_trees_big.tiles", "jumbo_trees.tiles"};
        int[] ids = {1, 2, 4, 5, -1, 6, 8};
        var world = IsoWorld.instance; var manager = IsoSpriteManager.instance;
        for (int i = 0; i < files.length; i++) world.LoadTileDefinitionsPropertyStrings(manager, "media/" + files[i], ids[i]);
        var custom = IsoWorld.class.getDeclaredMethod("SetCustomPropertyValues");
        custom.setAccessible(true); custom.invoke(world);
        var generate = IsoWorld.class.getDeclaredMethod("GenerateTilePropertyLookupTables");
        generate.setAccessible(true); generate.invoke(world);
        for (int i = 0; i < files.length; i++) world.LoadTileDefinitions(manager, "media/" + files[i], ids[i]);
        require(FenceProperties.tilesLoaded(manager, true) == 0, "unbound tile metadata accepted");
        ScriptManager.instance.PostTileDefinitions();
        require(!zombie.entity.components.spriteconfig.SpriteConfigManager.HasLoadErrors(), "native entity sprite binding failed");
        for (String key : List.of("FenceTypeLow", "FenceTypeHigh", "ThumpSound", "EntityScriptName")) {
            var property = TilePropertyAliasMap.instance.properties.get(TilePropertyAliasMap.instance.getIDFromPropertyName(key));
            property.idMap.put("toolkit-custom", property.possibleValues.size()); property.possibleValues.add("toolkit-custom");
            property.idMap.put("", property.possibleValues.size()); property.possibleValues.add("");
        }
    }

    public static void main(String[] args) throws Exception {
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"));
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        zombie.network.GameServer.server = true;
        Main.main(new String[0]);
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", FencePropertyChecks.class.getClassLoader());
        require(Main.PROPERTY_SUPPORTED && Main.FENCE_SUPPORTED, "unsupported native property/fence bytecode");
        loadNativeTiles();
        var manager = IsoSpriteManager.instance;
        var west = manager.namedMap.get("carpentry_02_48"); var north = manager.namedMap.get("carpentry_02_49");
        require(west != null && north != null, "native fence tiles missing");
        var propertyIds = TilePropertyAliasMap.instance.propertyToId;
        int lowId = propertyIds.remove("FenceTypeLow");
        try { require(FenceProperties.tilesLoaded(manager, true) == 0, "missing alias accepted"); }
        finally { propertyIds.put("FenceTypeLow", lowId); }
        var woodAliases = TilePropertyAliasMap.instance.properties.get(lowId);
        int woodId = woodAliases.idMap.get("Wood");
        String wood = woodAliases.possibleValues.set(woodId, "toolkit-custom");
        try { require(FenceProperties.tilesLoaded(manager, true) == 0, "wrong alias value accepted"); }
        finally { woodAliases.possibleValues.set(woodId, wood); }
        for (var stock : List.of(west, north)) {
            require(!stock.getProperties().has("FenceTypeLow"), "native omission no longer exists");
            unchanged(stock, sprite -> { }, false);
            for (String property : List.of("FenceTypeLow", "FenceTypeHigh", "ThumpSound")) {
                unchanged(stock, sprite -> sprite.getProperties().set(property, "toolkit-custom"), true);
                unchanged(stock, sprite -> sprite.getProperties().set(property, ""), true);
            }
            unchanged(stock, sprite -> sprite.getProperties().set("FenceTypeLow", "Metal"), true);
            unchanged(stock, sprite -> sprite.getProperties().set("Material", "Metal"), true);
            unchanged(stock, sprite -> sprite.getProperties().unset("IsPaintable"), true);
            unchanged(stock, sprite -> sprite.getProperties().unset("EntityScriptName"), true);
            unchanged(stock, sprite -> sprite.getProperties().set("EntityScriptName", "toolkit-custom"), true);
            unchanged(stock, sprite -> sprite.getProperties().unset(IsoFlagType.EntityScript), true);
            unchanged(stock, sprite -> sprite.getProperties().set(IsoFlagType.solid), true);
            unchanged(stock, sprite -> sprite.getProperties().unset(stock == west ? IsoFlagType.canPathW : IsoFlagType.canPathN), true);
            unchanged(stock, sprite -> sprite.name = "toolkit-custom-fence", true);
        }
        var alias = aliases(); var named = new HashMap<>(manager.namedMap);
        var byId = new gnu.trove.map.hash.TIntObjectHashMap<>(manager.intMap);
        var westProperties = west.getProperties(); var northProperties = north.getProperties();
        var westBefore = values(westProperties); var northBefore = values(northProperties);
        var westFlags = westProperties.getFlagsList(); var northFlags = northProperties.getFlagsList();
        var westSelectors = selectors(west); var northSelectors = selectors(north);
        require(FenceProperties.tilesLoaded(manager, true) == 2, "stock two fences were not corrected");
        westBefore.put("FenceTypeLow", "Wood"); northBefore.put("FenceTypeLow", "Wood");
        require(west.getProperties() == westProperties && north.getProperties() == northProperties
            && values(westProperties).equals(westBefore) && values(northProperties).equals(northBefore)
            && westFlags.equals(westProperties.getFlagsList()) && northFlags.equals(northProperties.getFlagsList()),
            "stock properties/flags/container identities changed beyond FenceTypeLow");
        require(manager.namedMap.equals(named) && manager.intMap.equals(byId) && aliases().equals(alias), "sprite maps or aliases changed");
        require(selectors(west).equals(westSelectors) && selectors(north).equals(northSelectors),
            "native player/animal climb/trip or furniture break sound selector changed");
        require(FenceProperties.tilesLoaded(manager, true) == 0, "repeat correction changed stock metadata");
        require(FenceProperties.tilesLoaded(null, true) == 0, "null manager accepted");
        System.out.println("FENCE_PROPERTY_CHECKS_PASS (native seven tile files; two exact stock sprites corrected; player/animal/grapple climb/trip and furniture break selectors preserved; custom/empty/modified/unknown/unsupported sprites and missing/wrong aliases rejected; flags, map/container identities and aliases preserved)");
    }
}

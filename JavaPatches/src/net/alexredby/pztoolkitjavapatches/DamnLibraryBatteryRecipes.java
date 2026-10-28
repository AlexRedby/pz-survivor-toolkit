package net.alexredby.pztoolkitjavapatches;

import java.io.IOException;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Map;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.ZomboidFileSystem;
import zombie.gameStates.ChooseGameInfo;
import zombie.scripting.ScriptLoadMode;
import zombie.scripting.ScriptManager;
import zombie.scripting.ScriptBucket;
import zombie.scripting.ScriptBucketCollection;
import zombie.scripting.entity.components.crafting.CraftRecipe;
import zombie.scripting.objects.ScriptModule;

/** Retire two reviewed duplicates before registration; Workshop input stays unchanged. */
public final class DamnLibraryBatteryRecipes {
    public static final String TARGET = "media/scripts/damnCraft/recipes_damnCraft.txt";
    public static final String SOURCE_SHA256 = "0f26406851c62525a913a2e41ead186b43591993c5ad3547f3249274a61b6c93";
    public static final String INSERT = "damnCraftInsertBatteryIntoPlasticWeldingGun";
    public static final String REMOVE = "damnCraftRemoveBatteryFromPlasticWeldingGun";
    public static final boolean SUPPORTED =
        BytecodeSupport.supports("zombie/scripting/objects/ScriptModule.class", "10606317c7d84eb1b5c0df06a27687803aaefbc13e7d7148e99c6d9074442856")
        && BytecodeSupport.supports("zombie/scripting/ScriptManager.class", "8aee81a03fb7c09a9e9844ba9388a943aef9b313ea00017b8f2a33f16f4f0f99")
        && BytecodeSupport.supports("zombie/scripting/ScriptParser.class", "5f33328e2551fd40797697c15a9381b770fb547ac027f199e7dfc9172ac78f87")
        && BytecodeSupport.supports("zombie/scripting/ScriptBucket.class", "dc7a234f0d1fb162ef6b6ce316f16d13d87a52a93d863016abc7a7b9ba41d4dc")
        && BytecodeSupport.supports("zombie/scripting/ScriptBucket$LoadData.class", "9e84d8049c93c4e5140fe7aaec7ed9873cff513ec92c5f7949de88540facad33")
        && BytecodeSupport.supports("zombie/scripting/ScriptBucketCollection.class", "61ba45ea197992413af259c3736820d1669a5678f577f661956d0c3e8fbf9781")
        && BytecodeSupport.supports("zombie/scripting/ScriptType.class", "ed05efd72d87dbfa5e8bfc5831121290a0b377acdbb1cb694eb2d8f8e4b2bfdd")
        && BytecodeSupport.supports("zombie/scripting/objects/BaseScriptObject.class", "65d5f2bae0552d7a4ceaf24fb1124a57b93ae33b98d5afa8e0f5766d9bcbf666")
        && BytecodeSupport.supports("zombie/scripting/entity/components/crafting/CraftRecipe.class", "a5c076d53e68f5cdfcc5bc17239aee1fb2072766471c29070ca84b30bd63c5de")
        && BytecodeSupport.supports("zombie/ZomboidFileSystem.class", "c4e5a5123bc43d03f2585c40f37544c50c1e702eebceb78bec94069e410b6750")
        && BytecodeSupport.supports("zombie/gameStates/ChooseGameInfo.class", "8c4b47ba966f071120feeec090202967e414246e28b5b6fd6a622a6a266af651")
        && BytecodeSupport.supports("zombie/gameStates/ChooseGameInfo$Mod.class", "c91e48400b77015c450a696f2d7c5665fa872f1a76fc05d2c38e72ba2928dc69");

    private DamnLibraryBatteryRecipes() { }

    public static boolean skip(ScriptModule module, ScriptLoadMode mode, String token, boolean supported) {
        if (!supported || module == null || !"Base".equals(module.getName()) || token == null
                || (mode != ScriptLoadMode.Init && mode != ScriptLoadMode.Reload)) return false;
        String body = token.trim();
        String fingerprint;
        String name;
        if (body.startsWith("craftRecipe " + INSERT + "\n")) {
            name = INSERT;
            fingerprint = "67616654ea67a21aa7f2efcb026700eaa59439c010292ef5522fbb935b0af3ed";
        } else if (body.startsWith("craftRecipe " + REMOVE + "\n")) {
            name = REMOVE;
            fingerprint = "9b28dd4f567ae0046b5b082af407fa5d18ad62b9e27a2417f289ceaa385f8855";
        } else return false;
        if (!fingerprint.equals(sha256(body.getBytes(StandardCharsets.UTF_8)))
                || !"damnlib".equals(ScriptManager.getCurrentLoadFileMod())
                || !"recipes_damnCraft.txt".equals(ScriptManager.getCurrentLoadFileName())) return false;
        try {
            ZomboidFileSystem files = ZomboidFileSystem.instance;
            if (!files.getModIDs().contains("damnlib")) return false;
            ChooseGameInfo.Mod mod = ChooseGameInfo.getModDetails("damnlib");
            String loading = ScriptManager.getCurrentLoadFileAbsPath();
            if (mod == null || mod.getVersionDir() == null || loading == null) return false;
            Path expected = Path.of(mod.getVersionDir()).resolve(TARGET);
            // The source hash also guards the reviewed callback/input contract. Reading only
            // these two candidate tokens keeps unrelated script loading outside this work.
            boolean reviewed = Files.isRegularFile(expected) && Files.size(expected) <= 1024 * 1024
                && Files.isSameFile(expected, Path.of(loading))
                && Files.isSameFile(expected, Path.of(files.getAbsolutePath(TARGET)))
                && SOURCE_SHA256.equals(sha256(Files.readAllBytes(expected)));
            return reviewed && (mode != ScriptLoadMode.Reload || retirePrevious(module, name, fingerprint));
        } catch (IOException | RuntimeException error) {
            return false;
        }
    }

    private static Field field(Class<?> type, String name) {
        try {
            Field result = type.getDeclaredField(name);
            result.setAccessible(true);
            return result;
        } catch (ReflectiveOperationException | RuntimeException error) {
            return null;
        }
    }

    private static final class ReloadFields {
        static final Field DATA = field(ScriptBucket.class, "loadData");
        static final Field COLLECTION = field(ScriptManager.class, "craftRecipes");
        static final Field RELOADED;
        static final Field SCRIPT;
        static {
            Class<?> type;
            try { type = Class.forName("zombie.scripting.ScriptBucket$LoadData"); }
            catch (ClassNotFoundException error) { type = null; }
            RELOADED = type == null ? null : field(type, "reloaded");
            SCRIPT = type == null ? null : field(type, "script");
        }
    }

    /** Native reload retains removed definitions. Erase only a proven old DAMN object and
     * its discovery record so a later unknown source uses native added-on-reload handling. */
    private static boolean retirePrevious(ScriptModule module, String name, String fingerprint) {
        if (ReloadFields.DATA == null || ReloadFields.COLLECTION == null
                || ReloadFields.RELOADED == null || ReloadFields.SCRIPT == null) return false;
        try {
            var bucket = module.craftRecipes;
            Map<?, ?> data = (Map<?, ?>) ReloadFields.DATA.get(bucket);
            Object record = data.get(name);
            if (record == null || ReloadFields.RELOADED.getBoolean(record)) return true;
            Object script = ReloadFields.SCRIPT.get(record);
            if (!(script instanceof CraftRecipe previous)) return false;
            var bodies = previous.getLoadedScriptBodies();
            // An unrecognized or foreign prior definition stays on the native reload path.
            // In particular, never delete it before its provider's reload turn.
            if (bodies.size() != 2 || !"damnlib".equals(bodies.get(0))
                    || !fingerprint.equals(sha256(bodies.get(1).trim().getBytes(StandardCharsets.UTF_8)))) return false;
            if (bucket.getScriptMap().get(name) != previous) return false;
            var collection = (ScriptBucketCollection<?>) ReloadFields.COLLECTION.get(ScriptManager.instance);
            String fullType = previous.getScriptObjectFullType();
            if (collection.getFullTypeToScriptMap().get(fullType) != previous) return false;
            // All references and fingerprints were checked before changing any registry.
            data.remove(name, record);
            bucket.getScriptMap().remove(name, previous);
            bucket.getScriptList().removeIf(value -> value == previous);
            collection.getFullTypeToScriptMap().remove(fullType, previous);
            return true;
        } catch (IllegalAccessException | RuntimeException error) {
            return false;
        }
    }

    private static String sha256(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (NoSuchAlgorithmException error) {
            throw new AssertionError(error);
        }
    }

    @Patch(className="zombie.scripting.objects.ScriptModule", methodName="CreateFromTokenPP", warmUp=true, strictMatch=true)
    public static class NativeRecipeDiscovery {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This ScriptModule module, @Patch.Argument(0) ScriptLoadMode mode,
                                    @Patch.Argument(1) String token) {
            return DamnLibraryBatteryRecipes.skip(module, mode, token, SUPPORTED);
        }
    }
}

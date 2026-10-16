package zombie.scripting.entity.components.crafting;

import java.io.ByteArrayOutputStream;
import java.lang.reflect.Modifier;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import javax.imageio.ImageIO;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.PatchEngine;
import net.alexredby.pztoolkitjavapatches.Main;
import net.alexredby.pztoolkitjavapatches.PianoIcon;
import zombie.GameWindow;
import zombie.ZomboidFileSystem;
import zombie.asset.AssetManagers;
import zombie.core.textures.Texture;
import zombie.core.textures.TextureAssetManager;
import zombie.core.textures.TextureID;
import zombie.core.textures.TextureIDAssetManager;
import zombie.debug.DebugLog;
import zombie.debug.DebugType;
import zombie.debug.LogSeverity;
import zombie.entity.ComponentType;
import zombie.fileSystem.FileSystem;
import zombie.fileSystem.FileSystemImpl;
import zombie.scripting.ScriptManager;
import zombie.scripting.ScriptParser;
import zombie.scripting.ScriptLoadMode;
import zombie.scripting.entity.GameEntityScript;
import zombie.scripting.entity.components.spriteconfig.SpriteConfigScript;
import zombie.scripting.objects.ScriptModule;

public final class PianoChecks {
    static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    static String body() throws Exception {
        var block = ScriptParser.parse(Files.readString(Path.of("media/scripts/generated/entities/admin/entity_piano.txt")))
            .getBlock("module", "Base").getBlock("entity", "Piano");
        var text = new StringBuilder();
        block.prettyPrint(0, text);
        return text.toString();
    }

    static GameEntityScript load(String body, String module, String name, String mod) throws Exception {
        var script = new GameEntityScript();
        var scriptModule = new ScriptModule();
        scriptModule.name = module;
        script.setModule(scriptModule);
        Accessor.trySet(ScriptManager.class, "currentLoadFileMod", mod);
        script.InitLoadPP(name);
        script.Load(name, body);
        return script;
    }

    static CraftRecipeComponentScript recipe(GameEntityScript script) {
        return script.getComponentScriptFor(ComponentType.CraftRecipe);
    }

    static GameEntityScript nativeLoader(String body) {
        Accessor.trySet(ScriptManager.class, "currentLoadFileMod", "pz-vanilla");
        Accessor.trySet(ScriptManager.class, "currentLoadFileAbsPath",
            Path.of("media/scripts/generated/entities/admin/entity_piano.txt").toAbsolutePath().toString());
        var module = new ScriptModule();
        module.Load(ScriptLoadMode.Init, "Base", body);
        module.entities.LoadScripts(ScriptLoadMode.Init);
        require(!module.entities.isHasLoadErrors(), "native module/bucket loader failed");
        return module.entities.get("Piano");
    }

    static String repeatedStage(CraftRecipeComponentScript component) throws Exception {
        try {
            component.OnScriptsLoaded(ScriptLoadMode.Init);
            throw new AssertionError("native duplicate Prop1 validation was bypassed");
        } catch (java.io.IOException error) {
            return error.getClass().getName() + ":" + error.getMessage();
        }
    }

    static Map<String, Object> state(Object object, String... ignored) throws Exception {
        var result = new HashMap<String, Object>();
        for (Class<?> type = object.getClass(); type != Object.class; type = type.getSuperclass()) {
            for (var field : type.getDeclaredFields()) {
                if (Modifier.isStatic(field.getModifiers()) || java.util.List.of(ignored).contains(field.getName())) continue;
                field.setAccessible(true);
                Object value = field.get(object);
                if (value instanceof java.util.List<?> list) value = new ArrayList<>(list);
                if (value instanceof Map<?, ?> map) value = new HashMap<>(map);
                result.put(type.getName() + "." + field.getName(), value);
            }
        }
        return result;
    }

    static void setup() throws Exception {
        ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"));
        ZomboidFileSystem.instance.init();
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        zombie.world.WorldDictionary.StartScriptLoading();
        GameWindow.fileSystem = new FileSystemImpl();
        GameWindow.assetManagers = new AssetManagers(GameWindow.fileSystem);
        TextureAssetManager.instance.create(Texture.ASSET_TYPE, GameWindow.assetManagers);
        TextureIDAssetManager.instance.create(TextureID.ASSET_TYPE, GameWindow.assetManagers);
        var initialized = zombie.core.opengl.RenderThread.class.getDeclaredField("isInitialized");
        initialized.setAccessible(true);
        initialized.setBoolean(null, true);
        var entries = new FileSystem.TexturePackTextures();
        GameWindow.fileSystem.mountTexturePack("Tiles2x", entries, 0);
        GameWindow.texturePackTextures.put(PianoIcon.TILE, entries.get(PianoIcon.TILE));
    }

    static void finish() throws Exception {
        long deadline = System.nanoTime() + 10_000_000_000L;
        while (GameWindow.fileSystem.hasWork() && System.nanoTime() < deadline) {
            GameWindow.fileSystem.updateAsyncTransactions();
            Thread.sleep(1);
        }
        require(!GameWindow.fileSystem.hasWork(), "native texture jobs timed out");
    }

    static void pixels(Texture texture) throws Exception {
        var entry = GameWindow.texturePackTextures.get(PianoIcon.TILE);
        try (var stream = GameWindow.fileSystem.openStream(
                GameWindow.fileSystem.getTexturePackDevice(entry.packName), entry.pageName)) {
            var png = ImageIO.read(stream);
            var data = texture.getTextureId().getImageData();
            require(data != null, "real tile pixels unavailable");
            int x = Math.round(texture.xStart * texture.getWidthHW());
            int y = Math.round(texture.yStart * texture.getHeightHW());
            require(x == entry.info.x && y == entry.info.y && texture.getWidth() == entry.info.w
                && texture.getHeight() == entry.info.h, "tile atlas region changed");
            ByteBuffer pixels = data.getData().getBuffer();
            int opaque = 0;
            for (int dy = 0; dy < texture.getHeight(); dy++) {
                for (int dx = 0; dx < texture.getWidth(); dx++) {
                    int offset = ((y + dy) * data.getWidthHW() + x + dx) * 4;
                    int argb = png.getRGB(x + dx, y + dy);
                    int alpha = Byte.toUnsignedInt(pixels.get(offset + 3));
                    require(alpha == argb >>> 24, "native tile alpha differs from PNG");
                    if (alpha != 0) {
                        require(Byte.toUnsignedInt(pixels.get(offset)) == ((argb >>> 16) & 255)
                            && Byte.toUnsignedInt(pixels.get(offset + 1)) == ((argb >>> 8) & 255)
                            && Byte.toUnsignedInt(pixels.get(offset + 2)) == (argb & 255), "native tile color differs");
                        opaque++;
                    }
                }
            }
            require(opaque > 0, "native tile is transparent");
        }
    }

    public static void main(String[] args) throws Exception {
        setup();
        try {
            var log = new ByteArrayOutputStream();
            var logger = DebugLog.getInstance();
            DebugType.General.setLogSeverity(LogSeverity.Error);
            logger.setStdOut(log);
            logger.setStdErr(log);
            String body = body();
            var original = nativeLoader(body);
            require(original != null, "native source caller did not load Piano");
            recipe(original).OnScriptsLoaded(ScriptLoadMode.Init);
            SpriteConfigScript sprites = original.getComponentScriptFor(ComponentType.SpriteConfig);
            require(sprites.getAllTileNames().get(0).equals(PianoIcon.TILE), "native fallback tile changed");
            Texture baseline = recipe(original).getIconTexture();
            require(!baseline.isReady(), "cold atlas unexpectedly decoded before async transactions");
            PianoIcon.loaded(original, body, true);
            require(PianoIcon.resolve(recipe(original), true) == baseline, "pending native texture was rejected");
            finish();
            require(baseline != null && baseline.isReady(), "native fallback did not load real tile");
            require(log.toString().contains("Recipe Piano missing UiConfigScript"), "native diagnostic missing");
            pixels(baseline);
            var nativeRepeated = load(body, "Base", "Piano", "pz-vanilla");
            recipe(nativeRepeated).OnScriptsLoaded(ScriptLoadMode.Init);
            String nativeFailure = repeatedStage(recipe(nativeRepeated));
            var iconProbe = new CraftRecipe();
            iconProbe.Load("Piano", ScriptParser.parse("component CraftRecipe { Icon = " + PianoIcon.TILE + ", }")
                .getBlock("component", "CraftRecipe"));
            iconProbe.OnScriptsLoaded(ScriptLoadMode.Init);
            require(iconProbe.getIconName().equals("Item_" + PianoIcon.TILE) && iconProbe.getIconTexture() == null,
                "native item-only icon path changed");
            zombie.network.GameServer.server = true;
            try {
                var serverOriginal = load(body, "Base", "Piano", "pz-vanilla");
                log.reset();
                require(recipe(serverOriginal).getIconTexture() == null
                    && log.toString().contains("Recipe Piano missing UiConfigScript"),
                    "native dedicated null/diagnostic changed");
            } finally {
                zombie.network.GameServer.server = false;
            }

            PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", PianoChecks.class.getClassLoader());
            require(Main.PIANO_SUPPORTED, "unsupported native Piano bytecode");
            require(!Main.supports("zombie/scripting/entity/components/crafting/CraftRecipe.class", "unknown"),
                "unknown native icon parser fingerprint accepted");
            var woven = nativeLoader(body);
            var component = recipe(woven);
            var initialState = state(component.getCraftRecipe(), "iconName", "iconTexture");
            require(component.getIconTexture() == baseline, "early getter changed native texture");
            require(state(component.getCraftRecipe(), "iconName", "iconTexture").equals(initialState),
                "early correction changed nonicon recipe fields");
            component.OnScriptsLoaded(ScriptLoadMode.Init);
            require(component.getCraftRecipe().getIconName().equals(PianoIcon.TILE)
                && component.getCraftRecipe().getIconTexture() == baseline,
                "first native script stage prefixed or cleared world icon");
            var gameState = state(woven);
            var spriteState = state(woven.getComponentScriptFor(ComponentType.SpriteConfig));
            var recipeState = state(component.getCraftRecipe(), "iconName", "iconTexture");
            log.reset();
            require(component.getIconTexture() == baseline, "woven icon differs from real native fallback");
            require(!log.toString().contains("missing UiConfigScript"), "woven native recipe still diagnoses missing icon");
            require(component.getCraftRecipe().getIconName().equals(PianoIcon.TILE)
                && component.getCraftRecipe().getIconTexture() == baseline, "explicit recipe metadata was not corrected");
            require(state(woven).equals(gameState) && state(woven.getComponentScriptFor(ComponentType.SpriteConfig)).equals(spriteState)
                && state(component.getCraftRecipe(), "iconName", "iconTexture").equals(recipeState),
                "world components/name/creation fields or recipe gameplay data changed");
            require(!woven.containsComponent(ComponentType.UiConfig) && woven.getComponentScripts().size() == 2,
                "UI/save component set changed");
            require(component.getIconTexture() == baseline, "repeat icon resolution is not idempotent");
            require(repeatedStage(component).equals(nativeFailure), "native validation exception changed");
            require(component.getCraftRecipe().getIconName().equals(PianoIcon.TILE)
                && component.getCraftRecipe().getIconTexture() == baseline,
                "exceptional script stage did not restore icon metadata and texture");
            require(PianoIcon.resolve(component, false) == null, "unsupported resolver enabled");
            require(PianoIcon.beginScripts(component.getCraftRecipe(), false) == null, "unsupported stage guard enabled");
            var foreignResult = new java.util.concurrent.atomic.AtomicReference<Texture>();
            var foreignError = new java.util.concurrent.atomic.AtomicReference<Throwable>();
            var foreign = new Thread(() -> {
                try { foreignResult.set(PianoIcon.resolve(component, true)); }
                catch (Throwable error) { foreignError.set(error); }
            });
            foreign.start();
            foreign.join();
            require(foreignResult.get() == null && foreignError.get() == null, "foreign thread modified recipe metadata");

            woven.PreReload();
            woven.Load("Piano", body);
            var reloaded = recipe(woven);
            reloaded.OnScriptsLoaded(ScriptLoadMode.Reload);
            require(reloaded.getIconTexture() == baseline, "native reload lost the icon correction");
            require(reloaded.getCraftRecipe().getIconName().equals(PianoIcon.TILE), "reloaded metadata missing");

            for (String changed : new String[]{body.replace("time = 10", "time = 11"),
                    body.replace("recreational_01_28", "recreational_01_13"),
                    body.replace("component CraftRecipe", "component UiConfig { xuiSkin = default, entityStyle = Custom, uiEnabled = true, }\ncomponent CraftRecipe"),
                    body.replace("time = 10", "Icon = CustomIcon, time = 10")}) {
                var custom = load(changed, "Base", "Piano", "pz-vanilla");
                require(PianoIcon.resolve(recipe(custom), true) == null, "changed native data accepted");
            }
            for (String[] identity : new String[][]{{"Mod", "Piano", "pz-vanilla"}, {"Base", "Other", "pz-vanilla"},
                    {"Base", "Piano", "custom-mod"}}) {
                var custom = load(body, identity[0], identity[1], identity[2]);
                require(PianoIcon.resolve(recipe(custom), true) == null, "custom entity identity accepted");
            }
            var unknown = load(body.replace("entity Piano", "entity Unknown"), "Base", "Unknown", "pz-vanilla");
            log.reset();
            recipe(unknown).getIconTexture();
            require(log.toString().contains("missing UiConfigScript"), "unknown native diagnostic suppressed");
            zombie.network.GameServer.server = true;
            try {
                var dedicated = load(body, "Base", "Piano", "pz-vanilla");
                int atlasSize = GameWindow.texturePackTextures.size();
                var dedicatedState = state(dedicated);
                var dedicatedRecipeState = state(recipe(dedicated).getCraftRecipe());
                log.reset();
                require(recipe(dedicated).getIconTexture() == null && Texture.getSharedTexture(PianoIcon.TILE) == null,
                    "dedicated server manufactured a UI texture");
                require(recipe(dedicated).getCraftRecipe().getIconName() == null
                    && !log.toString().contains("Recipe Piano missing UiConfigScript")
                    && state(dedicated).equals(dedicatedState)
                    && state(recipe(dedicated).getCraftRecipe()).equals(dedicatedRecipeState),
                    "dedicated server retained unnecessary UI error or changed native metadata");
                require(GameWindow.texturePackTextures.size() == atlasSize && !GameWindow.fileSystem.hasWork(),
                    "dedicated icon lookup loaded UI assets");
                var dedicatedUnknown = load(body.replace("entity Piano", "entity Unknown"), "Base", "Unknown", "pz-vanilla");
                log.reset();
                require(recipe(dedicatedUnknown).getIconTexture() == null
                    && log.toString().contains("Recipe Unknown missing UiConfigScript"),
                    "unknown dedicated diagnostic was suppressed");
                require(!PianoIcon.headless(recipe(dedicated), false), "unsupported dedicated guard enabled");
                for (String changed : new String[]{body.replace("time = 10", "time = 11"),
                        body.replace("time = 10", "Icon = CustomIcon, time = 10"),
                        body.replace("component CraftRecipe", "component UiConfig { entityStyle = Custom, }\ncomponent CraftRecipe")}) {
                    var custom = load(changed, "Base", "Piano", "pz-vanilla");
                    require(!PianoIcon.headless(recipe(custom), true), "custom dedicated data accepted");
                }
            } finally {
                zombie.network.GameServer.server = false;
            }
            var missing = load(body, "Base", "Piano", "pz-vanilla");
            Texture.forgetTexture(PianoIcon.TILE);
            GameWindow.texturePackTextures.remove(PianoIcon.TILE);
            require(PianoIcon.resolve(recipe(missing), true) == null, "missing native texture accepted");
            require(recipe(missing).getCraftRecipe().getIconName() == null, "missing texture invented metadata");
            logger.setStdOut(System.out);
            logger.setStdErr(System.err);
            System.out.println("PIANO_CHECKS_PASS (native loader/error, same real tile/UV/pixels, early getter, first script stage, native exception restoration, reload, unchanged world/recipe fields, custom/thread/unsupported guards)");
        } catch (Throwable error) {
            error.printStackTrace(System.err);
            System.exit(1);
        }
        System.exit(0);
    }
}

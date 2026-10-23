package zombie.scripting.entity.components.crafting

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.lang.reflect.Modifier
import java.nio.file.Files
import java.nio.file.Path
import java.util.ArrayList
import java.util.HashMap
import java.util.concurrent.atomic.AtomicReference
import javax.imageio.ImageIO
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.BytecodeSupport
import net.alexredby.pztoolkitjavapatches.PianoIcon
import zombie.GameWindow
import zombie.ZomboidFileSystem
import zombie.asset.AssetManagers
import zombie.core.textures.Texture
import zombie.core.textures.TextureAssetManager
import zombie.core.textures.TextureID
import zombie.core.textures.TextureIDAssetManager
import zombie.debug.DebugLog
import zombie.debug.DebugType
import zombie.debug.LogSeverity
import zombie.entity.ComponentType
import zombie.fileSystem.FileSystem
import zombie.fileSystem.FileSystemImpl
import zombie.scripting.ScriptLoadMode
import zombie.scripting.ScriptManager
import zombie.scripting.ScriptParser
import zombie.scripting.entity.GameEntityScript
import zombie.scripting.entity.components.spriteconfig.SpriteConfigScript
import zombie.scripting.objects.ScriptModule

object PianoChecks {
    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun body(): String {
        val block = ScriptParser.parse(Files.readString(Path.of("media/scripts/generated/entities/admin/entity_piano.txt")))
            .getBlock("module", "Base").getBlock("entity", "Piano")
        val text = StringBuilder()
        block.prettyPrint(0, text)
        return text.toString()
    }

    private fun load(body: String, module: String, name: String, mod: String): GameEntityScript {
        val script = GameEntityScript()
        val scriptModule = ScriptModule()
        scriptModule.name = module
        script.setModule(scriptModule)
        Accessor.trySet(ScriptManager::class.java, "currentLoadFileMod", mod)
        script.InitLoadPP(name)
        script.Load(name, body)
        return script
    }

    private fun recipe(script: GameEntityScript): CraftRecipeComponentScript =
        script.getComponentScriptFor(ComponentType.CraftRecipe)

    private fun nativeLoader(body: String): GameEntityScript? {
        Accessor.trySet(ScriptManager::class.java, "currentLoadFileMod", "pz-vanilla")
        Accessor.trySet(ScriptManager::class.java, "currentLoadFileAbsPath",
            Path.of("media/scripts/generated/entities/admin/entity_piano.txt").toAbsolutePath().toString())
        val module = ScriptModule()
        module.Load(ScriptLoadMode.Init, "Base", body)
        module.entities.LoadScripts(ScriptLoadMode.Init)
        require(!module.entities.isHasLoadErrors, "native module/bucket loader failed")
        return module.entities.get("Piano")
    }

    private fun repeatedStage(component: CraftRecipeComponentScript): String {
        try {
            component.OnScriptsLoaded(ScriptLoadMode.Init)
            throw AssertionError("native duplicate Prop1 validation was bypassed")
        } catch (error: IOException) {
            return error.javaClass.name + ":" + error.message
        }
    }

    private fun state(instance: Any, vararg ignored: String): Map<String, Any?> {
        val result = HashMap<String, Any?>()
        var type: Class<*> = instance.javaClass
        while (type != Any::class.java) {
            for (field in type.declaredFields) {
                if (Modifier.isStatic(field.modifiers) || ignored.contains(field.name)) continue
                field.isAccessible = true
                var value = field.get(instance)
                if (value is List<*>) value = ArrayList(value)
                if (value is Map<*, *>) value = HashMap(value)
                result[type.name + "." + field.name] = value
            }
            type = type.superclass
        }
        return result
    }

    private fun setup() {
        ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        ZomboidFileSystem.instance.init()
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        zombie.world.WorldDictionary.StartScriptLoading()
        GameWindow.fileSystem = FileSystemImpl()
        GameWindow.assetManagers = AssetManagers(GameWindow.fileSystem)
        TextureAssetManager.instance.create(Texture.ASSET_TYPE, GameWindow.assetManagers)
        TextureIDAssetManager.instance.create(TextureID.ASSET_TYPE, GameWindow.assetManagers)
        val initialized = zombie.core.opengl.RenderThread::class.java.getDeclaredField("isInitialized").apply { isAccessible = true }
        initialized.setBoolean(null, true)
        val entries = FileSystem.TexturePackTextures()
        GameWindow.fileSystem.mountTexturePack("Tiles2x", entries, 0)
        GameWindow.texturePackTextures.put(PianoIcon.TILE, entries.get(PianoIcon.TILE))
    }

    private fun finish() {
        val deadline = System.nanoTime() + 10_000_000_000L
        while (GameWindow.fileSystem.hasWork() && System.nanoTime() < deadline) {
            GameWindow.fileSystem.updateAsyncTransactions()
            Thread.sleep(1)
        }
        require(!GameWindow.fileSystem.hasWork(), "native texture jobs timed out")
    }

    private fun pixels(texture: Texture) {
        val entry = GameWindow.texturePackTextures.get(PianoIcon.TILE) ?: throw NullPointerException()
        GameWindow.fileSystem.openStream(
            GameWindow.fileSystem.getTexturePackDevice(entry.packName), entry.pageName).use { stream ->
            val png = ImageIO.read(stream)
            val data = texture.getTextureId().getImageData()
            require(data != null, "real tile pixels unavailable")
            val x = Math.round(texture.xStart * texture.getWidthHW())
            val y = Math.round(texture.yStart * texture.getHeightHW())
            require(x == entry.info.x && y == entry.info.y && texture.width == entry.info.w
                && texture.height == entry.info.h, "tile atlas region changed")
            val pixels = data.getData().getBuffer()
            var opaque = 0
            for (dy in 0 until texture.height) {
                for (dx in 0 until texture.width) {
                    val offset = ((y + dy) * data.getWidthHW() + x + dx) * 4
                    val argb = png.getRGB(x + dx, y + dy)
                    val alpha = java.lang.Byte.toUnsignedInt(pixels.get(offset + 3))
                    require(alpha == (argb ushr 24), "native tile alpha differs from PNG")
                    if (alpha != 0) {
                        require(java.lang.Byte.toUnsignedInt(pixels.get(offset)) == ((argb ushr 16) and 255)
                            && java.lang.Byte.toUnsignedInt(pixels.get(offset + 1)) == ((argb ushr 8) and 255)
                            && java.lang.Byte.toUnsignedInt(pixels.get(offset + 2)) == (argb and 255), "native tile color differs")
                        opaque++
                    }
                }
            }
            require(opaque > 0, "native tile is transparent")
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        setup()
        try {
            val log = ByteArrayOutputStream()
            val logger = DebugLog.getInstance()
            DebugType.General.setLogSeverity(LogSeverity.Error)
            logger.setStdOut(log)
            logger.setStdErr(log)
            val body = body()
            val original = nativeLoader(body)
                ?: throw AssertionError("native source caller did not load Piano")
            recipe(original).OnScriptsLoaded(ScriptLoadMode.Init)
            val sprites = original.getComponentScriptFor<SpriteConfigScript>(ComponentType.SpriteConfig)
            require(sprites.allTileNames[0] == PianoIcon.TILE, "native fallback tile changed")
            val baseline = recipe(original).iconTexture
            require(!baseline.isReady, "cold atlas unexpectedly decoded before async transactions")
            PianoIcon.loaded(original, body, true)
            require(PianoIcon.resolve(recipe(original), true) === baseline, "pending native texture was rejected")
            finish()
            require(baseline != null && baseline.isReady, "native fallback did not load real tile")
            require(log.toString().contains("Recipe Piano missing UiConfigScript"), "native diagnostic missing")
            pixels(baseline)
            val nativeRepeated = load(body, "Base", "Piano", "pz-vanilla")
            recipe(nativeRepeated).OnScriptsLoaded(ScriptLoadMode.Init)
            val nativeFailure = repeatedStage(recipe(nativeRepeated))
            val iconProbe = CraftRecipe()
            iconProbe.Load("Piano", ScriptParser.parse("component CraftRecipe { Icon = ${PianoIcon.TILE}, }")
                .getBlock("component", "CraftRecipe"))
            iconProbe.OnScriptsLoaded(ScriptLoadMode.Init)
            require(iconProbe.iconName == "Item_" + PianoIcon.TILE && iconProbe.iconTexture == null,
                "native item-only icon path changed")
            zombie.network.GameServer.server = true
            try {
                val serverOriginal = load(body, "Base", "Piano", "pz-vanilla")
                log.reset()
                require(recipe(serverOriginal).iconTexture == null
                    && log.toString().contains("Recipe Piano missing UiConfigScript"),
                    "native dedicated null/diagnostic changed")
            } finally {
                zombie.network.GameServer.server = false
            }

            PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", PianoChecks::class.java.classLoader)
            require(PianoIcon.SUPPORTED, "unsupported native Piano bytecode")
            require(!BytecodeSupport.supports("zombie/scripting/entity/components/crafting/CraftRecipe.class", "unknown"),
                "unknown native icon parser fingerprint accepted")
            val woven = nativeLoader(body) ?: throw NullPointerException()
            val component = recipe(woven)
            val initialState = state(component.craftRecipe, "iconName", "iconTexture")
            require(component.iconTexture === baseline, "early getter changed native texture")
            require(state(component.craftRecipe, "iconName", "iconTexture") == initialState,
                "early correction changed nonicon recipe fields")
            component.OnScriptsLoaded(ScriptLoadMode.Init)
            require(component.craftRecipe.iconName == PianoIcon.TILE && component.craftRecipe.iconTexture === baseline,
                "first native script stage prefixed or cleared world icon")
            val gameState = state(woven)
            val spriteState = state(woven.getComponentScriptFor<SpriteConfigScript>(ComponentType.SpriteConfig))
            val recipeState = state(component.craftRecipe, "iconName", "iconTexture")
            log.reset()
            require(component.iconTexture === baseline, "woven icon differs from real native fallback")
            require(!log.toString().contains("missing UiConfigScript"), "woven native recipe still diagnoses missing icon")
            require(component.craftRecipe.iconName == PianoIcon.TILE && component.craftRecipe.iconTexture === baseline,
                "explicit recipe metadata was not corrected")
            require(state(woven) == gameState && state(woven.getComponentScriptFor<SpriteConfigScript>(ComponentType.SpriteConfig)) == spriteState
                && state(component.craftRecipe, "iconName", "iconTexture") == recipeState,
                "world components/name/creation fields or recipe gameplay data changed")
            require(!woven.containsComponent(ComponentType.UiConfig) && woven.componentScripts.size == 2,
                "UI/save component set changed")
            require(component.iconTexture === baseline, "repeat icon resolution is not idempotent")
            require(repeatedStage(component) == nativeFailure, "native validation exception changed")
            require(component.craftRecipe.iconName == PianoIcon.TILE && component.craftRecipe.iconTexture === baseline,
                "exceptional script stage did not restore icon metadata and texture")
            require(PianoIcon.resolve(component, false) == null, "unsupported resolver enabled")
            require(PianoIcon.beginScripts(component.craftRecipe, false) == null, "unsupported stage guard enabled")
            val foreignResult = AtomicReference<Texture>()
            val foreignError = AtomicReference<Throwable>()
            val foreign = Thread {
                try {
                    foreignResult.set(PianoIcon.resolve(component, true))
                } catch (error: Throwable) {
                    foreignError.set(error)
                }
            }
            foreign.start()
            foreign.join()
            require(foreignResult.get() == null && foreignError.get() == null, "foreign thread modified recipe metadata")

            woven.PreReload()
            woven.Load("Piano", body)
            val reloaded = recipe(woven)
            reloaded.OnScriptsLoaded(ScriptLoadMode.Reload)
            require(reloaded.iconTexture === baseline, "native reload lost the icon correction")
            require(reloaded.craftRecipe.iconName == PianoIcon.TILE, "reloaded metadata missing")

            for (changed in arrayOf(body.replace("time = 10", "time = 11"),
                    body.replace("recreational_01_28", "recreational_01_13"),
                    body.replace("component CraftRecipe", "component UiConfig { xuiSkin = default, entityStyle = Custom, uiEnabled = true, }\ncomponent CraftRecipe"),
                    body.replace("time = 10", "Icon = CustomIcon, time = 10"))) {
                val custom = load(changed, "Base", "Piano", "pz-vanilla")
                require(PianoIcon.resolve(recipe(custom), true) == null, "changed native data accepted")
            }
            for (identity in arrayOf(arrayOf("Mod", "Piano", "pz-vanilla"), arrayOf("Base", "Other", "pz-vanilla"),
                    arrayOf("Base", "Piano", "custom-mod"))) {
                val custom = load(body, identity[0], identity[1], identity[2])
                require(PianoIcon.resolve(recipe(custom), true) == null, "custom entity identity accepted")
            }
            val unknown = load(body.replace("entity Piano", "entity Unknown"), "Base", "Unknown", "pz-vanilla")
            log.reset()
            recipe(unknown).iconTexture
            require(log.toString().contains("missing UiConfigScript"), "unknown native diagnostic suppressed")
            zombie.network.GameServer.server = true
            try {
                val dedicated = load(body, "Base", "Piano", "pz-vanilla")
                val atlasSize = GameWindow.texturePackTextures.size
                val dedicatedState = state(dedicated)
                val dedicatedRecipeState = state(recipe(dedicated).craftRecipe)
                log.reset()
                require(recipe(dedicated).iconTexture == null && Texture.getSharedTexture(PianoIcon.TILE) == null,
                    "dedicated server manufactured a UI texture")
                require(recipe(dedicated).craftRecipe.iconName == null
                    && !log.toString().contains("Recipe Piano missing UiConfigScript")
                    && state(dedicated) == dedicatedState && state(recipe(dedicated).craftRecipe) == dedicatedRecipeState,
                    "dedicated server retained unnecessary UI error or changed native metadata")
                require(GameWindow.texturePackTextures.size == atlasSize && !GameWindow.fileSystem.hasWork(),
                    "dedicated icon lookup loaded UI assets")
                val dedicatedUnknown = load(body.replace("entity Piano", "entity Unknown"), "Base", "Unknown", "pz-vanilla")
                log.reset()
                require(recipe(dedicatedUnknown).iconTexture == null
                    && log.toString().contains("Recipe Unknown missing UiConfigScript"),
                    "unknown dedicated diagnostic was suppressed")
                require(!PianoIcon.headless(recipe(dedicated), false), "unsupported dedicated guard enabled")
                for (changed in arrayOf(body.replace("time = 10", "time = 11"),
                        body.replace("time = 10", "Icon = CustomIcon, time = 10"),
                        body.replace("component CraftRecipe", "component UiConfig { entityStyle = Custom, }\ncomponent CraftRecipe"))) {
                    val custom = load(changed, "Base", "Piano", "pz-vanilla")
                    require(!PianoIcon.headless(recipe(custom), true), "custom dedicated data accepted")
                }
            } finally {
                zombie.network.GameServer.server = false
            }
            val missing = load(body, "Base", "Piano", "pz-vanilla")
            Texture.forgetTexture(PianoIcon.TILE)
            GameWindow.texturePackTextures.remove(PianoIcon.TILE)
            require(PianoIcon.resolve(recipe(missing), true) == null, "missing native texture accepted")
            require(recipe(missing).craftRecipe.iconName == null, "missing texture invented metadata")
            logger.setStdOut(System.out)
            logger.setStdErr(System.err)
            println("PIANO_CHECKS_PASS (native loader/error, same real tile/UV/pixels, early getter, first script stage, native exception restoration, reload, unchanged world/recipe fields, custom/thread/unsupported guards)")
        } catch (error: Throwable) {
            error.printStackTrace(System.err)
            System.exit(1)
        }
        System.exit(0)
    }
}

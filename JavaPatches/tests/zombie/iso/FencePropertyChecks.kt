package zombie.iso

import java.nio.file.Files
import java.nio.file.Path
import java.util.ArrayList
import java.util.HashMap
import java.util.TreeMap
import gnu.trove.map.hash.TIntObjectHashMap
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.PatchEngine
import net.bytebuddy.jar.asm.ClassReader
import net.bytebuddy.jar.asm.ClassVisitor
import net.bytebuddy.jar.asm.MethodVisitor
import net.bytebuddy.jar.asm.Opcodes
import net.alexredby.pztoolkitjavapatches.FenceProperties
import net.alexredby.pztoolkitjavapatches.FenceValidation
import net.alexredby.pztoolkitjavapatches.Main
import net.alexredby.pztoolkitjavapatches.TilePropertyNames
import zombie.ai.states.ClimbOverFenceState
import zombie.ai.states.GrappledThrownOverFenceState
import zombie.ai.states.animals.AnimalClimbOverFenceState
import zombie.core.TilePropertyAliasMap
import zombie.core.properties.PropertyContainer
import zombie.iso.SpriteDetails.IsoFlagType
import zombie.iso.objects.IsoThumpable
import zombie.iso.sprite.IsoSprite
import zombie.iso.sprite.IsoSpriteManager
import zombie.scripting.ScriptBucketCollection
import zombie.scripting.ScriptLoadMode
import zombie.scripting.ScriptManager
import zombie.scripting.ScriptParser
import zombie.scripting.objects.ScriptModule

object FencePropertyChecks {
    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun values(properties: PropertyContainer): MutableMap<String, String> {
        val result = TreeMap<String, String>()
        for (key in properties.propertyNames) result[key] = properties.get(key)
        return result
    }

    private fun aliases(): List<Any> {
        val aliases = TilePropertyAliasMap.instance
        val result = ArrayList<Any>()
        result.add(HashMap(aliases.propertyToId))
        for (property in aliases.properties)
            result.add(listOf(property.propertyName, ArrayList(property.possibleValues), HashMap(property.idMap)))
        return result
    }

    private fun copy(source: IsoSprite): IsoSprite {
        val result = IsoSprite()
        result.name = source.name
        result.getProperties().AddProperties(source.getProperties())
        return result
    }

    private fun selectors(sprite: IsoSprite): List<Any?> {
        val objectWithSprite = IsoObject()
        objectWithSprite.setSprite(sprite)
        val result = ArrayList<Any?>()
        for (state in listOf(ClimbOverFenceState.instance(), AnimalClimbOverFenceState.instance(), GrappledThrownOverFenceState.instance())) {
            for (name in listOf("getFenceType", "getTripType")) {
                val method = state.javaClass.getDeclaredMethod(name, IsoObject::class.java).apply { isAccessible = true }
                result.add(method.invoke(state, objectWithSprite))
            }
        }
        result.add(IsoThumpable.GetBreakFurnitureSound(sprite))
        return result
    }

    private fun unchanged(stock: IsoSprite, modify: (IsoSprite) -> Unit, supported: Boolean) {
        val manager = IsoSpriteManager()
        val sprite = copy(stock)
        modify(sprite)
        manager.namedMap.put(sprite.name, sprite)
        val properties = sprite.getProperties()
        val before = values(properties)
        val flags = properties.flagsList
        val maps = HashMap(manager.namedMap)
        val alias = aliases()
        require(FenceProperties.tilesLoaded(manager, supported) == 0, "modified/unsupported fence corrected: $before")
        require(properties === sprite.getProperties() && values(properties) == before
            && properties.flagsList == flags && manager.namedMap == maps && aliases() == alias,
            "modified/unsupported fence or global metadata changed")
    }

    private fun getterDispatch() {
        // IsoSprite is final, so inspect its API calls instead of inventing a subclass fixture.
        for ((helper, method, expected) in listOf(
                Triple("FenceProperties", "tilesLoaded", 2), Triple("FenceValidationLogic", "validate", 1))) {
            val reads = IntArray(2)
            val resource = "net/alexredby/pztoolkitjavapatches/$helper.class"
            val bytes = FenceProperties::class.java.classLoader.getResourceAsStream(resource).use { input ->
                (input ?: throw AssertionError("missing fence helper bytecode: $resource")).readAllBytes()
            }
            ClassReader(bytes).accept(object : ClassVisitor(Opcodes.ASM9) {
                override fun visitMethod(access: Int, name: String, descriptor: String,
                                         signature: String?, exceptions: Array<out String>?): MethodVisitor? {
                    if (name != method) return null
                    return object : MethodVisitor(Opcodes.ASM9) {
                        override fun visitMethodInsn(opcode: Int, owner: String, name: String, descriptor: String, itf: Boolean) {
                            if (opcode == Opcodes.INVOKEVIRTUAL && owner == "zombie/iso/sprite/IsoSprite"
                                && name == "getProperties" && descriptor == "()Lzombie/core/properties/PropertyContainer;") reads[0]++
                        }
                        override fun visitFieldInsn(opcode: Int, owner: String, name: String, descriptor: String) {
                            if (opcode == Opcodes.GETFIELD && owner == "zombie/iso/sprite/IsoSprite" && name == "properties") reads[1]++
                        }
                    }
                }
            }, 0)
            require(reads[0] == expected && reads[1] == 0, "$helper.$method replaced native getProperties calls with field reads")
        }
    }

    private fun loadNativeTiles() {
        val entityFile = Path.of("media/scripts/generated/entities/walls/entity_wood_fencelvl3.txt")
        val block = ScriptParser.parse(Files.readString(entityFile)).getBlock("module", "Base")
        val body = StringBuilder()
        block.getBlock("entity", "WoodFenceLvl3").prettyPrint(0, body)
        val module = ScriptModule()
        ScriptManager.instance.moduleMap.put("Base", module)
        val entities = ScriptManager::class.java.getDeclaredField("entities").apply { isAccessible = true }
        (entities.get(ScriptManager.instance) as ScriptBucketCollection<*>).registerModule(module)
        Accessor.trySet(ScriptManager::class.java, "currentLoadFileMod", "pz-vanilla")
        Accessor.trySet(ScriptManager::class.java, "currentLoadFileAbsPath", entityFile.toAbsolutePath().toString())
        module.Load(ScriptLoadMode.Init, "Base", body.toString())
        module.entities.LoadScripts(ScriptLoadMode.Init)
        require(!module.entities.isHasLoadErrors
            && ScriptManager.instance.allGameEntities.contains(module.entities.get("WoodFenceLvl3")),
            "native wooden fence entity did not load into script collection")
        val files = arrayOf("newtiledefinitions.tiles", "tiledefinitions_erosion.tiles", "tiledefinitions_overlays.tiles",
            "tiledefinitions_b42chunkcaching.tiles", "tiledefinitions_noiseworks.patch.tiles", "jumbo_trees_big.tiles", "jumbo_trees.tiles")
        val ids = intArrayOf(1, 2, 4, 5, -1, 6, 8)
        val world = IsoWorld.instance
        val manager = IsoSpriteManager.instance
        for (i in files.indices) world.LoadTileDefinitionsPropertyStrings(manager, "media/" + files[i], ids[i])
        val custom = IsoWorld::class.java.getDeclaredMethod("SetCustomPropertyValues").apply { isAccessible = true }
        custom.invoke(world)
        val generate = IsoWorld::class.java.getDeclaredMethod("GenerateTilePropertyLookupTables").apply { isAccessible = true }
        generate.invoke(world)
        for (i in files.indices) world.LoadTileDefinitions(manager, "media/" + files[i], ids[i])
        require(FenceProperties.tilesLoaded(manager, true) == 0, "unbound tile metadata accepted")
        ScriptManager.instance.PostTileDefinitions()
        require(!zombie.entity.components.spriteconfig.SpriteConfigManager.HasLoadErrors(), "native entity sprite binding failed")
        for (key in listOf("FenceTypeLow", "FenceTypeHigh", "ThumpSound", "EntityScriptName")) {
            val property = TilePropertyAliasMap.instance.properties[TilePropertyAliasMap.instance.getIDFromPropertyName(key)]
            property.idMap.put("toolkit-custom", property.possibleValues.size)
            property.possibleValues.add("toolkit-custom")
            property.idMap.put("", property.possibleValues.size)
            property.possibleValues.add("")
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        zombie.network.GameServer.server = true
        Main.main(emptyArray())
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", FencePropertyChecks::class.java.classLoader)
        require(TilePropertyNames.SUPPORTED && FenceValidation.SUPPORTED, "unsupported native property/fence bytecode")
        loadNativeTiles()
        val manager = IsoSpriteManager.instance
        val west = manager.namedMap.get("carpentry_02_48")
            ?: throw AssertionError("native fence tiles missing")
        val north = manager.namedMap.get("carpentry_02_49")
            ?: throw AssertionError("native fence tiles missing")
        val propertyIds = TilePropertyAliasMap.instance.propertyToId
        val lowId = propertyIds.remove("FenceTypeLow")!!
        try {
            require(FenceProperties.tilesLoaded(manager, true) == 0, "missing alias accepted")
        } finally {
            propertyIds.put("FenceTypeLow", lowId)
        }
        val woodAliases = TilePropertyAliasMap.instance.properties[lowId]
        val woodId = woodAliases.idMap.get("Wood")!!
        val wood = woodAliases.possibleValues.set(woodId, "toolkit-custom")
        try {
            require(FenceProperties.tilesLoaded(manager, true) == 0, "wrong alias value accepted")
        } finally {
            woodAliases.possibleValues.set(woodId, wood)
        }
        for (stock in listOf(west, north)) {
            require(!stock.getProperties().has("FenceTypeLow"), "native omission no longer exists")
            unchanged(stock, {}, false)
            for (property in listOf("FenceTypeLow", "FenceTypeHigh", "ThumpSound")) {
                unchanged(stock, { it.getProperties().set(property, "toolkit-custom") }, true)
                unchanged(stock, { it.getProperties().set(property, "") }, true)
            }
            unchanged(stock, { it.getProperties().set("FenceTypeLow", "Metal") }, true)
            unchanged(stock, { it.getProperties().set("Material", "Metal") }, true)
            unchanged(stock, { it.getProperties().unset("IsPaintable") }, true)
            unchanged(stock, { it.getProperties().unset("EntityScriptName") }, true)
            unchanged(stock, { it.getProperties().set("EntityScriptName", "toolkit-custom") }, true)
            unchanged(stock, { it.getProperties().unset(IsoFlagType.EntityScript) }, true)
            unchanged(stock, { it.getProperties().set(IsoFlagType.solid) }, true)
            unchanged(stock, { it.getProperties().unset(if (stock === west) IsoFlagType.canPathW else IsoFlagType.canPathN) }, true)
            unchanged(stock, { it.name = "toolkit-custom-fence" }, true)
        }
        val alias = aliases()
        val named = HashMap(manager.namedMap)
        val byId = TIntObjectHashMap(manager.intMap)
        val westProperties = west.getProperties()
        val northProperties = north.getProperties()
        val westBefore = values(westProperties)
        val northBefore = values(northProperties)
        val westFlags = westProperties.flagsList
        val northFlags = northProperties.flagsList
        val westSelectors = selectors(west)
        val northSelectors = selectors(north)
        require(FenceProperties.tilesLoaded(manager, true) == 2, "stock two fences were not corrected")
        westBefore["FenceTypeLow"] = "Wood"
        northBefore["FenceTypeLow"] = "Wood"
        require(west.getProperties() === westProperties && north.getProperties() === northProperties
            && values(westProperties) == westBefore && values(northProperties) == northBefore
            && westFlags == westProperties.flagsList && northFlags == northProperties.flagsList,
            "stock properties/flags/container identities changed beyond FenceTypeLow")
        require(manager.namedMap == named && manager.intMap == byId && aliases() == alias, "sprite maps or aliases changed")
        require(selectors(west) == westSelectors && selectors(north) == northSelectors,
            "native player/animal climb/trip or furniture break sound selector changed")
        require(FenceProperties.tilesLoaded(manager, true) == 0, "repeat correction changed stock metadata")
        require(FenceProperties.tilesLoaded(null, true) == 0, "null manager accepted")
        getterDispatch()
        println("FENCE_PROPERTY_CHECKS_PASS (native seven tile files; two exact stock sprites corrected; player/animal/grapple climb/trip and furniture break selectors preserved; custom/empty/modified/unknown/unsupported sprites and missing/wrong aliases rejected; flags, map/container identities and aliases preserved)")
    }
}

package net.alexredby.equipmentprobe;

import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import zombie.entity.ComponentType;
import zombie.entity.components.attributes.AttributeContainer;
import zombie.entity.components.script.EntityScriptInfo;
import zombie.inventory.InventoryItem;
import zombie.inventory.types.ComboItem;
import zombie.scripting.ScriptBucketCollection;
import zombie.scripting.ScriptLoadMode;
import zombie.scripting.ScriptManager;
import zombie.scripting.ScriptParser;
import zombie.scripting.entity.components.attributes.AttributesScript;
import zombie.scripting.objects.Item;
import zombie.scripting.objects.ItemType;
import zombie.scripting.objects.ScriptModule;

/** Standalone native factory preflight: no world, window, agent or installed mod. */
public final class HotbarItemShapeCheck {
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static Item parse(ScriptParser.Block nativeModule, ScriptModule module, String name,
                              boolean omitFluidIcon) throws Exception {
        var block = nativeModule.getBlock("item", name);
        require(block != null, "native item missing: " + name);
        // Rendering fields eagerly load textures. Scissors omits only Icon;
        // the RoastingPan control also omits its IconFluidMask. Factory and
        // component metadata are otherwise the exact shipped definition.
        var icon = block.getValue("Icon");
        require(icon != null, "native icon missing: " + name);
        block.values.remove(icon);
        block.elements.remove(icon);
        if (omitFluidIcon) {
            var mask = block.getValue("IconFluidMask");
            require(mask != null, "native control fluid icon missing");
            block.values.remove(mask);
            block.elements.remove(mask);
        }
        var body = new StringBuilder();
        block.prettyPrint(0, body);
        var item = new Item();
        item.setModule(module);
        item.InitLoadPP(name);
        item.Load(name, body.toString());
        item.OnScriptsLoaded(ScriptLoadMode.Init);
        require(item.getFullName().equals("Base." + name) && item.getItemType() == ItemType.NORMAL,
                "native normal script identity/type changed: " + name);
        return item;
    }

    private static void plain(InventoryItem item, Item script) {
        require(item.getClass() == ComboItem.class && item.getScriptItem() == script
                && item.getFullType().equals(script.getFullName()), "native normal factory class/identity changed");
        require(script.getLuaCreate() == null && script.getItemConfig() == null && script.getItemConfigKey() == null,
                "native fixture gained factory callback/configuration");
        require(item.getFluidContainer() == null && !item.isWet() && item.getItemWhenDry() == null,
                "native fixture gained fluid/wet/drying effects");
    }

    public static void main(String[] args) throws Exception {
        require(args.length == 1, "isolated cache path required");
        zombie.ZomboidFileSystem.instance.setCacheDir(args[0]);
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        Field mod = ScriptManager.class.getDeclaredField("currentLoadFileMod");
        mod.setAccessible(true);
        mod.set(null, "pz-vanilla");
        zombie.world.WorldDictionary.StartScriptLoading();
        var module = new ScriptModule();
        module.Load(ScriptLoadMode.Init, "Base", "module Base { }");
        ScriptManager.instance.moduleMap.put("Base", module);
        ScriptManager.instance.moduleList.add(module);
        Field buckets = ScriptManager.class.getDeclaredField("bucketCollectionList");
        buckets.setAccessible(true);
        for (Object bucket : (List<?>) buckets.get(ScriptManager.instance))
            ((ScriptBucketCollection<?>) bucket).registerModule(module);
        var nativeModule = ScriptParser.parse(ScriptParser.stripComments(Files.readString(
                Path.of("media/scripts/generated/items/normal.txt")))).getBlock("module", "Base");
        var script = parse(nativeModule, module, "ScissorsBluntMedical", false);
        var item = script.InstanceItem(null);
        plain(item, script);
        var definitions = script.getComponentScripts();
        require(script.hasComponents() && definitions.size() == 1
                && definitions.get(0).getClass() == AttributesScript.class
                && definitions.get(0) == script.getComponentScriptFor(ComponentType.Attributes),
                "Scissors native attributes script shape changed");
        var attributes = item.getAttributes();
        var metadata = item.getComponent(ComponentType.Script);
        require(item.hasComponents() && item.componentSize() == 2
                && attributes != null && attributes.getClass() == AttributeContainer.class
                && attributes == item.getComponentForIndex(0)
                && attributes.getComponentType() == ComponentType.Attributes && attributes.getOwner() == item,
                "Scissors native attributes instance shape/owner changed");
        require(metadata != null && metadata.getClass() == EntityScriptInfo.class
                && metadata == item.getComponentForIndex(1)
                && metadata.getComponentType() == ComponentType.Script && metadata.getOwner() == item,
                "Scissors native script-info shape/owner changed");
        var info = (EntityScriptInfo) metadata;
        require(info.getScript() == script && item.getEntityScript() == script && info.isOriginalIsItem()
                && script.getScriptObjectFullType().equals(info.getOriginalScript()),
                "Scissors native script-info canonical mapping changed");
        require(item.getCondition() == 10 && item.getSharpness() == 1.0f,
                "Scissors native condition/sharpness changed");
        System.out.println("SCISSORS class=" + item.getClass().getSimpleName()
                + " scriptComponents=1:AttributesScript itemComponents=2:AttributeContainer,EntityScriptInfo"
                + " canonical=true owners=true original=" + info.getOriginalScript()
                + " condition=" + item.getCondition() + " sharpness=" + item.getSharpness());
        var panScript = parse(nativeModule, module, "RoastingPan", true);
        var pan = panScript.InstanceItem(null);
        plain(pan, panScript);
        require(!panScript.hasComponents() && panScript.getComponentScripts().isEmpty()
                && !pan.hasComponents() && pan.componentSize() == 0 && pan.getEntityScript() == null,
                "RoastingPan native no-components control changed");
        System.out.println("ROASTING_PAN class=" + pan.getClass().getSimpleName()
                + " scriptComponents=0 itemComponents=0 entityScript=null");
        System.out.println("HOTBAR_ITEM_SHAPE_CHECK_PASS");
    }
}

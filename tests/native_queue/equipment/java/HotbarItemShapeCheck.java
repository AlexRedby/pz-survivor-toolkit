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
                              boolean omitFluidIcon, ItemType expectedType) throws Exception {
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
        require(item.getFullName().equals("Base." + name) && item.getItemType() == expectedType,
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
        var script = parse(nativeModule, module, "ScissorsBluntMedical", false, ItemType.NORMAL);
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
        var panScript = parse(nativeModule, module, "RoastingPan", true, ItemType.NORMAL);
        var pan = panScript.InstanceItem(null);
        plain(pan, panScript);
        require(!panScript.hasComponents() && panScript.getComponentScripts().isEmpty()
                && !pan.hasComponents() && pan.componentSize() == 0 && pan.getEntityScript() == null,
                "RoastingPan native no-components control changed");
        System.out.println("ROASTING_PAN class=" + pan.getClass().getSimpleName()
                + " scriptComponents=0 itemComponents=0 entityScript=null");
        var radioModule = ScriptParser.parse(ScriptParser.stripComments(Files.readString(
                Path.of("media/scripts/generated/items/radio.txt")))).getBlock("module", "Base");
        var radioScript = parse(radioModule, module, "WalkieTalkie2", false, ItemType.RADIO);
        // Radio uses the legacy string constructor which eagerly probes icon textures.
        // Native headless server mode suppresses only that rendering lookup.
        boolean wasServer = zombie.network.GameServer.server;
        InventoryItem radio;
        try {
            zombie.network.GameServer.server = true;
            radio = radioScript.InstanceItem(null);
        } finally {
            zombie.network.GameServer.server = wasServer;
        }
        require(radio.getClass() == zombie.inventory.types.Radio.class && radio.getScriptItem() == radioScript
                && radio.getFullType().equals("Base.WalkieTalkie2"), "native radio factory class/identity changed");
        require(radioScript.getLuaCreate() == null && radioScript.getItemConfig() == null && radioScript.getItemConfigKey() == null
                && !radioScript.hasComponents() && !radio.hasComponents() && radio.getFluidContainer() == null
                && !radio.isWet() && radio.getItemWhenDry() == null, "native radio gained unreviewed factory/component effects");
        var device = ((zombie.inventory.types.Radio) radio).getDeviceData();
        require(device != null && device.getClass() == zombie.radio.devices.DeviceData.class && device.getParent() == radio
                && device.getIsPortable() && device.getIsBatteryPowered() && !device.getIsTelevision()
                && !device.hasMedia() && !device.isPlayingMedia() && !radio.canBeActivated()
                && radio.getAttachmentType().equals("Walkie"), "native portable radio device/attachment shape changed");
        System.out.println("RADIO class=Radio script=base:radio device=DeviceData parent=true portable=true battery=true media=false attachment=Walkie");
        var drainables = ScriptParser.parse(ScriptParser.stripComments(Files.readString(
                Path.of("media/scripts/generated/items/drainable.txt")))).getBlock("module", "Base");
        var lightScript = parse(drainables, module, "FlashLight_AngleHead", false, ItemType.DRAINABLE);
        var light = lightScript.InstanceItem(null);
        require(light.getClass() == zombie.inventory.types.DrainableComboItem.class && light.getScriptItem() == lightScript
                && light.getFullType().equals("Base.FlashLight_AngleHead") && light.hasTag(zombie.scripting.objects.ItemTag.FLASHLIGHT)
                && light.getAttachmentType().equals("Webbing"), "native flashlight factory/type/tag/attachment changed");
        var torch = (zombie.inventory.types.DrainableComboItem) light;
        require(lightScript.getLuaCreate() == null && lightScript.getItemConfig() == null && lightScript.getItemConfigKey() == null
                && lightScript.getReplaceOnUse() == null && lightScript.getOnBreak() == null
                && !lightScript.hasComponents() && !light.hasComponents() && light.getFluidContainer() == null
                && !light.isWet() && light.getItemWhenDry() == null && !torch.isCookable() && torch.getOnCooked() == null
                && torch.getOnEat() == null && (torch.getReplaceOnCooked() == null || torch.getReplaceOnCooked().isEmpty()),
                "native flashlight gained callback/component/cooking effects");
        require(torch.canBeActivated() && torch.isKeepOnDeplete() && torch.isUseWhileEquiped() && !torch.isUseWhileUnequiped()
                && torch.getReplaceOnDeplete() == null && torch.getReplaceOnDepleteFullType() == null
                && torch.getUseDelta() == 0.006f && torch.getMaxUses() == 166 && torch.getLightStrength() == 1.5f
                && torch.getLightDistance() == 15 && torch.isTorchCone(), "native flashlight lifecycle shape changed");
        torch.setCurrentUses(1);torch.setActivated(true);
        require(torch.isEmittingLight(), "charged native flashlight must emit");
        torch.Use();
        require(torch.getCurrentUses() == 0 && torch.isActivated() && !torch.isEmittingLight() && torch.isKeepOnDeplete() && torch.getLightStrength() == 1.5f && torch.getLightDistance() == 15,
                "native kept flashlight depletion changed activation/emission/identity behavior");
        System.out.println("FLASHLIGHT class=DrainableComboItem script=base:drainable tag=flashlight attachment=Webbing maxUses=166 nativeUse=0 activated=true emitting=false kept=true");
        var clothes = ScriptParser.parse(ScriptParser.stripComments(Files.readString(
                Path.of("media/scripts/generated/items/clothing.txt")))).getBlock("module", "Base");
        var provider = parse(clothes, module, "SCBA_notank", false, ItemType.CLOTHING);
        require(provider.getBodyLocation().toString().equals("base:scbanotank") && provider.attachmentsProvided != null
                && provider.attachmentsProvided.equals(List.of("SmallBeltLeft", "SmallBeltRight", "WebbingLeft")),
                "native flashlight provider location/slots changed");
        System.out.println("FLASHLIGHT_PROVIDER script=Base.SCBA_notank location=base:scbanotank slots=SmallBeltLeft,SmallBeltRight,WebbingLeft");
        System.out.println("HOTBAR_ITEM_SHAPE_CHECK_PASS");
    }
}

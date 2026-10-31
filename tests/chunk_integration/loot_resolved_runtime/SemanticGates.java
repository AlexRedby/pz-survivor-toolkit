package toolkit.lootresolved.runtime;

import java.io.InputStream;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import toolkit.lootresolved.bootstrap.Bootstrap;
import zombie.SandboxOptions;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.core.random.Rand;
import zombie.inventory.*;
import zombie.inventory.ItemPickerJava.*;
import zombie.inventory.types.InventoryContainer;
import zombie.iso.IsoGridSquare;
import zombie.scripting.*;
import zombie.scripting.objects.Item;

/** Additional explicitly selected native cases. No game/world/script implementation is replaced. */
final class SemanticGates {
    static final String TARGET="Base.PZLootRuntimeProbe", ALTERNATE="Base.PZLootRuntimeAlternate", SOURCE="Base.PZLootRuntimeSource";
    static final String SCRIPT="loot-runtime-probes.txt";
    private static Binding binding;
    private static int sourcePaths, replacementPaths;
    private static boolean reloadAttempted, reloadComplete, diskRestored;

    static String coverage() {
        return "source_square="+(sourcePaths==2?"finite-plumbing":"uncovered")
            +"\nregional_multiplier=uncovered-no-differential\nmodule_item_replacement="+(replacementPaths==2?"complete":"uncovered")
            +"\nlive_script_reload="+(reloadComplete?"terminal-complete":"uncovered")+"\nreload_attempted="+reloadAttempted
            +"\nreload_disk_restored="+diskRestored+"\nreload_runtime_restored=false\n";
    }
    private static void preflight() {
        Main.require(SandboxOptions.instance.rollsMultiplier.getValue()==1.0,"semantic-bank-requires-initial-RollsMultiplier1");
        Item target=ScriptManager.instance.FindItem(TARGET), alternate=ScriptManager.instance.FindItem(ALTERNATE);
        Main.require(target!=null && alternate!=null && target!=alternate && ScriptManager.instance.FindItem(SOURCE)!=null,"missing-preloaded-native-probes");
        Main.require(SandboxOptions.instance.mementoLootNew.getValue()==0.0 && SandboxOptions.instance.medicalLootNew.getValue()==1.0,
            "semantic-bank-requires-declared-initial-loot-factors");
        Main.require(ScriptManager.instance.FindItem("PZLootRuntimeProbe")==target
            && ScriptManager.instance.FindItem("PZLootRuntimeAlternate")==alternate,"preloaded-probe-resolution");
    }
    static void runSemantics(IsoPlayer actor) throws Exception {
        preflight();
        Main.require(actor!=null && !actor.isDead() && actor.getSquare()!=null,"semantic-owned-actor-required");
        IsoGridSquare square=actor.getSquare();
        Main.require(zombie.iso.IsoWorld.instance.currentCell.getGridSquare(square.x,square.y,square.z)==square,"foreign-source-square");
        // Ordinary no-Region squares return "General", not null. Do not invent a null Region
        // or alter map zones to force SandboxOptions' ruralLooted branch.
        Main.test("finite-source-direct","",()->source(square,false));
        Main.test("finite-source-bag","",()->source(square,true));
        Main.test("callback-module-replacement-direct","module",()->replace(false));
        Main.test("callback-module-replacement-bag","module",()->replace(true));
    }
    private static ItemContainer output(boolean bag, IsoGridSquare square) {
        ItemContainer out;
        if (bag) {
            InventoryContainer item=Main.bag();
            // The bag is in a detached real root, and both root and actual roll inventory have
            // the real source. The native chance call reads that inventory's getSourceGrid().
            ItemContainer root=Main.container(100); root.setSourceGrid(square);
            // Native AddItem(InventoryItem) is setup, not ItemSpawner: it neither
            // invokes acceptance nor increments Item Spawns. The bag is already owned.
            Main.require(root.AddItem(item)==item,"bag-root-native-insertion");
            out=item.getInventory();
            Main.require(item.getOutermostContainer()==root,"bag-source-parent-root");
        } else out=Main.container(100);
        out.setSourceGrid(square);
        Main.require(out.getSourceGrid()==square,"source-grid-identity");
        return out;
    }
    private static void roll(boolean bag, ItemContainer out, ItemPickerContainer dist) {
        if (bag) {
            Main.require(out.getContainingItem() instanceof InventoryContainer,"native-roll-bag-owner");
            ItemPickerJava.rollContainerItem((InventoryContainer)out.getContainingItem(),null,dist);
        } else Main.direct(dist,out);
    }
    private static void settings() {
        Main.row("SETTINGS","rolls=1.0:memento=0.0:medical=1.0:scope=initial-owned-test-only");
    }
    private static void source(IsoGridSquare square, boolean bag) throws Exception {
        settings();
        int seed=Main.caseSeed();
        Bootstrap.seedRng(seed); int draw=Rand.Next(10000); Bootstrap.seedRng(seed);
        Main.require(draw>1 && draw<9998,"finite-source-seed-boundary");
        String region=ItemPickerJava.getSquareRegion(square);
        Main.require(region!=null,"unreviewed-null-region-input");
        float global=SandboxOptions.instance.getCurrentLootMultiplier(), regional=SandboxOptions.instance.getCurrentLootMultiplier(square);
        Main.require(Float.isFinite(global) && global>0 && Float.floatToRawIntBits(global)==Float.floatToRawIntBits(regional),
            "source-factor-differs-requires-separate-regional-review");
        // Coordinate provenance is retained separately; compared inputs are exact native region,
        // multipliers and source identity, not a claim that every loaded square is equivalent.
        Files.writeString(Bootstrap.cache().resolve("loot-source-"+ProcessHandle.current().pid()+"-"+(bag?"bag":"direct")+".txt"),
            "x="+square.x+"\ny="+square.y+"\nz="+square.z+"\nregion="+region+"\nactual_loaded_square=true\n");
        for (boolean sourced : new boolean[]{false,true}) for (boolean hit : new boolean[]{true,false}) {
            ItemContainer out=output(bag,sourced?square:null);
            ItemPickerContainer dist=Main.distribution(SOURCE); ItemPickerItem item=dist.items[0]; item.chance=1f;
            float unit=ItemPickerJava.getActualSpawnChance(item,null,out,0f,false);
            Main.require(Float.isFinite(unit) && unit>0,"finite-source-native-unit-chance");
            item.chance=(draw+(hit?1f:-1f))/unit;
            float chance=ItemPickerJava.getActualSpawnChance(item,null,out,0f,false);
            Main.require(Float.isFinite(item.chance) && Float.isFinite(chance) && chance>0 && chance<10000
                && (draw<chance)==hit,"finite-source-chance-does-not-separate-draw");
            Bootstrap.seedRng(seed); roll(bag,out,dist);
            Main.require(out.getItems().size()==(hit?1:0),"finite-source-native-outcome");
            String label=(sourced?"source":"null")+(hit?"-hit":"-miss");
            Main.row("SOURCE", "path="+(bag?"bag":"direct")+":trial="+label+":source="+sourced+":region="+(sourced?region:"none")
                +":global_factor="+Main.bits(global)+":square_factor="+Main.bits(regional)+":draw="+draw+":picker_chance="+Main.bits(item.chance)
                +":native_chance="+Main.bits(chance)+":expected="+(hit?1:0)+":actual="+out.getItems().size()+":next_rng="+Rand.Next(1_000_000)
                +":regional_differential=false");
            Main.snapshot(out,label,0); Main.disposeTrial();
        }
        sourcePaths++;
    }
    @SuppressWarnings("unchecked")
    private static Map<String,Item> fullTypes() throws Exception {
        return ((ScriptBucketCollection<Item>)Main.field(ScriptManager.class,"items").get(ScriptManager.instance)).getFullTypeToScriptMap();
    }
    private static final class Binding implements AutoCloseable {
        final Map<String,Item> module=ScriptManager.instance.getModule("Base").items.getScriptMap(), full;
        final Item old, alternate;
        boolean changed;
        final ItemContainer out;
        final ItemPickerContainer distribution;
        Binding(ItemContainer out, ItemPickerContainer distribution) throws Exception {
            this.out=out; this.distribution=distribution;
            full=fullTypes(); old=module.get("PZLootRuntimeProbe"); alternate=ScriptManager.instance.FindItem(ALTERNATE);
            Main.require(old!=null && old==full.get(TARGET) && alternate!=old,"module-binding-input");
            for (int i=1;i<3;i++) {
                float chance=ItemPickerJava.getActualSpawnChance(distribution.items[i],null,out,0f,false);
                Main.require(Float.isFinite(chance) && chance==0f,"module-old-finite-chance-must-miss");
            }
        }
        void replace() {
            if (changed) return;
            Main.require(module.get("PZLootRuntimeProbe")==old && full.get(TARGET)==old,"module-binding-changed-before-callback");
            module.put("PZLootRuntimeProbe",alternate); full.put(TARGET,alternate); changed=true;
            Main.require(ScriptManager.instance.FindItem("PZLootRuntimeProbe")==alternate
                && ScriptManager.instance.FindItem(TARGET)==alternate,"callback-rebinding-not-visible");
            float qualified=ItemPickerJava.getActualSpawnChance(distribution.items[1],null,out,0f,false);
            float shortName=ItemPickerJava.getActualSpawnChance(distribution.items[2],null,out,0f,false);
            Main.require(Float.isFinite(qualified) && qualified>=10000 && Float.floatToRawIntBits(qualified)==Float.floatToRawIntBits(shortName),
                "module-new-finite-chance-must-hit");
            Main.row("REBIND","callback=true:qualified_new=true:unqualified_new=true:old_distinct=true:old_chance=0:new_chance="+Main.bits(qualified)
                +":picker_chance="+Main.bits(distribution.items[1].chance)+":draw_min=0:draw_max_exclusive=10000");
        }
        @Override public void close() {
            if (changed) {
                Main.require(module.get("PZLootRuntimeProbe")==alternate && full.get(TARGET)==alternate,"foreign-map-change-during-binding");
                module.put("PZLootRuntimeProbe",old); full.put(TARGET,old);
            }
            Main.require(ScriptManager.instance.FindItem(TARGET)==old && ScriptManager.instance.FindItem("PZLootRuntimeProbe")==old,"module-binding-restore");
            Main.row("RESTORE","module=true:fulltype=true:qualified_old=true:unqualified_old=true");
        }
    }
    static void onAccept(InventoryItem item) {
        if (binding!=null && !binding.changed) {
            Main.require(item.getFullType().equals("Base.Nails"),"replacement-trigger-is-not-first-roll-Nails");
            binding.replace();
        }
    }
    private static void replace(boolean bag) throws Exception {
        settings();
        ItemContainer out=output(bag,null);
        ItemPickerContainer dist=Main.distribution("Base.Nails",TARGET,"PZLootRuntimeProbe");
        dist.items[1].chance=dist.items[2].chance=20000f;
        try (Binding owned=new Binding(out,dist)) {
            binding=owned;
            try {
                roll(bag,out,dist);
                Main.require(owned.changed && out.getItems().size()==3,"callback-replacement-count");
                for (int i=1;i<3;i++) Main.require(out.getItems().get(i).getFullType().equals(ALTERNATE)
                    && out.getItems().get(i).getScriptItem()==owned.alternate,"factory-did-not-use-replacement");
                Main.row("REPLACEMENT","path="+(bag?"bag":"direct")+":qualified_factory=true:unqualified_factory=true:count=3");
                Main.snapshot(out,"replacement",0);
            } finally { binding=null; }
        }
        replacementPaths++;
    }
    private static String sha(byte[] bytes) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }
    private static byte[] originalScript() throws Exception {
        try (InputStream in=SemanticGates.class.getResourceAsStream(SCRIPT)) {
            Main.require(in!=null,"missing-probe-script-resource"); return in.readAllBytes();
        }
    }
    private static Path ownedPath() throws Exception {
        Path cache=Bootstrap.cache(); Path path=cache.resolve("mods/PZLootResolvedRuntime/42/media/scripts/"+SCRIPT);
        Main.require(Bootstrap.owned(cache) && Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS),"reload-owned-script-marker");
        for (Path current=path;!current.equals(cache);current=current.getParent()) Main.require(!Files.isSymbolicLink(current),"reload-script-symlink");
        return path;
    }
    private static Path ownedScript(Item target) throws Exception {
        Path path=ownedPath();
        Main.require(target.getFileAbsPath()!=null && path.toRealPath().equals(Path.of(target.getFileAbsPath()).toRealPath())
            && path.toRealPath().equals(Path.of(ZomboidFileSystem.instance.getAbsolutePath(target.getFileName())).toRealPath()),"reload-script-not-native-source");
        return path;
    }
    @SuppressWarnings("unchecked")
    private static String boundedReloadInputs() throws Exception {
        List<String> names=new ArrayList<>((List<String>)Main.field(ScriptManager.class,"loadFileNames").get(ScriptManager.instance));
        Main.require(!names.isEmpty() && names.size()<=4096,"reload-source-count-bound");
        MessageDigest digest=MessageDigest.getInstance("SHA-256"); long total=0;
        for (String name:names) {
            Path path=Path.of(ZomboidFileSystem.instance.getAbsolutePath(name));
            Main.require(Files.isRegularFile(path) && Files.size(path)<=8*1024*1024,"reload-source-file-bound");
            byte[] bytes=Files.readAllBytes(path); total+=bytes.length;
            Main.require(total<=128L*1024*1024,"reload-total-source-bound"); digest.update(MessageDigest.getInstance("SHA-256").digest(bytes));
        }
        return "files="+names.size()+":bytes="+total+":input_digest="+HexFormat.of().formatHex(digest.digest());
    }
    private static void reloadRolls(String phase, Item expected, float weight, boolean hit) throws Exception {
        for (boolean bag:new boolean[]{false,true}) {
            ItemContainer out=output(bag,null); Bootstrap.seedRng(bag?92:91);
            ItemPickerContainer dist=Main.distribution(TARGET,"PZLootRuntimeProbe");
            for (ItemPickerItem picker:dist.items) picker.chance=20000f;
            float chance=ItemPickerJava.getActualSpawnChance(dist.items[0],null,out,0f,false);
            Main.require(Float.isFinite(chance) && (hit?chance>=10000:chance==0),"reload-finite-classification-chance");
            roll(bag,out,dist);
            Main.require(out.getItems().size()==(hit?2:0),"reload-native-roll-count");
            for (int index=0;index<out.getItems().size();index++) {
                InventoryItem item=out.getItems().get(index);
                // Native InstanceItem copies the script weight, but the public getter returns
                // zero for an untranslated name equal to its full type. Verify both contracts.
                float stored=Main.field(InventoryItem.class,"actualWeight").getFloat(item);
                boolean fallback=item.getDisplayName().equals(item.getFullType());
                float publicWeight=item.getActualWeight(), expectedPublic=fallback?0f:Math.max(stored,0f);
                Main.row("RELOAD_ITEM","phase="+phase+":path="+(bag?"bag":"direct")+":index="+index
                    +":fulltype="+item.getFullType()+":id="+item.getID()+":stored_weight="+Main.bits(stored)
                    +":public_weight="+Main.bits(publicWeight)+":display_fallback="+fallback
                    +":script_identity="+(item.getScriptItem()==expected)+":initialized="+item.isInitialised());
                Main.require(item.getClass()==zombie.inventory.types.ComboItem.class && item.getFullType().equals(TARGET) && item.getScriptItem()==expected && item.isInitialised()
                    && Float.floatToRawIntBits(stored)==Float.floatToRawIntBits(weight)
                    && Float.floatToRawIntBits(publicWeight)==Float.floatToRawIntBits(expectedPublic),
                    "reload-factory-field-proof:index="+index+":stored="+Main.bits(stored)+":public="+Main.bits(publicWeight)+":fallback="+fallback);
            }
            Main.row("RELOAD_ROLL","phase="+phase+":path="+(bag?"bag":"direct")+":count="+(hit?2:0)+":weight="+Main.bits(weight)+":script_field_proof=true:factory_proof="+hit+":picker_chance="+Main.bits(20000f)+":native_chance="+Main.bits(chance)+":draw_min=0:draw_max_exclusive=10000:next_rng="+Rand.Next(1_000_000));
            Main.snapshot(out,phase+(bag?"-bag":"-direct"),0); Main.disposeTrial();
        }
    }
    static void runReload() throws Exception {
        preflight();
        Main.test("terminal-live-item-reload","",()->{
            settings();
            ScriptManager manager=ScriptManager.instance; Item before=manager.FindItem(TARGET);
            Main.require(!manager.hasLoadErrors() && before.getDisplayCategory().equals("Memento")
                && before.getActualWeight()==0.05f,"reload-initial-native-state");
            Path path=ownedScript(before); byte[] original=originalScript();
            Main.require(Arrays.equals(Files.readAllBytes(path),original),"reload-source-bytes-differ");
            String text=new String(original,java.nio.charset.StandardCharsets.UTF_8);
            String anchor="DisplayCategory = Memento,\n        Weight = 0.05,";
            Main.require(text.contains(anchor) && text.indexOf(anchor)==text.lastIndexOf(anchor),"reload-source-edit-anchor");
            byte[] changed=text.replace(anchor,"DisplayCategory = FirstAid,\n        Weight = 0.125,").getBytes(java.nio.charset.StandardCharsets.UTF_8);
            String inputs=boundedReloadInputs(); reloadRolls("before",before,0.05f,false);
            try {
                Files.write(path,changed,StandardOpenOption.TRUNCATE_EXISTING);
                Main.require(sha(Files.readAllBytes(path)).equals(sha(changed)),"reload-written-source-digest");
                Main.row("RELOAD_INPUT",inputs+":original="+sha(original)+":changed="+sha(changed));
                reloadAttempted=true; manager.ReloadScripts(ScriptType.Item);
                Item after=manager.FindItem(TARGET);
                Main.require(!manager.hasLoadErrors() && after==before && manager.FindItem("PZLootRuntimeProbe")==after
                    && after.getDisplayCategory().equals("FirstAid") && after.getActualWeight()==0.125f,"native-live-reload-field-identity-proof");
                Main.require(ownedScript(after).equals(path),"reload-postload-native-source-changed");
                Main.row("RELOAD","native_api=ReloadScripts(Item):same_identity=true:qualified=true:unqualified=true:category=FirstAid:weight="+Main.bits(after.getActualWeight())+":load_errors=false:owned_source=true");
                reloadRolls("after",after,0.125f,true); reloadComplete=true;
            } finally {
                Main.require(ownedPath().equals(path),"reload-restore-owned-path-changed");
                Files.write(path,original,StandardOpenOption.TRUNCATE_EXISTING);
                diskRestored=Arrays.equals(Files.readAllBytes(path),original);
                Main.require(diskRestored,"reload-disk-restore-failed");
                Main.row("RELOAD_RESTORE","disk=true:original="+sha(original)+":runtime_restored=false:terminal=true");
            }
        });
    }
}

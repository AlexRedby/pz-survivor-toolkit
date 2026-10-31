package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.scripting.ScriptLoadMode;
import zombie.scripting.objects.ScriptModule;
import java.util.EnumSet;
import se.krka.kahlua.integration.annotations.LuaMethod;

/**
 * Constant-time revision of registered script loading and metadata resolution.
 * Native getters rebuild shared lists and are deliberately outside this boundary.
 * Direct edits through exposed lists/maps or public metadata fields require the
 * caller's explicit Lua index invalidation; they are not native loading operations.
 */
public final class RecipeCatalogRevision {
    static final boolean SUPPORTED =
        BytecodeSupport.supports("zombie/scripting/ScriptManager.class", "8aee81a03fb7c09a9e9844ba9388a943aef9b313ea00017b8f2a33f16f4f0f99")
        && BytecodeSupport.supports("zombie/scripting/ScriptBucketCollection.class", "61ba45ea197992413af259c3736820d1669a5678f577f661956d0c3e8fbf9781")
        && BytecodeSupport.supports("zombie/scripting/ScriptBucket.class", "dc7a234f0d1fb162ef6b6ce316f16d13d87a52a93d863016abc7a7b9ba41d4dc");
    private static long revision;
    private static int changing;
    private static final long EXACT_DOUBLE_MASK = (1L << 53) - 1;

    @LuaMethod(name="toolkitRecipeCatalogRevision", global=true)
    public static Double current() { return read(SUPPORTED); }

    static synchronized Double read(boolean supported) {
        // Never let a reader persist a cache from a partially loaded catalogue.
        return supported && changing == 0 ? Double.valueOf(revision & EXACT_DOUBLE_MASK) : null;
    }

    public static synchronized void begin() {
        if (SUPPORTED) { revision++; changing++; }
    }

    public static synchronized void end() {
        if (SUPPORTED) { revision++; changing--; }
    }

    private RecipeCatalogRevision() {}

    @Patch(className="zombie.scripting.ScriptManager", methodName="loadScripts", warmUp=true, strictMatch=true)
    public static class ManagerLoadScripts {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) ScriptLoadMode mode, @Patch.Argument(1) EnumSet<?> types) { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptManager", methodName="Reset", warmUp=true, strictMatch=true)
    public static class ManagerReset {
        @Patch.OnEnter public static void enter() { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptManager", methodName="LoadedAfterLua", warmUp=true, strictMatch=true)
    public static class ManagerLoadedAfterLua {
        @Patch.OnEnter public static void enter() { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptManager", methodName="PostTileDefinitions", warmUp=true, strictMatch=true)
    public static class ManagerPostTileDefinitions {
        @Patch.OnEnter public static void enter() { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptManager", methodName="PostWorldDictionaryInit", warmUp=true, strictMatch=true)
    public static class ManagerPostWorldDictionaryInit {
        @Patch.OnEnter public static void enter() { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptBucketCollection", methodName="LoadScripts", warmUp=true, strictMatch=true)
    public static class CollectionLoadScripts {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) ScriptLoadMode mode) { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptBucketCollection", methodName="PreReloadScripts", warmUp=true, strictMatch=true)
    public static class CollectionPreReloadScripts {
        @Patch.OnEnter public static void enter() { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptBucketCollection", methodName="reset", warmUp=true, strictMatch=true)
    public static class CollectionReset {
        @Patch.OnEnter public static void enter() { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptBucketCollection", methodName="registerModule", warmUp=true, strictMatch=true)
    public static class CollectionRegisterModule {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) ScriptModule module) { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptBucketCollection", methodName="PostLoadScripts", warmUp=true, strictMatch=true)
    public static class CollectionPostLoadScripts {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) ScriptLoadMode mode) { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptBucketCollection", methodName="OnScriptsLoaded", warmUp=true, strictMatch=true)
    public static class CollectionOnScriptsLoaded {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) ScriptLoadMode mode) { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptBucketCollection", methodName="OnLoadedAfterLua", warmUp=true, strictMatch=true)
    public static class CollectionOnLoadedAfterLua {
        @Patch.OnEnter public static void enter() { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptBucketCollection", methodName="OnPostTileDefinitions", warmUp=true, strictMatch=true)
    public static class CollectionOnPostTileDefinitions {
        @Patch.OnEnter public static void enter() { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptBucketCollection", methodName="OnPostWorldDictionaryInit", warmUp=true, strictMatch=true)
    public static class CollectionOnPostWorldDictionaryInit {
        @Patch.OnEnter public static void enter() { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptBucket", methodName="LoadScripts", warmUp=true, strictMatch=true)
    public static class BucketLoadScripts {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) ScriptLoadMode mode) { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

    @Patch(className="zombie.scripting.ScriptBucket", methodName="reset", warmUp=true, strictMatch=true)
    public static class BucketReset {
        @Patch.OnEnter public static void enter() { RecipeCatalogRevision.begin(); }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit() { RecipeCatalogRevision.end(); }
    }

}

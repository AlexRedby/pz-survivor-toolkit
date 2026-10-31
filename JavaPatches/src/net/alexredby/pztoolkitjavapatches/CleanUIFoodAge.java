package net.alexredby.pztoolkitjavapatches;

import java.io.IOException;
import java.io.Reader;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.ZomboidFileSystem;
import zombie.gameStates.ChooseGameInfo;

/** Amend the reviewed compiler input, preserving Workshop files and the original renderer. */
public final class CleanUIFoodAge {
    public static final String INPUT_SHA256 = "f5992aaebc4f629fd6ebb7b049be86a3e0995ea82276b23f22cf921a18bb7cc0";
    public static final String OUTPUT_SHA256 = "a0e001a7de8cd908c1e0e95d06e551bfb8f9cc4dac7f12ed74becfd8c2cb1a74";
    public static final String TARGET = "media/lua/client/ISUI/ISInventoryPane.lua";
    public static final String VANILLA_TARGET = "media/lua/client/CleanUI/Vanilla/CleanUI_Vanilla_ISInventoryPane.lua";
    public static final String VANILLA_INPUT_SHA256 = "a122ffd45d91e87a367cfa352385ff6092774a949f494e220dd91f62c4ae9c57";
    public static final String VANILLA_OUTPUT_SHA256 = "89b5d3ba7383caccce32408d93fe26c51f1d7c83e6adb75feadb5c3d03a22411";
    private static final int MAX_SOURCE_CHARS = 1024 * 1024;
    public static final boolean SUPPORTED =
        BytecodeSupport.supports("zombie/Lua/LuaManager.class", "dcaad0082ca27a15550c7d0a6e14b3aeb71f634a14f32123dec620df180c646d")
        && BytecodeSupport.supports("se/krka/kahlua/luaj/compiler/LuaCompiler.class", "dd2b68ac4ce7a8e65cd7c3b11a3c1672a2471b824a675d4085e7b07041d4cbad")
        && BytecodeSupport.supports("zombie/ZomboidFileSystem.class", "c4e5a5123bc43d03f2585c40f37544c50c1e702eebceb78bec94069e410b6750")
        && BytecodeSupport.supports("zombie/gameStates/ChooseGameInfo.class", "8c4b47ba966f071120feeec090202967e414246e28b5b6fd6a622a6a266af651")
        && BytecodeSupport.supports("zombie/gameStates/ChooseGameInfo$Mod.class", "c91e48400b77015c450a696f2d7c5665fa872f1a76fc05d2c38e72ba2928dc69");
    private static final ThreadLocal<Scope> LOADING = new ThreadLocal<>();

    private CleanUIFoodAge() { }

    public static final class Scope {
        private final boolean candidate;
        private final String target;
        private boolean claimed;
        private Scope(String target) { this.target = target; this.candidate = target != null; }
    }

    /** Each nested load, including unrelated loads, temporarily owns its own compiler scope. */
    public static Scope begin(String file, boolean supported) {
        Scope previous = LOADING.get();
        LOADING.set(new Scope(candidateTarget(file, supported)));
        return previous;
    }

    public static void end(Scope previous) {
        if (previous == null) LOADING.remove();
        else LOADING.set(previous);
    }

    private static String candidateTarget(String file, boolean supported) {
        if (!supported || file == null) return null;
        String normalized = file.replace('\\', '/');
        String target;
        if (normalized.equals(TARGET) || normalized.endsWith("/" + TARGET)) target = TARGET;
        else if (normalized.equals(VANILLA_TARGET) || normalized.endsWith("/" + VANILLA_TARGET)) target = VANILLA_TARGET;
        else return null;
        try {
            ZomboidFileSystem files = ZomboidFileSystem.instance;
            if (!files.getModIDs().contains("CleanUI")) return null;
            ChooseGameInfo.Mod mod = ChooseGameInfo.getModDetails("CleanUI");
            if (mod == null || mod.getVersionDir() == null) return null;
            Path expected = Path.of(mod.getVersionDir()).resolve(target);
            Path resolved = Path.of(files.getString(normalized));
            return Files.isRegularFile(expected) && Files.isSameFile(expected, resolved) ? target : null;
        } catch (IOException | RuntimeException error) {
            return null;
        }
    }

    /** Pure source gate shared with the native Food differential regression. */
    public static String transformSource(String source) {
        return transformSource(TARGET, source);
    }

    /** The target and its reviewed digest must agree; a source alone cannot cross target scopes. */
    public static String transformSource(String target, String source) {
        if (source == null) return null;
        if (VANILLA_TARGET.equals(target)) return transformVanillaSource(source);
        if (!TARGET.equals(target) || !INPUT_SHA256.equals(sha256(source))) return source;
        String result = replaceOnce(source, "local CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_LIMIT = 50\n", "");
        result = replaceOnce(result,
            "    -- Large collapsed food stacks used to update dozens of items every render, even off-screen.\n"
            + "    -- Keep the extra freshness update visible-only and throttled; the first displayed item still\n"
            + "    -- follows the normal vanilla render path every frame.\n",
            "    -- Refresh every member so older food beyond the displayed header can change freshness.\n"
            + "    -- Keep this visible-only and throttled; the first displayed item still follows the\n"
            + "    -- normal vanilla render path every frame.\n");
        result = replaceOnce(result,
            "    if now ~= 0 and lastUpdate ~= 0 and (now - lastUpdate) < CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_INTERVAL_MS then return end\n",
            "    if now ~= 0 and lastUpdate ~= 0 and now >= lastUpdate and (now - lastUpdate) < CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_INTERVAL_MS then return end\n");
        result = replaceOnce(result,
            "    if itemGroup.cleanUILargeStackOptimized and maxIndex - startIndex + 1 > CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_LIMIT then\n"
            + "        maxIndex = math.min(maxIndex, startIndex + CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_LIMIT - 1)\n"
            + "    end\n", "");
        result = replaceOnce(result,
            "\nlocal function CleanUI_truncateForWeightColumn(text, width, font)\n",
            "\nCleanUI_ToolkitFoodAge = {\n"
            + "    protocol = 1,\n"
            + "    enhancedSourceSha256 = \"" + INPUT_SHA256 + "\",\n"
            + "    updateCollapsedStack = CleanUI_updateCollapsedFoodStackAge,\n"
            + "}\n\nlocal function CleanUI_truncateForWeightColumn(text, width, font)\n");
        return result != null && OUTPUT_SHA256.equals(sha256(result)) ? result : source;
    }

    private static String transformVanillaSource(String source) {
        if (!VANILLA_INPUT_SHA256.equals(sha256(source))) return source;
        String result = replaceOnce(source,
            "                    -- Update all food items in a collapsed stack so they separate when freshness changes.\n"
            + "                    for k3,v3 in ipairs(v.items) do\n"
            + "                        v3:updateAge()\n"
            + "                    end\n",
            "                    -- Preserve off-screen ageing while sharing CleanUI's one-second full-stack updater.\n"
            + "                    local foodAge = CleanUI_ToolkitFoodAge\n"
            + "                    if type(foodAge) == \"table\" and foodAge.protocol == 1\n"
            + "                            and foodAge.enhancedSourceSha256 == \"" + INPUT_SHA256 + "\"\n"
            + "                            and type(foodAge.updateCollapsedStack) == \"function\" then\n"
            + "                        foodAge.updateCollapsedStack(v, true)\n"
            + "                    else\n"
            + "                        -- Unknown or unpatched enhanced sources retain the original vanilla work.\n"
            + "                        for k3,v3 in ipairs(v.items) do\n"
            + "                            v3:updateAge()\n"
            + "                        end\n"
            + "                    end\n");
        return result != null && VANILLA_OUTPUT_SHA256.equals(sha256(result)) ? result : source;
    }

    private static String replaceOnce(String source, String before, String after) {
        if (source == null) return null;
        int start = source.indexOf(before);
        if (start < 0 || source.indexOf(before, start + before.length()) >= 0) return null;
        return source.substring(0, start) + after + source.substring(start + before.length());
    }

    private static String sha256(String source) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(source.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException error) {
            throw new AssertionError(error);
        }
    }

    /** The native RunLua owner still closes its original reader, including on compilation failure. */
    public static Reader compilerInput(Reader reader, String name, boolean supported) throws IOException {
        Scope scope = LOADING.get();
        if (!supported || scope == null || !scope.candidate || scope.claimed
                || !scope.target.substring(scope.target.lastIndexOf('/') + 1).equals(name)) return reader;
        scope.claimed = true;
        StringBuilder source = new StringBuilder();
        char[] buffer = new char[8192];
        while (source.length() <= MAX_SOURCE_CHARS) {
            int count = reader.read(buffer, 0, Math.min(buffer.length, MAX_SOURCE_CHARS + 1 - source.length()));
            if (count < 0) {
                String original = source.toString();
                String transformed = transformSource(scope.target, original);
                if (transformed != original) System.out.println("[PZToolkitJavaPatches] CleanUI food-age compiler input corrected");
                // An unknown complete source must be replayed from its beginning, too.
                return new StringReader(transformed);
            }
            if (count == 0) {
                int next = reader.read();
                if (next < 0) return new StringReader(transformSource(scope.target, source.toString()));
                source.append((char) next);
            } else source.append(buffer, 0, count);
        }
        // A larger future source is not a patch candidate. Replay what we read before its tail.
        return new ReplayReader(source.toString(), reader);
    }

    private static final class ReplayReader extends Reader {
        private final StringReader prefix;
        private final Reader tail;
        private boolean prefixDone;
        private ReplayReader(String prefix, Reader tail) { this.prefix = new StringReader(prefix); this.tail = tail; }
        @Override public int read(char[] buffer, int offset, int length) throws IOException {
            if (!prefixDone) {
                int count = prefix.read(buffer, offset, length);
                if (count >= 0) return count;
                prefixDone = true;
            }
            return tail.read(buffer, offset, length);
        }
        @Override public void close() throws IOException { tail.close(); }
    }

    @Patch(className="zombie.Lua.LuaManager", methodName="RunLua", warmUp=true, strictMatch=true)
    public static class LoadingSource {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                                 @Patch.Local("toolkitCleanUIFoodAge") Scope previous) {
            previous = begin(file, SUPPORTED);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Argument(0) String file, @Patch.Argument(1) boolean rewrite,
                                @Patch.Local("toolkitCleanUIFoodAge") Scope previous) {
            end(previous);
        }
    }

    @Patch(className="se.krka.kahlua.luaj.compiler.LuaCompiler", methodName="loadis", warmUp=true, strictMatch=true)
    public static class CompilingSource {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(value=0, readOnly=false) Reader reader,
                                 @Patch.Argument(1) String name,
                                 @Patch.Argument(2) se.krka.kahlua.vm.KahluaTable environment) throws IOException {
            reader = compilerInput(reader, name, SUPPORTED);
        }
    }
}

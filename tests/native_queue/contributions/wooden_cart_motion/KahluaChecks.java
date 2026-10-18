import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaThread;

public final class KahluaChecks {
    private static void checkKeys() {
        var core=zombie.core.Core.getInstance();
        String[] actions={"Forward","Left","Right","Backward","Run","Sprint"};
        int[] keys={17,30,32,31,42,56};
        for(int i=0;i<actions.length;i++) core.addKeyBinding(actions[i],keys[i],0,false,false,false);
        int[] directions={0,1,2,4,8,3,10,12,5};
        for(int drive=0;drive<=8;drive++) for(int gait=0;gait<=2;gait++) {
            net.alexredby.cartlab.Main.drive=drive;net.alexredby.cartlab.Main.gait=gait;
            for(int i=0;i<keys.length;i++) {
                boolean expected=i<4?(directions[drive]&(1<<i))!=0:i==4?gait==1:gait==2;
                if(net.alexredby.cartlab.Main.fixtureKey(keys[i])!=expected)
                    throw new AssertionError("Independent direction/modifier input changed: drive="+drive+" gait="+gait+" action="+actions[i]);
            }
        }
        net.alexredby.cartlab.Main.drive=-1;
        if(net.alexredby.cartlab.Main.Keys.enter(keys[4],false)
                || net.alexredby.cartlab.Main.RawKeys.enter(keys[4],false))
            throw new AssertionError("Manual mode must leave native keyboard input untouched");
        net.alexredby.cartlab.Main.gait=0;
        System.out.println("CART_INDEPENDENT_KEYS_PASS");
    }

    public static void main(String[] args) throws Exception {
        checkKeys();
        boolean pad = "true".equals(System.getenv("PZ_CART_TEST_PAD"));
        for (int original : new int[]{5, 13, 19, 25, 27}) {
            zombie.iso.IsoChunkMap.chunkGridWidth = original;
            zombie.iso.IsoChunkMap.chunkWidthInTiles = original * 8;
            net.alexredby.cartlab.Main.PadChunks.exit();
            int width = zombie.iso.IsoChunkMap.chunkGridWidth;
            if (width != (pad ? Math.max(25, original) : original)
                    || zombie.iso.IsoChunkMap.chunkWidthInTiles != width * 8)
                throw new AssertionError("Chunk window guard or wider native map changed");
            if (pad) for (int origin = 0; origin < 8; origin++) {
                for (int tile = origin + 2; tile < origin + 94; tile++) {
                    int min = (Math.floorDiv(tile, 8) - width / 2) * 8;
                    if (min > origin || min + width * 8 <= origin + 95)
                        throw new AssertionError("Pad edge can unload at safe tile " + tile);
                }
            }
        }
        System.out.println("CART_CHUNK_WINDOW_PASS enabled=" + pad);
        var platform=J2SEPlatform.getInstance();
        var environment=platform.newEnvironment();
        var thread=new KahluaThread(System.out,platform,environment);
        thread.debugOwnerThread=Thread.currentThread();
        Object[] result;
        environment.rawset("ProjectRoot",Path.of(args[0]).toAbsolutePath().toString());
        environment.rawset("dofile",(JavaFunction)(frame,count)->{
            try(var reader=Files.newBufferedReader(Path.of((String)frame.get(0)))) {
                var closure=LuaCompiler.loadis(reader,(String)frame.get(0),environment);
                return frame.push(frame.getThread().call(closure,new Object[0]));
            } catch(java.io.IOException error) {throw new RuntimeException(error);}
        });
        try(var reader=Files.newBufferedReader(Path.of(args[0],"tests/test_cart_obstacles.lua"))) {
            result=thread.pcall(LuaCompiler.loadis(reader,"test_cart_obstacles.lua",environment),new Object[0]);
            if(!Boolean.TRUE.equals(result[0])) throw new AssertionError(Arrays.toString(result));
        }
        System.out.println("KAH_LUA_CART_OBSTACLES_PASS (stock game VM, stub world, no native launch)");
    }
}

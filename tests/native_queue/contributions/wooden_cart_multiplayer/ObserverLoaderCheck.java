/** Match normal mod loading after core RNG initialization, before test actors exist. */
public final class ObserverLoaderCheck {
    public static void main(String[] args)throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        if(args[1].equals("LeaseCostCheck"))Class.forName("zombie.network.GameServer",true,ObserverLoaderCheck.class.getClassLoader());
        var phase=Class.forName("me.zed_0xff.zombie_buddy.Loader$Phase");
        var constant=phase.getDeclaredField("MAIN");constant.setAccessible(true);
        var loader=Class.forName("me.zed_0xff.zombie_buddy.Loader");
        var load=loader.getDeclaredMethod("loadJar",java.nio.file.Path.class,String.class,String.class,phase);load.setAccessible(true);
        if(!Boolean.TRUE.equals(load.invoke(null,java.nio.file.Path.of(args[0]),"net.alexredby.cartlab",java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(java.nio.file.Files.readAllBytes(java.nio.file.Path.of(args[0])))),constant.get(null))))
            throw new AssertionError("Native mod loader refused CartLab");
        Class.forName(args[1]).getMethod("main",String[].class).invoke(null,(Object)java.util.Arrays.copyOfRange(args,2,args.length));
    }
}

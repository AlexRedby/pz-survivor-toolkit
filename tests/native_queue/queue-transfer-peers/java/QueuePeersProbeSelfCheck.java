package net.alexredby.queuepeersprobe;

import java.util.HashMap;
import java.util.List;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;

/** Offline gate/transform verification. Does not start native game state. */
public final class QueuePeersProbeSelfCheck {
    private static java.lang.instrument.Instrumentation instrumentation;
    public static void premain(String arguments,java.lang.instrument.Instrumentation value) {
        instrumentation=value;
    }
    private static byte[] resource(String name) throws Exception {
        try (var input=Main.class.getClassLoader().getResourceAsStream(name+".class")) {
            if (input==null) throw new AssertionError("missing "+name);
            return input.readAllBytes();
        }
    }
    private static void check(boolean condition,String message) {
        if (!condition) throw new AssertionError(message);
    }
    private static java.util.Map<String,Integer> nativeInstructions(byte[] bytes) {
        var result=new HashMap<String,Integer>();
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int access,String method,String descriptor,String signature,String[] exceptions) {
                return new MethodVisitor(Opcodes.ASM9) {
                    @Override public void visitMethodInsn(int opcode,String owner,String target,String desc,boolean itf) {
                        if (!owner.equals("net/alexredby/queuepeersprobe/Main"))
                            result.merge(method+":"+opcode+":"+owner+":"+target+":"+desc,1,Integer::sum);
                    }
                    @Override public void visitFieldInsn(int opcode,String owner,String field,String desc) {
                        result.merge(method+":"+opcode+":"+owner+":"+field+":"+desc,1,Integer::sum);
                    }
                };
            }
        },0);
        return result;
    }
    private static se.krka.kahlua.vm.LuaClosure originClosure(String filename,String name,Object[] constants,int upvalues,
            se.krka.kahlua.vm.KahluaTable env) {
        var p=new se.krka.kahlua.vm.Prototype(); p.filename=filename; p.name=name; p.constants=constants;
        p.numUpvalues=upvalues; p.numParams=upvalues==0 ? 2 : 0; p.isVararg=upvalues!=0;
        p.prototypes=new se.krka.kahlua.vm.Prototype[0]; p.lines=new int[0]; p.code=new int[0];
        return new se.krka.kahlua.vm.LuaClosure(p,env);
    }
    private static void cell(se.krka.kahlua.vm.LuaClosure closure,int index,Object value) {
        var up=new se.krka.kahlua.vm.UpValue(null,index); up.setValue(value); closure.upvalues[index]=up;
    }
    private static void originChecks(String[] sources) throws Exception {
        var env=new se.krka.kahlua.j2se.J2SEPlatform().newTable();
        var owner=new se.krka.kahlua.j2se.J2SEPlatform().newTable();
        Object[] nativeConstants={"ISInventoryPane","getActualItems","getSpecificPlayer","getPlayerInventory","inventory","ipairs",
            "instanceof","InventoryItem","items",2.0,1.0,"getContainer","luautils","walkToContainer","isHumanCorpse","ISTimedActionQueue",
            "add","ISGrabCorpseItem","new","ISInventoryTransferUtil","newInventoryTransferAction"};
        env.rawset("ISInventoryPaneContextMenu",owner);
        Object[] wrapperConstants={6.0,"kind","player",1.0,"chr","getSpecificPlayer",2.0,"records","pcall","ipairs","enqueued","equip",
            "action","accepted",true,"pending","finished",null,"error",0.0,"unpack","n"};
        Object[] retentionConstants={"onMoveItemsTo","select",2.0,1.0,"type","table","selectionAllowsStuck","filterTransfer"};
        var toolkit=new se.krka.kahlua.j2se.J2SEPlatform().newTable();
        var retained=new se.krka.kahlua.j2se.J2SEPlatform().newTable();
        var protection=new se.krka.kahlua.j2se.J2SEPlatform().newTable();
        var selection=originClosure("InventoryTransferProtection.lua","selectionAllowsStuck",new Object[]{"player","items",null},3,env);
        selection.prototype.numParams=2; selection.prototype.isVararg=false;
        var filter=originClosure("ItemRetentionUI.lua","filterTransfer",new Object[]{"ipairs","allowsAutomatic",1.0},2,env);
        filter.prototype.numParams=2; filter.prototype.isVararg=false;
        protection.rawset("selectionAllowsStuck",selection); retained.rawset("filterTransfer",filter);
        toolkit.rawset("ItemRetention",retained); toolkit.rawset("InventoryTransferProtection",protection); env.rawset("PZSurvivorToolkit",toolkit);
        var retentionWrapper=originClosure("ItemRetentionUI.lua","wrapper",retentionConstants,4,env); retentionWrapper.prototype.numParams=1;
        var nativeGrab=originClosure("ISInventoryPaneContextMenu.lua","onGrabItems",nativeConstants,0,env);
        var wrapper=originClosure("ActionQueueTidyIntent.lua","replacement",wrapperConstants,13,env);
        // Optional actual source compilation checks every pinned constant and
        // native compiler descriptor without running either source chunk.
        for (int i=0;i<Math.min(sources.length,4);i++) {
            String filename=i==0 ? "ISInventoryPaneContextMenu.lua" : i==1 ? "ActionQueueTidyIntent.lua" : i==2 ? "ItemRetentionUI.lua" : "InventoryTransferProtection.lua";
            Object[] expectedConstants=i==0 ? nativeConstants : i==1 ? wrapperConstants : i==2 ? retentionConstants : new Object[]{"player","items",null};
            String old=org.luaj.kahluafork.compiler.FuncState.currentFile;
            String oldFull=org.luaj.kahluafork.compiler.FuncState.currentfullFile;
            se.krka.kahlua.vm.LuaClosure chunk;
            try {
                org.luaj.kahluafork.compiler.FuncState.currentFile=filename;
                org.luaj.kahluafork.compiler.FuncState.currentfullFile=filename;
                chunk=se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring(java.nio.file.Files.readString(java.nio.file.Path.of(sources[i])),filename,env);
            } finally { org.luaj.kahluafork.compiler.FuncState.currentFile=old; org.luaj.kahluafork.compiler.FuncState.currentfullFile=oldFull; }
            var pending=new java.util.ArrayDeque<se.krka.kahlua.vm.Prototype>(); pending.add(chunk.prototype);
            se.krka.kahlua.vm.Prototype match=null;
            while (!pending.isEmpty()) {
                var p=pending.remove();
                if (java.util.Arrays.equals(p.constants,expectedConstants)) {
                    check(match==null,"ambiguous original source prototype"); match=p;
                }
                if (i==2 && "filterTransfer".equals(p.name)) {
                    filter=new se.krka.kahlua.vm.LuaClosure(p,env); retained.rawset("filterTransfer",filter);
                }
                pending.addAll(java.util.Arrays.asList(p.prototypes));
            }
            check(match!=null,"actual source constants changed "+filename);
            if (i==0) nativeGrab=new se.krka.kahlua.vm.LuaClosure(match,env);
            else if (i==1) wrapper=new se.krka.kahlua.vm.LuaClosure(match,env);
            else if (i==2) retentionWrapper=new se.krka.kahlua.vm.LuaClosure(match,env);
            else { selection=new se.krka.kahlua.vm.LuaClosure(match,env); protection.rawset("selectionAllowsStuck",selection); }
        }
        owner.rawset("onGrabItems",nativeGrab);
        check(Main.grabOriginal(nativeGrab,owner)==nativeGrab,"direct native grab rejected");
        owner.rawset("onGrabItems",wrapper); cell(wrapper,0,owner); cell(wrapper,1,"onGrabItems"); cell(wrapper,2,nativeGrab);
        cell(wrapper,3,(se.krka.kahlua.vm.JavaFunction)(frame,count)->{throw new AssertionError("origin checker invoked callback");});
        cell(wrapper,4,wrapper);
        check(Main.grabOriginal(wrapper,owner)==nativeGrab,"exact direct wrapper rejected");
        cell(retentionWrapper,0,"onGrabItems"); cell(retentionWrapper,1,protection); cell(retentionWrapper,2,nativeGrab); cell(retentionWrapper,3,retained);
        owner.rawset("onGrabItems",retentionWrapper);
        check(Main.grabOriginal(retentionWrapper,owner)==nativeGrab,"Retention direct native wrapper rejected");
        cell(retentionWrapper,2,wrapper);
        check(Main.grabOriginal(retentionWrapper,owner)==nativeGrab,"Retention -> Tidy -> native chain rejected");
        owner.rawset("onGrabItems",wrapper); cell(wrapper,2,retentionWrapper); cell(retentionWrapper,2,nativeGrab);
        check(Main.grabOriginal(wrapper,owner)==nativeGrab,"Tidy -> Retention -> native chain rejected");
        cell(wrapper,2,nativeGrab); owner.rawset("onGrabItems",retentionWrapper);
        protection.rawset("selectionAllowsStuck",(se.krka.kahlua.vm.JavaFunction)(frame,count)->{throw new AssertionError("changed helper invoked");});
        check(Main.grabOriginal(retentionWrapper,owner)==null,"changed dynamic selection helper accepted"); protection.rawset("selectionAllowsStuck",selection);
        var equivalent=new se.krka.kahlua.vm.LuaClosure(filter.prototype,env); retained.rawset("filterTransfer",equivalent);
        check(Main.grabOriginal(retentionWrapper,owner)==null,"shape-equivalent replaced filter helper accepted"); retained.rawset("filterTransfer",filter);
        var foreignProtection=new se.krka.kahlua.j2se.J2SEPlatform().newTable();
        cell(retentionWrapper,1,foreignProtection); check(Main.grabOriginal(retentionWrapper,owner)==null,"foreign Protection captured table accepted"); cell(retentionWrapper,1,protection);
        toolkit.rawset("ItemRetention",foreignProtection); check(Main.grabOriginal(retentionWrapper,owner)==null,"retired Retention table accepted"); toolkit.rawset("ItemRetention",retained);
        cell(retentionWrapper,0,"onGrabHalfItems"); check(Main.grabOriginal(retentionWrapper,owner)==null,"Retention wrong method accepted"); cell(retentionWrapper,0,"onGrabItems");
        cell(retentionWrapper,2,retentionWrapper); check(Main.grabOriginal(retentionWrapper,owner)==null,"self-referential Retention callback accepted"); cell(retentionWrapper,2,nativeGrab);
        var otherRetention=originClosure("ItemRetentionUI.lua","wrapper",retentionConstants,4,env); otherRetention.prototype.numParams=1;
        cell(otherRetention,0,"onGrabItems"); cell(otherRetention,1,protection); cell(otherRetention,2,nativeGrab); cell(otherRetention,3,retained);
        cell(retentionWrapper,2,otherRetention); check(Main.grabOriginal(retentionWrapper,owner)==null,"duplicate Retention layer accepted"); cell(retentionWrapper,2,nativeGrab);
        var environment=new se.krka.kahlua.j2se.J2SEPlatform().newTable(); var changedEnv=originClosure("ISInventoryPaneContextMenu.lua","onGrabItems",nativeConstants,0,environment);
        cell(retentionWrapper,2,changedEnv); check(Main.grabOriginal(retentionWrapper,owner)==null,"foreign callback environment accepted"); cell(retentionWrapper,2,nativeGrab);
        var diagnostic=Main.grabOriginSnapshot();
        check(Boolean.FALSE.equals(diagnostic.rawget("supported")) && "callback-environment-mismatch".equals(diagnostic.rawget("reason"))
            && diagnostic.rawget("chain") instanceof String,"scalar descriptive chain diagnostics missing");
        owner.rawset("onGrabItems",wrapper);
        var foreign=new se.krka.kahlua.j2se.J2SEPlatform().newTable(); foreign.rawset("onGrabItems",wrapper);
        check(Main.grabOriginal(wrapper,foreign)==null,"foreign captured owner accepted");
        cell(wrapper,1,"onGrabOneItems"); check(Main.grabOriginal(wrapper,owner)==null,"foreign captured name accepted"); cell(wrapper,1,"onGrabItems");
        cell(wrapper,5,nativeGrab); check(Main.grabOriginal(wrapper,owner)==null,"multiple callback cells accepted"); cell(wrapper,5,null);
        var mask=originClosure("ActionQueueTidyIntent.lua","replacement",wrapperConstants,13,env); cell(mask,0,nativeGrab);
        cell(wrapper,2,mask); check(Main.grabOriginal(wrapper,owner)==null,"masked/deeper native callback accepted"); cell(wrapper,2,nativeGrab);
        var wrong=originClosure("Foreign.lua","onGrabItems",nativeConstants,0,env);
        cell(wrapper,2,wrong); check(Main.grabOriginal(wrapper,owner)==null,"foreign native callback source accepted"); cell(wrapper,2,nativeGrab);
        owner.rawset("onGrabItems",nativeGrab); check(Main.grabOriginal(wrapper,owner)==null,"retired wrapper accepted");
        var sibling=originClosure("ISInventoryPaneContextMenu.lua","onGrabOneItems",nativeConstants,0,env); owner.rawset("onGrabItems",sibling);
        check(Main.grabOriginal(sibling,owner)==null,"foreign same-file sibling accepted");
        var constants=nativeConstants.clone(); constants[1]="maskedHelper";
        var altered=originClosure("ISInventoryPaneContextMenu.lua","onGrabItems",constants,0,env); owner.rawset("onGrabItems",altered);
        check(Main.grabOriginal(altered,owner)==null,"changed native helper constants accepted");
        check(Main.grabOriginal(null,owner)==null && Main.grabOriginal(nativeGrab,null)==null,"missing origin arguments accepted");
        System.out.println("PASS bounded native/Tidy/Retention origin, compiled source constants, identity/name/foreign/cycle/duplicate guards and scalar diagnostics (no callbacks)");
    }
    private static se.krka.kahlua.vm.LuaClosure compileOrigin(String source,String filename,se.krka.kahlua.vm.KahluaTable env) throws Exception {
        String file=org.luaj.kahluafork.compiler.FuncState.currentFile, full=org.luaj.kahluafork.compiler.FuncState.currentfullFile;
        try {
            org.luaj.kahluafork.compiler.FuncState.currentFile=filename;
            org.luaj.kahluafork.compiler.FuncState.currentfullFile=filename;
            return se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring(source,filename,env);
        } finally { org.luaj.kahluafork.compiler.FuncState.currentFile=file; org.luaj.kahluafork.compiler.FuncState.currentfullFile=full; }
    }
    private static se.krka.kahlua.vm.Prototype originNamed(se.krka.kahlua.vm.Prototype p,String name) {
        if (name.equals(p.name)) return p;
        for (var child:p.prototypes) { var match=originNamed(child,name); if (match!=null) return match; }
        return null;
    }
    private static void realFactoryChecks(String[] sources) throws Exception {
        if (sources.length<4) return;
        var platform=new se.krka.kahlua.j2se.J2SEPlatform(); var env=platform.newTable(); var owner=platform.newTable();
        var toolkit=platform.newTable(); var retained=platform.newTable(); var protection=platform.newTable();
        env.rawset("ISInventoryPaneContextMenu",owner); env.rawset("PZSurvivorToolkit",toolkit);
        toolkit.rawset("ItemRetention",retained); toolkit.rawset("InventoryTransferProtection",protection);
        se.krka.kahlua.stdlib.BaseLib.register(env);
        var thread=new se.krka.kahlua.vm.KahluaThread(platform,env); thread.debugOwnerThread=Thread.currentThread();
        env.rawset("ipairs",(se.krka.kahlua.vm.JavaFunction)(frame,count)->{
            frame.push((se.krka.kahlua.vm.JavaFunction)(inner,n)->{
                var table=(se.krka.kahlua.vm.KahluaTable)inner.get(0); double i=((Double)inner.get(1))+1;
                Object value=table.rawget(i); if (value==null) return 0; inner.push(i); inner.push(value); return 2;
            }); frame.push(frame.get(0)); frame.push(0.0); return 3;
        });
        var classes=platform.newTable(); classes.rawset("panes",(se.krka.kahlua.vm.JavaFunction)(frame,count)->0); env.rawset("fixtureClasses",classes);
        var calls=new int[1];
        se.krka.kahlua.vm.JavaFunction forbidden=(frame,count)->{calls[0]++; throw new AssertionError("gameplay callback/helper invoked");};
        for (String name:List.of("getSpecificPlayer","getPlayerInventory","instanceof")) env.rawset(name,forbidden);
        String nativeSource=java.nio.file.Files.readString(java.nio.file.Path.of(sources[0]));
        String tidySource=java.nio.file.Files.readString(java.nio.file.Path.of(sources[1]));
        String retentionSource=java.nio.file.Files.readString(java.nio.file.Path.of(sources[2]));
        String protectionSource=java.nio.file.Files.readString(java.nio.file.Path.of(sources[3]));
        var selection=originNamed(compileOrigin(protectionSource,"InventoryTransferProtection.lua",env).prototype,"selectionAllowsStuck");
        var filter=originNamed(compileOrigin(retentionSource,"ItemRetentionUI.lua",env).prototype,"filterTransfer");
        protection.rawset("selectionAllowsStuck",new se.krka.kahlua.vm.LuaClosure(selection,env));
        retained.rawset("filterTransfer",new se.krka.kahlua.vm.LuaClosure(filter,env));
        String tidyFactory="local pack,guard,wrappedUI,state,confirm=nil,nil,nil,nil,nil\nlocal scope=nil;local watching={}\n"
            +tidySource.substring(tidySource.indexOf("local function wrap(owner,name,kind,hotbar)"),tidySource.indexOf("function Intent.install("))+"return wrap";
        String retentionFactory="local Classes=fixtureClasses;local installPane;local actionHooks={};local actionNames={'onGrabItems'};local menuHook,itemsIn,rememberMenu\n"
            +"local Retention=PZSurvivorToolkit.ItemRetention;local Protection=PZSurvivorToolkit.InventoryTransferProtection\n"
            +retentionSource.substring(retentionSource.indexOf("local function install()"),retentionSource.indexOf("Retention.install = install"))+"return install";
        var wrap=(se.krka.kahlua.vm.LuaClosure)thread.call(compileOrigin(tidyFactory,"ActionQueueTidyIntent.lua",env),new Object[0]);
        var install=(se.krka.kahlua.vm.LuaClosure)thread.call(compileOrigin(retentionFactory,"ItemRetentionUI.lua",env),new Object[0]);
        int variants=sources.length>=5 ? 2 : 1;
        for (int variant=0;variant<variants;variant++) {
            String source=variant==0 ? nativeSource : java.nio.file.Files.readString(java.nio.file.Path.of(sources[4]));
            int start=source.indexOf(variant==0 ? "ISInventoryPaneContextMenu.onGrabItems = function" : "local function CleanUI_getValidTransferContainer(item)");
            int end=source.indexOf("ISInventoryPaneContextMenu.onGrabOneItems",start);
            check(start>=0 && end>start,"actual selected producer source slice missing");
            thread.call(compileOrigin(source.substring(start,end),"ISInventoryPaneContextMenu.lua",env),new Object[0]);
            var leaf=(se.krka.kahlua.vm.LuaClosure)owner.rawget("onGrabItems");
            if (variant==1) check(leaf.upvalues.length==1 && !java.util.Arrays.asList(leaf.prototype.constants).contains("getContainer"),
                "CleanUI root cause: stock-only zero-upvalue/getContainer gate must reject reviewed source");
            check(Main.grabOriginal(leaf,owner)==leaf,"actual direct producer rejected");
            thread.call(wrap,new Object[]{owner,"onGrabItems","grab",null});
            var tidy=(se.krka.kahlua.vm.LuaClosure)owner.rawget("onGrabItems");
            int self=0; se.krka.kahlua.vm.UpValue selfCell=null;
            for (var cell:tidy.upvalues) if (cell.getValue()==tidy) { self++; selfCell=cell; }
            check(self==1,"actual Tidy factory must bind one exact self cell");
            thread.call(install,new Object[0]);
            var outer=(se.krka.kahlua.vm.LuaClosure)owner.rawget("onGrabItems");
            check(Main.grabOriginal(outer,owner)==leaf,"actual Retention -> Tidy -> leaf rejected: "+Main.grabOriginSnapshot().rawget("reason"));
            check((variant==0 ? "stock" : "cleanui-reviewed").equals(Main.grabOriginSnapshot().rawget("leaf")),"actual leaf provenance variant missing");
            selfCell.setValue(outer);
            check(Main.grabOriginal(outer,owner)==null,"actual Tidy self cell replaced by outer cycle accepted"); selfCell.setValue(tidy);
            check(Main.grabOriginal(outer,owner)==leaf,"restored exact self cell rejected");
            if (variant==1) {
                int instruction=leaf.prototype.code[0]; leaf.prototype.code[0]^=1;
                check(Main.grabOriginal(outer,owner)==null,"changed CleanUI leaf instructions accepted"); leaf.prototype.code[0]=instruction;
                var helper=leaf.upvalues[0].getValue();
                leaf.upvalues[0].setValue(new se.krka.kahlua.vm.LuaClosure(((se.krka.kahlua.vm.LuaClosure)helper).prototype,env));
                check(Main.grabOriginal(outer,owner)==null,"replaced CleanUI source helper identity accepted"); leaf.upvalues[0].setValue(helper);
                var child=((se.krka.kahlua.vm.LuaClosure)helper).prototype.prototypes[0]; var constants=child.constants;
                child.constants=new Object[]{"foreignContainer"}; check(Main.grabOriginal(outer,owner)==null,"changed nested CleanUI container helper accepted"); child.constants=constants;
                check(Main.grabOriginal(outer,owner)==leaf,"restored CleanUI helper rejected");
            }
            // Rebuild both factories so captured install hooks are fresh and
            // exercise the other legitimate construction order as well.
            owner.rawset("onGrabItems",leaf);
            install=(se.krka.kahlua.vm.LuaClosure)thread.call(compileOrigin(retentionFactory,"ItemRetentionUI.lua",env),new Object[0]);
            thread.call(install,new Object[0]); thread.call(wrap,new Object[]{owner,"onGrabItems","grab",null});
            check(Main.grabOriginal(owner.rawget("onGrabItems"),owner)==leaf,"actual Tidy -> Retention -> leaf rejected");
            install=(se.krka.kahlua.vm.LuaClosure)thread.call(compileOrigin(retentionFactory,"ItemRetentionUI.lua",env),new Object[0]);
        }
        check(calls[0]==0,"source factory setup invoked gameplay producer/helper");
        System.out.println("PASS actual source factory construction, exact self cells, selected stock/CleanUI leaf, both wrapper orders and helper identity guards (no gameplay calls)");
    }
    private static java.lang.reflect.Field fixtureField(Class<?> type,String name) throws Exception {
        var field=type.getDeclaredField(name); field.setAccessible(true); return field;
    }
    private static int fullyConnectedCalls(String name) throws Exception {
        int[] calls={0};
        new ClassReader(resource(name)).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int access,String method,String descriptor,String signature,String[] exceptions) {
                return new MethodVisitor(Opcodes.ASM9) {
                    @Override public void visitMethodInsn(int opcode,String owner,String target,String desc,boolean itf) {
                        if ((owner.equals("zombie/core/raknet/UdpConnection") || owner.equals("zombie/network/IConnection"))
                                && target.equals("setFullyConnected")) calls[0]++;
                    }
                };
            }
        },0);
        return calls[0];
    }
    private static void nativeArmBoundaryChecks() throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        check(fullyConnectedCalls("zombie/network/GameClient")==0,"client unexpectedly writes server fullyConnected flag");
        check(fullyConnectedCalls("zombie/network/GameServer")>0,"native server fullyConnected setter missing");
        var unsafeField=sun.misc.Unsafe.class.getDeclaredField("theUnsafe"); unsafeField.setAccessible(true);
        var unsafe=(sun.misc.Unsafe)unsafeField.get(null);
        var actor=(zombie.characters.IsoPlayer)unsafe.allocateInstance(zombie.characters.IsoPlayer.class);
        var wire=(zombie.core.raknet.UdpConnection)unsafe.allocateInstance(zombie.core.raknet.UdpConnection.class);
        var otherWire=(zombie.core.raknet.UdpConnection)unsafe.allocateInstance(zombie.core.raknet.UdpConnection.class);
        var first=(zombie.inventory.InventoryItem)unsafe.allocateInstance(zombie.inventory.InventoryItem.class); first.setID(1753422528);
        var second=(zombie.inventory.InventoryItem)unsafe.allocateInstance(zombie.inventory.InventoryItem.class); second.setID(2121748602);
        var source=fixtureField(Main.class,"sourceExact"); var history=fixtureField(Main.class,"historyFromConnectionStart");
        var partial=fixtureField(Main.class,"partial"); var epoch=Main.class.getDeclaredMethod("partialEpoch"); epoch.setAccessible(true);
        Object oldPartial=partial.get(null); boolean oldSource=source.getBoolean(null),oldHistory=history.getBoolean(null);
        boolean oldClient=zombie.network.GameClient.client, oldServer=zombie.network.GameServer.server;
        boolean oldConnected=zombie.network.GameClient.instance.connected;
        var oldConnection=zombie.network.GameClient.connection; var oldEnv=zombie.Lua.LuaManager.env;
        int oldPlayers=zombie.characters.IsoPlayer.numPlayers; var players=zombie.characters.IsoPlayer.players.clone();
        var oldEngine=zombie.network.GameServer.udpEngine; var oldActor=zombie.network.GameServer.IDToPlayerMap.get((short)0);
        Long oldAddress=zombie.network.GameServer.PlayerToAddressMap.get(actor);
        try {
            source.setBoolean(null,true); history.setBoolean(null,true);
            zombie.network.GameClient.client=true; zombie.network.GameServer.server=false;
            zombie.network.GameClient.instance.connected=true; zombie.network.GameClient.connection=wire;
            zombie.characters.IsoPlayer.numPlayers=1; zombie.characters.IsoPlayer.players[0]=actor;
            check(actor.isLocalPlayer() && !wire.isFullyConnected(),"headless client role fixture differs from native flags");
            var platform=new se.krka.kahlua.j2se.J2SEPlatform(); var env=platform.newTable();
            var thread=new se.krka.kahlua.vm.KahluaThread(platform,env); thread.debugOwnerThread=Thread.currentThread();
            var converter=new se.krka.kahlua.converter.KahluaConverterManager(); zombie.Lua.KahluaNumberConverter.install(converter);
            var exposer=new zombie.Lua.LuaManager.Exposer(converter,platform,env);
            exposer.exposeGlobalObjectFunction(env,first,zombie.inventory.InventoryItem.class.getMethod("getID"),"nativeFirstId");
            exposer.exposeGlobalObjectFunction(env,second,zombie.inventory.InventoryItem.class.getMethod("getID"),"nativeSecondId");
            check(env.rawget("nativeFirstId") instanceof se.krka.kahlua.integration.expose.LuaJavaInvoker,"real native invoker missing");
            env.rawset("actor",actor); zombie.Lua.LuaManager.env=env; Main.partialBindings();
            env.rawset("checkNumberClass",(se.krka.kahlua.vm.JavaFunction)(frame,count)->frame.push(frame.get(0) instanceof Double && frame.get(1) instanceof Double));
            check(Boolean.TRUE.equals(thread.call(compileOrigin("return checkNumberClass(nativeFirstId(),nativeSecondId())","arm-boundary.lua",env),new Object[0])),
                "actual InventoryItem.getID converter does not return Double");
            Object rejected=thread.call(compileOrigin("return queuePeersArmPartialClient(actor,'wrong',nativeSecondId(),'queue-peers:1794236736919:4')","arm-boundary.lua",env),new Object[0]);
            check(Boolean.FALSE.equals(rejected) && "numeric-id-class-or-range".equals(Main.partialArmSnapshot().rawget("reason")),"typed boundary rejection lacks exact reason");
            zombie.network.GameClient.instance.connected=false;
            rejected=thread.call(compileOrigin("return queuePeersArmPartialClient(actor,nativeFirstId(),nativeSecondId(),'queue-peers:1794236736919:4')","arm-boundary.lua",env),new Object[0]);
            check(Boolean.FALSE.equals(rejected) && "client-instance-not-connected".equals(Main.partialArmSnapshot().rawget("reason")),"disconnected client did not fail exact role guard");
            zombie.network.GameClient.instance.connected=true;
            Object accepted=thread.call(compileOrigin("return queuePeersArmPartialClient(actor,nativeFirstId(),nativeSecondId(),'queue-peers:1794236736919:4')","arm-boundary.lua",env),new Object[0]);
            var diagnostic=Main.partialArmSnapshot();
            check(Boolean.TRUE.equals(accepted) && Boolean.TRUE.equals(diagnostic.rawget("accepted")) && "".equals(diagnostic.rawget("reason")),
                "real native Lua/Java numeric boundary arm failed");
            check("java.lang.Double".equals(diagnostic.rawget("firstClass")) && "java.lang.Double".equals(diagnostic.rawget("secondClass"))
                && Boolean.FALSE.equals(diagnostic.rawget("serverFullyConnectedFlag")) && Boolean.FALSE.equals(diagnostic.rawget("scopePresent")),
                "native argument/role/scope scalar diagnostics differ");
            var iterator=diagnostic.iterator();
            while (iterator.advance()) check(iterator.getValue() instanceof String || iterator.getValue() instanceof Double || iterator.getValue() instanceof Boolean,
                "arm diagnostic leaked non-scalar data");
            check(Boolean.TRUE.equals(epoch.invoke(null)),"live native client epoch rejected server-only flag=false");
            zombie.network.GameClient.instance.connected=false; check(Boolean.FALSE.equals(epoch.invoke(null)),"disconnected client epoch accepted");
            zombie.network.GameClient.instance.connected=true;
            zombie.network.GameClient.connection=otherWire; check(Boolean.FALSE.equals(epoch.invoke(null)),"replacement client connection accepted"); zombie.network.GameClient.connection=wire;
            var guid=fixtureField(zombie.core.raknet.UdpConnection.class,"connectedGuid"); guid.setLong(wire,1L);
            check(Boolean.FALSE.equals(epoch.invoke(null)),"changed connection GUID accepted"); guid.setLong(wire,0L);
            zombie.characters.IsoPlayer.players[0]=null; check(Boolean.FALSE.equals(epoch.invoke(null)),"foreign local actor epoch accepted"); zombie.characters.IsoPlayer.players[0]=actor;
            var state=partial.get(null); fixtureField(state.getClass(),"client").setBoolean(state,false);
            zombie.network.GameClient.client=false; zombie.network.GameServer.server=true;
            var engine=(zombie.core.raknet.UdpEngine)unsafe.allocateInstance(zombie.core.raknet.UdpEngine.class);
            fixtureField(zombie.core.raknet.UdpEngine.class,"connectionMap").set(engine,new java.util.HashMap<>(java.util.Map.of(0L,wire)));
            zombie.network.GameServer.udpEngine=engine; zombie.network.GameServer.PlayerToAddressMap.put(actor,0L); zombie.network.GameServer.IDToPlayerMap.put((short)0,actor);
            check(Boolean.FALSE.equals(epoch.invoke(null)),"server epoch accepted missing server fullyConnected flag");
            var fully=fixtureField(zombie.core.raknet.UdpConnection.class,"fullyConnected"); fully.setBoolean(wire,true);
            check(Boolean.TRUE.equals(epoch.invoke(null)),"server fullyConnected exact actor/connection epoch rejected");
            fully.setBoolean(wire,false); check(Boolean.FALSE.equals(epoch.invoke(null)),"server guard weakened after client correction");
        } finally {
            source.setBoolean(null,oldSource); history.setBoolean(null,oldHistory); partial.set(null,oldPartial);
            zombie.network.GameClient.client=oldClient; zombie.network.GameServer.server=oldServer;
            zombie.network.GameClient.instance.connected=oldConnected; zombie.network.GameClient.connection=oldConnection;
            zombie.Lua.LuaManager.env=oldEnv; zombie.characters.IsoPlayer.numPlayers=oldPlayers;
            System.arraycopy(players,0,zombie.characters.IsoPlayer.players,0,players.length);
            zombie.network.GameServer.udpEngine=oldEngine;
            if (oldActor==null) zombie.network.GameServer.IDToPlayerMap.remove((short)0); else zombie.network.GameServer.IDToPlayerMap.put((short)0,oldActor);
            if (oldAddress==null) zombie.network.GameServer.PlayerToAddressMap.remove(actor); else zombie.network.GameServer.PlayerToAddressMap.put(actor,oldAddress);
        }
        System.out.println("PASS real native InventoryItem.getID/LuaJavaInvoker converter boundary, client connected/server fullyConnected roles and identity/GUID/disconnect fences (no requests)");
    }
    public static void main(String[] sources) throws Exception {
        check(Main.sourceSupported(),"exact supported native source required");
        originChecks(sources);
        realFactoryChecks(sources);
        nativeArmBoundaryChecks();
        // Inert marker data tests the shape guard only, never native packet receipt.
        Object actor=new Object(), otherActor=new Object(), entry=new Object(), otherEntry=new Object();
        java.util.function.Predicate<Object> exactEntry=value->value==entry;
        check(Main.replyPayloadMatches(actor,actor,List.of(entry),exactEntry),"matching singleton payload");
        check(!Main.replyPayloadMatches(actor,otherActor,List.of(entry),exactEntry),"foreign actor payload");
        check(!Main.replyPayloadMatches(null,null,List.of(entry),exactEntry),"missing actor payload");
        check(!Main.replyPayloadMatches(actor,actor,null,exactEntry),"missing entries payload");
        check(!Main.replyPayloadMatches(actor,actor,List.of(),exactEntry),"empty entries payload");
        check(!Main.replyPayloadMatches(actor,actor,List.of(entry,otherEntry),exactEntry),"batch payload");
        check(!Main.replyPayloadMatches(actor,actor,List.of(otherEntry),exactEntry),"wrong item or containers");
        System.out.println("PASS reply payload guard rejects foreign actor, missing/empty/batch/wrong entry");
        check(Main.pairPayloadMatches(actor,actor,List.of(entry,otherEntry),exactEntry,value->value==otherEntry),"canonical pair payload");
        check(!Main.pairPayloadMatches(actor,otherActor,List.of(entry,otherEntry),exactEntry,value->value==otherEntry),"foreign pair actor");
        check(!Main.pairPayloadMatches(null,null,List.of(entry,otherEntry),exactEntry,value->value==otherEntry),"missing pair actor");
        check(!Main.pairPayloadMatches(actor,actor,null,exactEntry,value->value==otherEntry),"missing pair list");
        for (List<?> invalid:List.of(List.of(),List.of(entry),List.of(otherEntry,entry),List.of(entry,entry),List.of(entry,otherEntry,otherActor)))
            check(!Main.pairPayloadMatches(actor,actor,invalid,exactEntry,value->value==otherEntry),"wrong pair shape/order/member");
        check(!Main.pairPayloadMatches(actor,actor,List.of(entry,otherEntry),value->false,value->true),"wrong pair endpoint");
        System.out.println("PASS partial pair guard rejects foreign actor, missing, wrong shape/order/item/endpoints");
        var calls=new HashMap<String,Integer>();
        for (String name:List.of("zombie/core/TransactionManager","zombie/core/Transaction",
                "zombie/network/packets/ItemTransactionPacket")) {
            byte[] original=resource(name);
            byte[] woven=Main.weave(name,original,Main.class.getClassLoader());
            check(!java.util.Arrays.equals(original,woven),"target unchanged "+name);
            // Native invocations and field writes must all remain: advice only adds
            // observations and the opt-in physical intervention before native update.
            check(nativeInstructions(original).equals(nativeInstructions(woven)),"native body changed "+name);
            // ASM parses the complete generated output, including method frames.
            new ClassReader(woven).accept(new ClassVisitor(Opcodes.ASM9) {
                @Override public MethodVisitor visitMethod(int access,String method,String descriptor,
                        String signature,String[] exceptions) {
                    return new MethodVisitor(Opcodes.ASM9) {
                        @Override public void visitMethodInsn(int opcode,String owner,String target,String desc,boolean itf) {
                            if (owner.equals("net/alexredby/queuepeersprobe/Main"))
                                calls.merge(method+":"+target,1,Integer::sum);
                        }
                    };
                }
            },0);
        }
        check(calls.getOrDefault("createItemTransaction:begin",0)==1,"one request entry");
        check(calls.getOrDefault("createItemTransaction:end",0)==1,"one request exit including throw path");
        check(calls.getOrDefault("set:allocated",0)==1,"one allocation hook");
        check(calls.getOrDefault("add:added",0)==1,"one add hook");
        check(calls.getOrDefault("processClient:drop",0)==1,"one receive gate");
        check(calls.getOrDefault("lambda$update$1:expired",0)==1,"one passive timeout exit");
        check(calls.getOrDefault("update:managerUpdated",0)==1,"one passive manager exit/export");
        check(calls.getOrDefault("update:partialUpdateEnter",0)==1,"one pre-native-update competing move");
        check(calls.getOrDefault("update:partialUpdateExit",0)==1,"one unchanged native result observation");
        check(calls.getOrDefault("processServer:partialServerEnter",0)==1,"one real admission entry");
        check(calls.getOrDefault("processServer:partialServerExit",0)==1,"one real admission result");
        check(calls.getOrDefault("write:partialWrite",0)==1,"one passive response serialization observation");
        check(calls.size()==12,"unexpected injection "+calls);
        boolean rejected=false;
        try { Main.weave("zombie/core/TransactionManager",resource("zombie/core/Transaction"),Main.class.getClassLoader()); }
        catch (RuntimeException expected) { rejected=true; }
        check(rejected,"wrong target descriptors accepted");
        if (instrumentation!=null) {
            var names=List.of("zombie/core/TransactionManager","zombie/core/Transaction",
                    "zombie/network/packets/ItemTransactionPacket");
            var loaded=new java.util.ArrayList<Class<?>>();
            for (String name:names) loaded.add(Class.forName(name.replace('/','.'),false,Main.class.getClassLoader()));
            java.lang.instrument.ClassFileTransformer transformer=new java.lang.instrument.ClassFileTransformer() {
                @Override public byte[] transform(ClassLoader loader,String name,Class<?> type,
                        java.security.ProtectionDomain domain,byte[] bytes) {
                    return names.contains(name) ? Main.weave(name,bytes,loader) : null;
                }
            };
            instrumentation.addTransformer(transformer,true);
            try {
                instrumentation.retransformClasses(loaded.toArray(Class<?>[]::new));
                for (Class<?> type:loaded) type.getDeclaredMethods();
            } finally { instrumentation.removeTransformer(transformer); }
            System.out.println("PASS isolated JVM retransformation verification (no native state initialization)");
        }
        System.out.println("PASS exact native hashes/descriptors, original calls/fields, request/admission/update/write/expiry transformations");
    }
}

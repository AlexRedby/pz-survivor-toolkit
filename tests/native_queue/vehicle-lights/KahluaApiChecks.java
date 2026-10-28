import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.lang.classfile.ClassFile;
import java.lang.classfile.instruction.InvokeInstruction;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaThread;

/** Execute the actual fixture drain predicate in the installed game's stock VM. */
public final class KahluaApiChecks {
    public static void main(String[] args) throws Exception {
        // Verify the native contract modeled below against this installed B42 JAR.
        try (var stream = KahluaApiChecks.class.getResourceAsStream("/zombie/characters/IsoGameCharacter.class")) {
            var model = ClassFile.of().parse(stream.readAllBytes());
            var method = model.methods().stream()
                .filter(value -> value.methodName().stringValue().equals("teleportTo")
                    && value.methodType().stringValue().equals("(FFI)V")).findFirst().orElseThrow();
            var calls = method.code().orElseThrow().elementStream().filter(InvokeInstruction.class::isInstance)
                .map(InvokeInstruction.class::cast).toList();
            if (calls.stream().filter(value -> value.owner().asInternalName().equals("zombie/core/math/PZMath")
                    && value.name().stringValue().equals("fastfloor")).count() != 2
                || calls.stream().noneMatch(value -> value.name().stringValue().equals("teleportTo")
                    && value.type().stringValue().equals("(III)V")))
                throw new AssertionError("Native fractional teleport contract changed; recheck fixture position restoration");
            var motion = model.methods().stream().filter(value -> value.methodName().stringValue().equals("doDeferredMovement"))
                .findFirst().orElseThrow().code().orElseThrow().elementStream().filter(InvokeInstruction.class::isInstance)
                .map(InvokeInstruction.class::cast).toList();
            if (motion.stream().noneMatch(value -> value.name().stringValue().equals("getDeferredMovement")
                    && value.type().stringValue().equals("(Lzombie/iso/Vector2;Z)Lzombie/iso/Vector2;")))
                throw new AssertionError("Native deferred-motion pipeline changed; recheck the settlement observation");
            var direction = model.methods().stream().filter(value -> value.methodName().stringValue().equals("setForwardDirection")
                && value.methodType().stringValue().equals("(FF)V")).findFirst().orElseThrow().code().orElseThrow();
            if (direction.elementStream().filter(InvokeInstruction.class::isInstance).map(InvokeInstruction.class::cast)
                    .anyMatch(value -> value.owner().asInternalName().equals("zombie/core/skinnedmodel/animation/AnimationPlayer")
                        && value.name().stringValue().equals("setTargetAndCurrentDirection")))
                throw new AssertionError("Native forward-direction setter now changes current animation orientation; recheck restoration order");
            var snapDirection = model.methods().stream().filter(value -> value.methodName().stringValue().equals("setTargetAndCurrentDirection")
                && value.methodType().stringValue().equals("(FF)V")).findFirst().orElseThrow().code().orElseThrow();
            if (snapDirection.elementStream().filter(InvokeInstruction.class::isInstance).map(InvokeInstruction.class::cast)
                    .noneMatch(value -> value.owner().asInternalName().equals("zombie/core/skinnedmodel/animation/AnimationPlayer")
                        && value.name().stringValue().equals("setTargetAndCurrentDirection")))
                throw new AssertionError("Native logical/current animation direction distinction changed");
        }
        var platform = J2SEPlatform.getInstance();
        var environment = platform.newEnvironment();
        if (environment.rawget("next") != null) throw new AssertionError("Expected stock B42 globals without next()");
        String source = Files.readString(Path.of(args[0]));
        int start = source.indexOf("local function drained()\n");
        int end = source.indexOf("\nend", start) + 4;
        if (start < 0 || end < start) throw new AssertionError("Fixture drain function missing");
        String test = "local pendingAcks={}\n"
            + "local nativeBusy=false;local queue={}\n"
            + "getPlayer=function()return {hasTimedActions=function()return nativeBusy end}end\n"
            + "ISTimedActionQueue={getTimedActionQueue=function()return {queue=queue}end}\n"
            + source.substring(start, end) + "\n"
            + "assert(drained());pendingAcks[1]={};assert(not drained());pendingAcks[1]=nil\n"
            + "nativeBusy=true;assert(not drained());nativeBusy=false\n"
            + "queue[1]={};assert(not drained());queue[1]=nil;assert(drained())\n";
        var thread = new KahluaThread(System.out, platform, environment);
        thread.debugOwnerThread = Thread.currentThread();
        Object[] result = thread.pcall(LuaCompiler.loadstring(test, "vehicle-light-drain", environment), new Object[0]);
        if (!Boolean.TRUE.equals(result[0])) throw new AssertionError(Arrays.toString(result));
        System.out.println("VEHICLE_LIGHTS_STOCK_KAHLUA_DRAIN_PASS next=absent queue/native/pending-ACK gates=verified");
        var fixture = Path.of(args[0]).toAbsolutePath().getParent().getParent().resolve("shared/VehicleLightsFixture.lua");
        environment.rawset("F", thread.call(LuaCompiler.loadstring(Files.readString(fixture), "VehicleLightsFixture", environment), new Object[0]));
        String positionTest = "local p={x=99,y=88,z=0,nx=99,ny=88}\n"
            + "function p:getX()return self.x end;function p:getY()return self.y end;function p:getZ()return self.z end\n"
            + "function p:teleportTo(x,y,z)self.x=math.floor(x);self.y=math.floor(y);self.z=z;self.lx=self.x;self.ly=self.y end\n"
            + "for method,key in pairs({setX='x',setY='y',setZ='z',setNextX='nx',setNextY='ny',setLastX='lx',setLastY='ly'})do\n"
            + " local k=key;p[method]=function(self,value)self[k]=value end end\n"
            + "local target={x=1.375,y=2.625,z=0};F.restorePosition(p,target)\n"
            + "assert(p.x==target.x and p.y==target.y and p.lx==target.x and p.ly==target.y)\n"
            + "p.x=p.nx;p.y=p.ny;assert(p.x==target.x and p.y==target.y)\n";
        result = thread.pcall(LuaCompiler.loadstring(positionTest, "vehicle-light-position", environment), new Object[0]);
        if (!Boolean.TRUE.equals(result[0])) throw new AssertionError(Arrays.toString(result));
        System.out.println("VEHICLE_LIGHTS_STOCK_KAHLUA_POSITION_PASS native-floored-teleport verified fractional/current/next/last positions restored");
        String settlementTest = "local p={x=1.5,y=2.5,z=0,getX=function(self)return self.x end,getY=function(self)return self.y end,getZ=function(self)return self.z end}\n"
            + "p.setX=function()error('settlement must not pin')end;p.teleportTo=p.setX\n"
            + "local initial=F.newPositionSettlement(nil)\n"
            + "for i=0,20 do assert(not F.observePositionSettlement(initial,p,i*50,false))end\n"
            + "p.x=1.48828125;p.y=2.5048828125\n"
            + "for i=0,14 do assert(not F.observePositionSettlement(initial,p,1200+i*50,true))end\n"
            + "assert(F.observePositionSettlement(initial,p,1950,true))\n"
            + "local target={x=p.x,y=p.y,z=0};local after=F.newPositionSettlement(target)\n"
            + "assert(not F.observePositionSettlement(after,p,2000,true));p.x=p.x-.01171875\n"
            + "for i=0,40 do assert(not F.observePositionSettlement(after,p,2050+i*50,true))end\n"
            + "p.x=target.x;for i=0,14 do assert(not F.observePositionSettlement(after,p,5000+i*50,true))end\n"
            + "assert(F.observePositionSettlement(after,p,5750,true))\n";
        result = thread.pcall(LuaCompiler.loadstring(settlementTest, "vehicle-light-settlement", environment), new Object[0]);
        if (!Boolean.TRUE.equals(result[0])) throw new AssertionError(Arrays.toString(result));
        System.out.println("VEHICLE_LIGHTS_STOCK_KAHLUA_SETTLEMENT_PASS native-deferred-motion pipeline verified no-write initial/pre/post observation and unchanged target guard");
    }
}

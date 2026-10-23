import java.util.LinkedHashMap;
import java.util.Map;
import net.alexredby.cartlab.Main;

/** Actual pinned native State.loadFrom/params check, with no world, socket or game lifecycle. */
public final class ObserverAssociationCheck {
    public static final class Owner extends zombie.characters.IsoPlayer {
        Map<zombie.ai.State.Param<?>,Object> values;
        Owner(){super(null,null,0,0,0);}
        @Override public Map<zombie.ai.State.Param<?>,Object> getStateMachineParams(Class<?> type){return values;}
    }
    private static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
    public static void main(String[] args)throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        // Under the real javaagent, loading these classes also verifies the exact diagnostic advices.
        for(String name:new String[]{"zombie.characters.IsoGameCharacter","zombie.network.GameClient","zombie.network.GameServer",
                "zombie.network.packets.actions.StatePacket","zombie.ai.states.PlayerActionsState","zombie.characters.NetworkState",
                "zombie.characters.NetworkCharacterAI","zombie.characters.CharacterTimedActions.LuaTimedActionNew"})Class.forName(name,false,ObserverAssociationCheck.class.getClassLoader());
        String life="1|01234567-89ab-cdef-0123-456789abcdef|1|2|3|4|5",text=life+"|6";
        var tag=Main.observerAssociationTag(text);
        check(tag!=null && tag.life().equals(life) && tag.text().equals(text) && tag.actor()==1 && tag.connection()==2
            && tag.action()==3 && tag.table()==4 && tag.begin()==5 && tag.state()==6,"Exact marker identity changed");
        check(Main.observerAssociationTag(life+"|7").state()!=tag.state(),"Repeated state generation collapsed");
        for(String invalid:new String[]{text+"|8",text.replace("|6","|0"),text.replace("|6","|-1"),text.replace("|6","|1.0"),text.replace("|6","|01"),text.replace("|6","|9007199254740992"),"invalid"})
            check(Main.observerAssociationTag(invalid)==null,"Malformed diagnostic marker accepted: "+invalid);
        var unsafeField=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");unsafeField.setAccessible(true);
        var unsafe=(sun.misc.Unsafe)unsafeField.get(null);var owner=(Owner)unsafe.allocateInstance(Owner.class);owner.values=new LinkedHashMap<>();
        var state=zombie.ai.states.PlayerActionsState.instance();owner.values.put(zombie.ai.states.PlayerActionsState.STAGE,zombie.ai.State.Stage.Exit);
        var incoming=new LinkedHashMap<Object,Object>();incoming.put(Main.OBSERVER_MARKER,text);
        state.loadFrom(incoming,owner);
        check(owner.values.size()==1 && owner.values.get(zombie.ai.states.PlayerActionsState.STAGE)==zombie.ai.State.Stage.Exit,"Unknown top-level params changed native state");
        incoming.put(zombie.ai.states.PlayerActionsState.STAGE.getName(),zombie.ai.State.Stage.Enter);
        state.loadFrom(incoming,owner);
        check(owner.values.size()==1 && owner.values.get(zombie.ai.states.PlayerActionsState.STAGE)==zombie.ai.State.Stage.Enter,"Known native params stopped loading beside diagnostic tag");
        var packet=new zombie.network.packets.actions.StatePacket();var paramsField=zombie.network.packets.actions.StatePacket.class.getDeclaredField("params");paramsField.setAccessible(true);
        var params=(zombie.network.PZNetKahluaTableImpl)paramsField.get(packet);params.rawset(Main.OBSERVER_MARKER,text);
        check(params.rawget(Main.OBSERVER_MARKER).equals(text) && owner.values.size()==1,"Packet params alias native character params");
        var bytes=java.nio.ByteBuffer.allocate(512);params.save(bytes);int end=bytes.position();bytes.flip();
        var parsed=new zombie.network.PZNetKahluaTableImpl(new LinkedHashMap<>());parsed.load(new zombie.core.network.ByteBufferReader(bytes),null);
        check(text.equals(parsed.rawget(Main.OBSERVER_MARKER)) && bytes.position()==end,"Native params serialization lost diagnostic marker");
        check(packet.shouldInstantiate(),"StatePacket stopped allocating distinct receipt instances");
        System.out.println("OBSERVER_ASSOCIATION_CHECK_PASS");
    }
}

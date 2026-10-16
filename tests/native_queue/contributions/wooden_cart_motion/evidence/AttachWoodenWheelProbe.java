import com.sun.tools.attach.VirtualMachine;
public final class AttachWoodenWheelProbe {
    public static void main(String[] args) throws Exception {
        if(args.length!=3)throw new IllegalArgumentException("Usage: AttachWoodenWheelProbe PID AGENT_JAR ABSOLUTE_OUTPUT_DIRECTORY|stop");
        var vm=VirtualMachine.attach(args[0]);
        try{vm.loadAgent(args[1],args.length>2?args[2]:"");}finally{vm.detach();}
    }
}

import java.util.*;
import zombie.iso.*;
import zombie.iso.SpriteDetails.IsoFlagType;

/** Positive counterexamples to four-hook generation closure, using actual native operations. */
public final class NativeMutationChecks {
    static void require(boolean value,String message){if(!value)throw new AssertionError(message);}
    static DirtyDependencyChecks.World visible()throws Exception {
        var w=DirtyDependencyChecks.world();
        w.lower().getProperties().set(IsoFlagType.blocksight);
        IsoGridSquare.GetSquare getter=(x,y,z)->x!=16 || y!=24?null:z==2?w.upper():z==1?w.lower():null;
        w.upper().ReCalculateVisionBlocked(w.lower(),getter);
        require(DirtyDependencyChecks.nativeHeight(w)==2,"initial native occluder required");
        return w;
    }
    static void changed(String name,DirtyDependencyChecks.World w,int expectedBefore,int expectedAfter,Runnable mutation) {
        int before=DirtyDependencyChecks.nativeHeight(w);mutation.run();int after=DirtyDependencyChecks.nativeHeight(w);
        require(before==expectedBefore && after==expectedAfter,name+" native answer must change");
        require(!w.levels().isDirty(2,1f),name+" target unexpectedly dirty");
        System.out.println("UNOBSERVED_MUTATION "+name+" before="+before+" after="+after+" targetDirty=false");
    }
    public static void main(String[] args)throws Exception {
        zombie.core.PerformanceSettings.fboRenderChunk=true;zombie.network.GameServer.server=false;
        var x=visible();changed("native-setX",x,2,-32,()->x.upper().setX(17));
        var y=visible();changed("native-setY",y,2,-32,()->y.upper().setY(25));
        var z=visible();changed("native-setZ",z,2,-32,()->z.upper().setZ(3));
        var flag=visible();byte[] flags=flag.data().squareFlags[0];
        changed("public-flag-row-store",flag,2,-32,()->flags[0]=0);
        var fill=visible();byte[] fillAlias=fill.data().squareFlags[0];
        changed("public-flag-row-fill",fill,2,-32,()->Arrays.fill(fillAlias,(byte)0));
        var copy=visible();byte[] copyAlias=copy.data().squareFlags[0];
        changed("public-flag-row-arraycopy",copy,2,-32,()->System.arraycopy(new byte[64],0,copyAlias,0,64));
        var row=visible();
        changed("public-flag-row-replacement",row,2,-32,()->row.data().squareFlags[0]=new byte[64]);
        var lower=DirtyDependencyChecks.world();IsoGridSquare[] lowerAlias=lower.c().getSquaresForLevel(1);
        changed("native-returned-lower-row-store",lower,-32,2,()->lowerAlias[0]=null);
        require(!lower.levels().isDirty(1,1f),"row alias does not invoke lower invalidation either");
        var upper=visible();IsoGridSquare[] upperAlias=upper.c().getSquaresForLevel(2);
        changed("native-returned-upper-row-store",upper,2,-32,()->upperAlias[0]=null);
        var vision=DirtyDependencyChecks.world();
        changed("public-vision-field-write",vision,-32,2,()->vision.upper().visionMatrix=16);
        System.out.println("NATIVE_MUTATION_CHECKS_PASS cases=10 persistent_generation_contract_admissible=false gameplay_reachability_proved=false");
    }
}

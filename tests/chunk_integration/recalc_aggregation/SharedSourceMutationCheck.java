import java.util.*;
import pzresearch.AggregationScope;
import zombie.iso.*;
import zombie.iso.SpriteDetails.IsoFlagType;
import zombie.iso.sprite.IsoSprite;
import zombie.core.properties.PropertyContainer;

/** Negative control: exact native AddProperties mutates a live shared sprite source between required reads. */
public final class SharedSourceMutationCheck {
    static List<Object> run(boolean candidate)throws Exception {
        AggregationChecks.Fixture f=new AggregationChecks.Fixture(0,0);
        IsoSprite source=new IsoSprite();PropertyContainer sourceProperties=source.getProperties();
        sourceProperties.set(IsoFlagType.solidfloor);sourceProperties.set("Surface","10",false);sourceProperties.CreateKeySet();
        IsoObject object=new IsoObject();object.sprite=source;object.setSquare(f.s);f.s.getObjects().add(object);
        PropertyContainer closed=new PropertyContainer();closed.set(IsoFlagType.collideN);closed.set("Surface","20",false);closed.CreateKeySet();
        AggregationScope.enter();try {
            Throwable first=AggregationChecks.call(candidate,f.s);if(first!=null)throw new AssertionError(first);
            if(f.s.getProperties().getSurface()!=10 || f.s.getProperties().has(IsoFlagType.collideN))throw new AssertionError("Bad initial map");
            // This is the actual mutable native method used by the independently audited sprite loader.
            // The harness supplies the interleaving; it does not claim to schedule WorldStreamer or execute IsoWindow.load.
            sourceProperties.AddProperties(closed);
            Throwable second=AggregationChecks.call(candidate,f.s);if(second!=null)throw new AssertionError(second);
            return List.of(f.s.getProperties().has(IsoFlagType.collideN),f.s.getProperties().getSurface());
        }finally{AggregationScope.exit();}
    }
    public static void main(String[] args)throws Exception {
        AggregationChecks.aliases();List<Object> baseline=run(false),candidate=run(true);
        if(!baseline.equals(List.of(true,20)) || !candidate.equals(List.of(false,10)))
            throw new AssertionError("Expected live-dependency counterexample changed: "+baseline+"/"+candidate);
        if(AggregationScope.active() || AggregationScope.retained()!=0)throw new AssertionError("Negative scope leaked");
        System.out.println("SHARED_SOURCE_MUTATION_COUNTEREXAMPLE baseline="+baseline+" candidate="+candidate);
        System.out.println("SCOPE ordinary field-only IsoObject/IsoSprite; native AddProperties; supplied interleaving only, no actual worker or game launch");
    }
}

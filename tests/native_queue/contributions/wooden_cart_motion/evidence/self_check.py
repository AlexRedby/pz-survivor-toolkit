"""Offline evidence checks. Never attaches an agent or launches Project Zomboid."""
import argparse
import os
from pathlib import Path
import py_compile
import subprocess
import sys
import tempfile
import numpy as np
import actual_mesh
from clearance_geometry import separation, skin

HERE = Path(__file__).resolve().parent

WORLD_PROBE_CHECK = r'''
import java.io.*;
import java.lang.reflect.*;
import java.nio.file.*;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;
import static net.bytebuddy.matcher.ElementMatchers.*;
import org.joml.*;
import sun.misc.Unsafe;
import zombie.inventory.InventoryItem;
import zombie.iso.objects.IsoWorldInventoryObject;
import zombie.core.skinnedmodel.model.ItemModelRenderer;
public final class WorldCartProbeCheck {
    static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
    static Field field(Class<?> type,String name)throws Exception{var f=type.getDeclaredField(name);f.setAccessible(true);return f;}
    static final class Sink extends StringWriter {
        int closes; boolean fail;
        @Override public void close()throws IOException{closes++;if(fail)throw new IOException("expected close failure");super.close();}
    }
    public static void main(String[] args)throws Exception {
        var bytes=new ByteBuddy().redefine(ItemModelRenderer.class)
            .visit(Advice.to(ClearanceProbe.WorldRenderCapture.class).on(named("renderMain").and(takesArguments(9))))
            .make().getBytes();
        check(bytes.length>0,"world advice did not generate");
        var unsafe=(Unsafe)field(Unsafe.class,"theUnsafe").get(null);
        var item=(InventoryItem)unsafe.allocateInstance(InventoryItem.class);
        field(InventoryItem.class,"fullType").set(item,"SaucedWheelbarrow.WheelbarrowWood");
        item.setID(42);item.setWorldItem((IsoWorldInventoryObject)unsafe.allocateInstance(IsoWorldInventoryObject.class));
        var renderer=(ItemModelRenderer)unsafe.allocateInstance(ItemModelRenderer.class);
        renderer.x=11.25f;renderer.y=22.5f;renderer.z=3.75f;
        field(ItemModelRenderer.class,"angle").set(renderer,new Vector3f(10,20,30));
        var matrix=new Matrix4f().translation(4,5,6).scale(.85f);
        field(ItemModelRenderer.class,"transform").set(renderer,matrix);
        field(ItemModelRenderer.class,"alpha").setFloat(renderer,0);
        var body=new Sink();var world=new Sink();
        var bodyField=field(ClearanceProbe.class,"output");var worldField=field(ClearanceProbe.class,"worldOutput");
        bodyField.set(null,new BufferedWriter(body));worldField.set(null,new BufferedWriter(world));
        ClearanceProbe.finishWorld(renderer,item,ItemModelRenderer.RenderStatus.Ready);
        var row=world.toString();
        check(row.contains("\"itemId\":42") && row.contains("\"alpha\":0.0")
            && row.contains("\"angle\":[10.0,20.0,30.0]") && row.contains("4.0,5.0,6.0,1.0]"),"missing final render fields: "+row);
        check(row.lines().count()==1 && body.toString().isEmpty(),"world capture mixed body records");
        check(matrix.equals(new Matrix4f().translation(4,5,6).scale(.85f)),"probe mutated renderer matrix");
        ClearanceProbe.finishWorld(renderer,item,ItemModelRenderer.RenderStatus.NoModel);
        check(world.toString().equals(row),"early return emitted stale renderer fields");
        ClearanceProbe.finishWorld(renderer,item,ItemModelRenderer.RenderStatus.Loading);
        check(world.toString().equals(row),"loading renderer emitted a pose");
        field(InventoryItem.class,"fullType").set(item,"SaucedWheelbarrow.WheelbarrowMetal");
        ClearanceProbe.finishWorld(renderer,item,ItemModelRenderer.RenderStatus.Ready);
        check(world.toString().equals(row),"nonwood item captured");
        body.fail=true;
        try{ClearanceProbe.agentmain("stop",null);throw new AssertionError("close failure hidden");}catch(IOException expected){}
        check(body.closes==1 && world.closes==1 && bodyField.get(null)==null && worldField.get(null)==null,"stop failed to detach/close both writers");
        ClearanceProbe.finishWorld(renderer,item,ItemModelRenderer.RenderStatus.Ready);
        check(world.toString().equals(row),"callback wrote after stop");
        var directory=Files.createTempDirectory("world-probe-preserve-");
        var existing=directory.resolve("world-cart-poses.jsonl");
        try {
            Files.writeString(existing,"preserve");
            try{ClearanceProbe.agentmain(directory.toString(),null);throw new AssertionError("existing world evidence overwritten");}catch(IllegalStateException expected){}
            check(Files.readString(existing).equals("preserve") && !Files.exists(directory.resolve("body-clearance.jsonl")),"partial capture created before output preflight");
        }finally{Files.delete(existing);Files.delete(directory);}
        System.out.println("WORLD_CART_PROBE_CHECK_PASS (final world fields, advice, exact item scope, independent files, stale/late callback and close safety)");
    }
}
'''


def geometry():
    actual_mesh.self_check()
    cube = np.array([[0., 0, 0], [1, 1, 1]])
    assert separation(cube, cube + [2, 0, 0]) == 1
    assert separation(cube, cube + .5) < 0
    native = np.eye(4)
    native[:3, 3] = [2, 3, 4]
    mesh = (1, [('test', np.array([0]), np.array([1.]), np.array([[1., 1, 1, 1]]))], {}, [])
    row = {'bones': {'test': native.T.reshape(-1).tolist()}}
    np.testing.assert_allclose(skin(row, mesh), [[3, 4, 5]])
    row['bones'].clear()
    try:
        skin(row, mesh)
    except KeyError:
        pass
    else:
        raise AssertionError('Missing native bones must not become a false PASS')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-java-dir', type=Path)
    parser.add_argument('--jdk', type=Path)
    parser.add_argument('--toolkit-classes', type=Path, help='Compiled candidate JavaPatches classes; no binaries are supplied here')
    args = parser.parse_args()
    geometry()
    subprocess.run([sys.executable, str(HERE / 'test_analyzer.py')], check=True)
    subprocess.run([sys.executable, str(HERE / 'test_impact_clearance.py')], check=True)
    with tempfile.TemporaryDirectory(prefix='wood-evidence-check-') as temp:
        output = Path(temp)
        for path in HERE.glob('*.py'):
            py_compile.compile(str(path), cfile=str(output / (path.name + 'c')), doraise=True)
        print('PYTHON_EVIDENCE_CHECK_PASS (syntax, triangle crossing/containment/coplanarity/distance, AABB and native skin matrices)')
        supplied = [args.game_java_dir, args.jdk, args.toolkit_classes]
        if not any(supplied):
            print('JAVA_EVIDENCE_CHECK_SKIPPED (supply --game-java-dir, --jdk, --toolkit-classes); live=NOT_RUN')
            return
        assert all(supplied), 'Supply all three Java dependency paths'
        dependencies = [args.game_java_dir / 'projectzomboid.jar', args.game_java_dir / 'ZombieBuddy.jar', args.toolkit_classes]
        assert all(path.exists() for path in dependencies), 'Missing compile dependency'
        compiler, java = args.jdk / 'bin/javac', args.jdk / 'bin/java'
        classpath = os.pathsep.join(map(str, dependencies))
        subprocess.run([str(compiler), '--release', '25', '-cp', classpath, '-d', str(output), *map(str, HERE.glob('*.java'))], check=True)
        runtime = os.pathsep.join([str(output), classpath])
        for check in ['WoodenWheelProbeCheck', 'WoodenWheelProbeLifecycleTest', 'GripPoseProbeCheck', 'ClearanceProbeCheck']:
            subprocess.run([str(java), '--enable-native-access=ALL-UNNAMED', '-cp', runtime, check], check=True)
        world_check = output / 'WorldCartProbeCheck.java'
        world_check.write_text(WORLD_PROBE_CHECK)
        subprocess.run([str(compiler), '--release', '25', '-cp', runtime, '-d', str(output), str(world_check)], check=True)
        subprocess.run([str(java), '--enable-native-access=ALL-UNNAMED', '-cp', runtime, 'WorldCartProbeCheck'], check=True)
        print('JAVA_EVIDENCE_CHECK_PASS (compile and offline probe checks); live=NOT_RUN')


if __name__ == '__main__':
    main()

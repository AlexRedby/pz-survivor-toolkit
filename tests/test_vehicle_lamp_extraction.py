"""Regression for geometric extraction; optional developer-tool dependencies."""
import unittest
try:
    import numpy as np
    from tools.extract_vehicle_lamp_origins import sample_lamps
except ModuleNotFoundError as error:
    raise unittest.SkipTest('Lamp extraction developer checks need numpy and Pillow') from error


class LampExtractionChecks(unittest.TestCase):
    def mesh(self, z=0):
        return {'transform': np.eye(4).tolist(),
                'vertices': [[0,0,z,0,0], [4,0,z,1,0], [0,0,z+4,0,1]],
                'triangles': [[0,1,2]]}

    def test_actual_lamp_mask_excludes_body_head_zone(self):
        mask=np.zeros((4,4,3),dtype=np.uint8);mask[:]=[255,0,0]
        self.assertEqual(sample_lamps([self.mesh()],mask,1,False),{})
        mask[:]=[192,0,0]
        actual=sample_lamps([self.mesh()],mask,2,False)
        np.testing.assert_allclose(actual['HeadlightLeft'],[-3,0,3])
        self.assertEqual(set(actual),{'HeadlightLeft'})

    def test_tail_zone_shared_with_front_markers_does_not_average_cabin(self):
        mask=np.zeros((4,4,3),dtype=np.uint8);mask[:]=[0,64,0]
        actual=sample_lamps([self.mesh(4),self.mesh(-8)],mask,1,False)
        # Rear cluster alone has texel-centre mean (-1.5, 0, -6.5).
        np.testing.assert_allclose(actual['HeadlightRearLeft'],[-1.5,0,-6.5])

    def test_node_transform_and_model_mirroring_are_applied(self):
        mesh=self.mesh();mesh['transform'][0][3]=10
        mask=np.zeros((4,4,3),dtype=np.uint8);mask[:]=[64,0,0]
        actual=sample_lamps([mesh],mask,1,True)
        np.testing.assert_allclose(actual['HeadlightRight'],[11.5,0,1.5])


if __name__=='__main__': unittest.main()

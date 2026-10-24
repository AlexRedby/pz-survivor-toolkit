"""Three-role execution checks for the actual native-menu lifetime adapter."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / 'tests/native_queue/contributions/wooden_cart_multiplayer'
LUA = shutil.which('luajit') or shutil.which('lua')


@unittest.skipUnless(LUA, 'Requires LuaJIT or Lua 5.1')
class CartLeaseMenuBankTests(unittest.TestCase):
    def run_bank(self, defect='none', filename='LeaseMenuBankCheck.lua'):
        return subprocess.run([LUA, str(FOLDER / filename), str(ROOT), defect],
                              text=True, capture_output=True, timeout=15)

    def test_three_roles_complete_two_menu_cycles_with_stale_fences(self):
        result = self.run_bank()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('LEASE_MENU_BANK_CHECK_PASS messages=50 ownerActions=4 absenceObservations=6 '
                      'absentSourceRefusals=4 postBindClientRefusals=4', result.stdout)

    def test_omitted_absence_cannot_resume_pickup(self):
        result = self.run_bank('omitted-absence')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('Equipment lifetime bank deadline', result.stderr)

    def test_runtime_owner_input_requires_a_complete_native_menu_driver(self):
        for defect in ('missing-menu-driver', 'non-table-menu-driver', 'incomplete-menu-driver'):
            with self.subTest(defect=defect):
                result = self.run_bank(defect)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn('Owner native menu driver unavailable', result.stderr)

    def test_menu_commands_revalidate_exact_owner_and_observer_transports(self):
        for who, error in (('owner', 'Native menu owner transport changed'),
                           ('observer', 'Native menu requester transport changed')):
            for stage in ('absence', 'bind'):
                defect = who + '-transport-at-' + stage
                with self.subTest(defect=defect):
                    result = self.run_bank(defect)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn(error, result.stderr)

    def test_server_and_observer_must_independently_observe_native_absence(self):
        for defect in ('server-no-absence', 'client2-no-absence'):
            with self.subTest(defect=defect):
                result = self.run_bank(defect)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn('Equipment lifetime bank deadline', result.stderr)

    def test_malformed_absence_barrier_and_foreign_reply_source_fail_closed(self):
        for defect, error in (
            ('malformed-absence', 'Prepared menu payload changed body'),
            ('wrong-absence-nonce', 'Repeated/foreign menu absence'),
            ('early-resume', 'Unexpected menu pickup barrier'),
            ('malformed-resume', 'Unexpected menu pickup barrier'),
            ('foreign-ingress', 'Menu cycle client transport changed'),
        ):
            with self.subTest(defect=defect):
                result = self.run_bank(defect)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn(error, result.stderr)

    def test_existing_setter_bank_still_passes_original_message_bounds(self):
        result = self.run_bank(filename='LeaseLifetimeBankCheck.lua')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('LEASE_LIFETIME_BANK_CHECK_PASS messages=42 cycles=6 staleSourceRefusals=4', result.stdout)
        self.assertIn('LEASE_LIFETIME_BANK_CHECK_PASS messages=48 cycles=6 staleSourceRefusals=4', result.stdout)


if __name__ == '__main__':
    unittest.main()

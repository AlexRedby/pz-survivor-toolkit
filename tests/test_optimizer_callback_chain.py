"""Exact diagnostic replacements preserve source ownership and reject changed dependencies."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import callback_chain


class CallbackChainTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = self.root / 'cache'
        self.sources = []
        self.originals = []
        for index in range(2):
            original = self.root / ('source' + str(index) + '.lua')
            original.write_bytes(b'before\r\n old(self)\r\nafter\r\n')
            self.originals.append(original)
            relative = 'mods/example/42/media/lua/client/source' + str(index) + '.lua'
            target = self.cache / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.hardlink_to(original)
            self.sources.append((relative, hashlib.sha256(original.read_bytes()).hexdigest(),
                                 ' old(self)', ' PZDrivingCallbackCall(old, self)'))
        self.guard = patch.object(callback_chain, 'SOURCES', tuple(self.sources))
        self.guard.start()
        self.addCleanup(self.guard.stop)

    def test_atomic_replacement_preserves_hardlinked_sources_and_line_endings(self):
        receipt = callback_chain.stage(self.cache)
        self.assertEqual(receipt, callback_chain.verify(self.cache))
        for original, record in zip(self.originals, receipt['sources']):
            self.assertEqual(b'before\r\n old(self)\r\nafter\r\n', original.read_bytes())
            target = self.cache / record['source']
            self.assertEqual(b'before\r\n PZDrivingCallbackCall(old, self)\r\nafter\r\n', target.read_bytes())
            self.assertNotEqual(original.stat().st_ino, target.stat().st_ino)
        with self.assertRaisesRegex(ValueError, 'source changed'):
            callback_chain.stage(self.cache)

    def test_all_dependencies_validated_before_any_copy_changes(self):
        (self.cache / self.sources[1][0]).write_bytes(b'changed upstream')
        with self.assertRaisesRegex(ValueError, 'source changed'):
            callback_chain.stage(self.cache)
        self.assertEqual(self.originals[0].read_bytes(), (self.cache / self.sources[0][0]).read_bytes())
        self.assertFalse((self.cache / 'callback-chain-staging.json').exists())

    def test_receipt_cannot_admit_changed_body_even_with_replaced_after_hash(self):
        receipt = callback_chain.stage(self.cache)
        target = self.cache / receipt['sources'][0]['source']
        target.write_bytes(target.read_bytes() + b'extra side effect\n')
        receipt['sources'][0]['after_sha256'] = hashlib.sha256(target.read_bytes()).hexdigest()
        (self.cache / 'callback-chain-staging.json').write_text(json.dumps(receipt))
        with self.assertRaisesRegex(ValueError, 'source bytes changed'):
            callback_chain.verify(self.cache)

    def test_symbolic_source_rejected(self):
        target = self.cache / self.sources[1][0]
        target.unlink()
        target.symlink_to(self.originals[1])
        with self.assertRaisesRegex(ValueError, 'owned regular'):
            callback_chain.stage(self.cache)

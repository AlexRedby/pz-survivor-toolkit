"""Strict log-contract checks for the shelf-book/TV live fixture."""
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import shelf_book_tv as adapter


STAMP = '2026-10-20 12:00:00 '
MARK = '[SHELF_TV] '


class ShelfBookTVAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def selection(self, kind='sp', mode='toolkit'):
        return dict(suite='shelf-book-tv', cases=['demote-and-control'], kind=kind, mode=mode,
                    clients=1, languages=['EN'], mods=list(adapter.MODS),
                    options={'mp_host': True} if kind == 'mp' else {})

    def client_log(self, mode='toolkit'):
        lines = [
            'PREPARED shelfId=11 bookId=22 tv=10,20,0 tapeId=33 mediaIndex=44 mediaType=1 power=electric daylight=true',
            'PROGRESS authority=server pagesBefore=16 pagesCommitted=17',
            'READ started=true pagesBefore=16 pagesCommitted=17',
            'COMMANDS power=ISRadioAction insert=ISDeviceMediaAction play=ISRadioAction',
        ]
        lines += (['PROMOTED current=ISReadABook target=ISRadioAction after=true accepted=true'] if mode == 'toolkit' else
                  ['CONTROL queueOff=true naturalReadBeforeTV=true', 'NATURAL_ORDER readerFinishedBeforeTV=true'])
        lines += [
            'POWER_EFFECT command=ToggleOnOff turnedOn=true',
            'INSERT_EFFECT command=ISDeviceMediaAction exactTape=true mediaIndex=44 mediaType=1',
            'PLAY_EFFECT command=TogglePlayMedia mediaPlaying=true',
        ]
        if mode == 'toolkit':
            lines.append('RESUMED sameAction=false sameBook=true sameOperation=true pagesBefore=17 pagesAfter=18')
        lines += [
            'ACTIONS powerStarted=true powered=true insertStarted=true exactTape=true playStarted=true mediaMatched=true',
            'RETURN sameBook=true exactCount=1',
            'MEDIA tapeDebited=true exactTape=true mediaIndex=44 mediaType=1 title=Carzone playing=true',
            'COMPLETE case=demote-and-control',
        ]
        return '\n'.join(STAMP + MARK + line for line in lines) + '\n'

    def server_log(self):
        return '\n'.join((
            STAMP + MARK + 'PREPARED shelfId=11 bookId=22 tv=10,20,0 tapeId=33 mediaIndex=44 mediaType=1 power=electric daylight=true',
            STAMP + MARK + 'AUTH_PROGRESS pagesBefore=16 pagesCommitted=17 actor=client1',
            STAMP + MARK + 'AUTHORITY pagesComplete=true bookReturned=true exactBookCount=1 tapeRemoved=true mediaIndex=44 mediaType=1 tvMedia=Carzone playing=true actor=client1',
        )) + '\n'

    def verify(self, kind='sp', mode='toolkit', client=None, server=None):
        (self.root / 'client1-launch.log').write_text(self.client_log(mode) if client is None else client)
        if kind == 'mp':
            (self.root / 'server-launch.log').write_text(self.server_log() if server is None else server)
        return adapter.verify(self.root, self.selection(kind, mode), {})

    def test_timestamped_success_for_sp_and_host_native_and_toolkit(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                with self.subTest(kind=kind, mode=mode):
                    result = self.verify(kind, mode)
                    self.assertEqual(result['issues'], [])

    def test_stage_registers_fixture_failure_marker(self):
        cache = self.root / 'cache'
        runtime = {'roles': {'client1': {'cache': str(cache)}}}
        adapter.stage(ROOT, self.root / 'output', self.root / 'game', self.root / 'jdk',
                      self.selection(), {}, runtime)
        self.assertIn('[QUEUE_TEST] FAIL shelf-book-tv', runtime['fixture']['failure_markers'])

    def test_rejects_missing_duplicate_and_out_of_order_markers(self):
        client = self.client_log().replace(MARK + 'PLAY_EFFECT', MARK + 'OMITTED_EFFECT')
        self.assertTrue(self.verify(client=client)['issues'])
        client = self.client_log() + STAMP + MARK + 'COMPLETE case=demote-and-control\n'
        self.assertTrue(self.verify(client=client)['issues'])
        client = self.client_log()
        client = client.replace(MARK + 'POWER_EFFECT', MARK + 'HOLD_POWER', 1)
        client = client.replace(MARK + 'PLAY_EFFECT', MARK + 'POWER_EFFECT', 1)
        client = client.replace(MARK + 'HOLD_POWER', MARK + 'PLAY_EFFECT', 1)
        self.assertTrue(any('out of order' in issue for issue in self.verify(client=client)['issues']))

    def test_rejects_non_increasing_or_mismatched_page_receipts(self):
        client = self.client_log().replace('pagesCommitted=17', 'pagesCommitted=16', 1)
        self.assertTrue(any('committed increase' in issue for issue in self.verify(client=client)['issues']))
        client = self.client_log().replace('READ started=true pagesBefore=16 pagesCommitted=17',
                                           'READ started=true pagesBefore=16 pagesCommitted=18')
        self.assertTrue(any('does not match' in issue for issue in self.verify(client=client)['issues']))
        client = self.client_log().replace('pagesBefore=17 pagesAfter=18', 'pagesBefore=16 pagesAfter=18')
        self.assertTrue(any('previously committed' in issue for issue in self.verify(client=client)['issues']))

    def test_rejects_server_progress_and_media_identity_mismatches(self):
        server = self.server_log().replace('pagesCommitted=17', 'pagesCommitted=18')
        self.assertTrue(any('server-committed page progress' in issue for issue in self.verify('mp', server=server)['issues']))
        server = self.server_log().replace('mediaIndex=44 mediaType=1 tvMedia=Carzone',
                                           'mediaIndex=45 mediaType=1 tvMedia=Carzone')
        self.assertTrue(any('differs from exact prepared tape' in issue for issue in self.verify('mp', server=server)['issues']))
        client = self.client_log().replace('mediaIndex=44 mediaType=1 title=Carzone',
                                           'mediaIndex=45 mediaType=1 title=Carzone')
        self.assertTrue(any('differs from the exact prepared tape' in issue for issue in self.verify(client=client)['issues']))


if __name__ == '__main__':
    unittest.main()

"""Opaque native player cloning stays confined to a disposable database copy."""
from contextlib import closing
import hashlib
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import world_import


PLAYER_SCHEMA = '''CREATE TABLE networkPlayers (
    id INTEGER PRIMARY KEY NOT NULL, world TEXT, username TEXT, playerIndex INTEGER,
    name STRING, steamid STRING, x FLOAT, y FLOAT, z FLOAT, worldversion INTEGER, data BLOB,
    isDead BOOLEAN, splitUsername STRING
)'''


class PlayerImportTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.database = self.root / 'players.db'
        self.actors = [
            (7, 'original-world', 'original-one', 0, 'First actor', 'steam-one',
             1024.25, 2048.75, 0.0, 240, b'\x00first\xffnative\x00blob', 0, 'split-one'),
            (19, 'original-world', 'original-two', 1, 'Second actor', 'steam-two',
             -121.5, 300.125, 2.0, 240, b'\x00second\xfenative\x00blob', 0, 'split-two'),
        ]
        self.make_database()

    def make_database(self, schema=PLAYER_SCHEMA):
        self.database.unlink(missing_ok=True)
        with closing(sqlite3.connect(self.database)) as connection, connection:
            connection.execute(schema)
            connection.executemany('INSERT INTO networkPlayers VALUES (' + ','.join('?' * 13) + ')', self.actors)

    def rows(self):
        with closing(sqlite3.connect(self.database)) as connection:
            return connection.execute('SELECT * FROM networkPlayers ORDER BY id').fetchall()

    def clone(self, roles=('client1',), mappings=None):
        return world_import._clone_players(self.database, list(roles),
                                           {'client1': 7} if mappings is None else mappings, 'queue-smoke')

    def assert_closed_copy(self):
        self.assertEqual(['players.db'], sorted(path.name for path in self.root.iterdir()))

    def test_clones_distinct_native_actors_preserving_original_rows_and_opaque_fields(self):
        before = self.rows()
        receipts = self.clone(('client1', 'client2'), {'client1': 7, 'client2': 19})
        rows = self.rows()
        self.assertEqual(before, rows[:2])
        self.assertEqual(4, len(rows))
        for role, source, target, receipt in zip(('client1', 'client2'), before, rows[2:], receipts):
            expected = list(source)
            expected[0] = target[0]
            expected[1:4] = ['queue-smoke', role, 0]
            expected[5] = None
            expected[12] = role
            self.assertEqual(tuple(expected), target)
            self.assertGreater(target[0], max(row[0] for row in before))
            self.assertEqual(dict(role=role, source_id=source[0], target_id=target[0],
                                  blob_sha256=hashlib.sha256(source[10]).hexdigest()), receipt)
        self.assert_closed_copy()

    def test_requires_complete_distinct_explicit_actor_mappings(self):
        before = self.rows()
        for mappings in ({}, {'client1': 7}, {'client1': 7, 'client2': 7},
                         {'client1': True, 'client2': 19}, {'client1': -7, 'client2': 19},
                         {'client1': 7, 'unknown': 19}, {'client1': '7', 'client2': 19}):
            with self.subTest(mappings=mappings), self.assertRaisesRegex(ValueError, 'Explicit distinct'):
                self.clone(('client1', 'client2'), mappings)
            self.assertEqual(before, self.rows())
        self.assert_closed_copy()

    def test_missing_dead_empty_or_invalid_native_actor_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'living native character'):
            self.clone(mappings={'client1': 99})
        changes = [('isDead', 1), ('data', b''), ('data', None), ('data', 'not a native blob'),
                   ('x', None), ('y', 'invalid coordinate'), ('z', float('inf')),
                   ('worldversion', 0), ('worldversion', 1.5)]
        for column, value in changes:
            self.make_database()
            with closing(sqlite3.connect(self.database)) as connection, connection:
                connection.execute('UPDATE networkPlayers SET ' + column + '=? WHERE id=7', (value,))
            before = self.rows()
            with self.subTest(column=column, value=value), self.assertRaisesRegex(ValueError, 'living native character'):
                self.clone()
            self.assertEqual(before, self.rows())
            self.assert_closed_copy()

    def test_existing_fixture_tuple_is_never_overwritten(self):
        with closing(sqlite3.connect(self.database)) as connection, connection:
            connection.execute("UPDATE networkPlayers SET world='queue-smoke', username='client1', playerIndex=0 WHERE id=19")
        before = self.rows()
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.clone()
        self.assertEqual(before, self.rows())
        self.assert_closed_copy()

    def test_second_actor_failure_rolls_back_first_clone(self):
        with closing(sqlite3.connect(self.database)) as connection, connection:
            connection.execute('UPDATE networkPlayers SET isDead=1 WHERE id=19')
        before = self.rows()
        before_bytes = self.database.read_bytes()
        with self.assertRaisesRegex(ValueError, 'living native character'):
            self.clone(('client1', 'client2'), {'client1': 7, 'client2': 19})
        self.assertEqual(before, self.rows())
        self.assertEqual(before_bytes, self.database.read_bytes())
        self.assert_closed_copy()

    def test_a_missing_source_id_cannot_select_a_clone_inserted_for_another_actor(self):
        before = self.rows()
        next_id = max(row[0] for row in before) + 1
        with self.assertRaisesRegex(ValueError, 'living native character'):
            self.clone(('client1', 'client2'), {'client1': 7, 'client2': next_id})
        self.assertEqual(before, self.rows())
        self.assert_closed_copy()

    def test_closed_wal_database_copy_finishes_without_journal_sidecars(self):
        with closing(sqlite3.connect(self.database)) as connection:
            self.assertEqual('wal', connection.execute('PRAGMA journal_mode=WAL').fetchone()[0])
        self.assert_closed_copy()
        self.clone()
        self.assert_closed_copy()
        with closing(sqlite3.connect(self.database)) as connection:
            self.assertEqual('delete', connection.execute('PRAGMA journal_mode').fetchone()[0])

    def test_schema_changes_and_triggers_are_refused(self):
        for schema in (PLAYER_SCHEMA.replace('splitUsername STRING', 'otherName STRING'),
                       PLAYER_SCHEMA.replace('id INTEGER PRIMARY KEY NOT NULL', 'id INTEGER'),
                       PLAYER_SCHEMA.replace('data BLOB', 'data TEXT'),
                       PLAYER_SCHEMA.replace('id INTEGER PRIMARY KEY NOT NULL', 'id INTEGER PRIMARY KEY')):
            with self.subTest(schema=schema):
                self.make_database(schema)
                before = self.rows()
                with self.assertRaisesRegex(ValueError, 'schema'):
                    self.clone()
                self.assertEqual(before, self.rows())
        self.make_database()
        with closing(sqlite3.connect(self.database)) as connection, connection:
            connection.execute('CREATE TRIGGER unexpected AFTER INSERT ON networkPlayers BEGIN DELETE FROM networkPlayers WHERE id=7; END')
        before = self.rows()
        with self.assertRaisesRegex(ValueError, 'triggers'):
            self.clone()
        self.assertEqual(before, self.rows())
        self.assert_closed_copy()

    def test_connections_close_after_success_and_failure(self):
        closed = []
        class TrackedConnection(sqlite3.Connection):
            def close(self):
                super().close()
                closed.append(self)
        connect = sqlite3.connect
        def tracked(*args, **kwargs):
            return connect(*args, **kwargs, factory=TrackedConnection)
        with patch.object(world_import.sqlite3, 'connect', side_effect=tracked):
            self.clone()
            with self.assertRaisesRegex(ValueError, 'already exists'):
                self.clone()
        self.assertEqual(2, len(closed))
        for connection in closed:
            with self.assertRaises(sqlite3.ProgrammingError):
                connection.execute('SELECT 1')
        self.assert_closed_copy()


class NativePlayerApiTests(unittest.TestCase):
    def test_unknown_missing_or_malformed_native_class_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            game = Path(folder)
            jar = game / 'projectzomboid.jar'
            for name in (world_import.PLAYER_DB_CLASS, 'other/Native.class'):
                with zipfile.ZipFile(jar, 'w') as archive:
                    archive.writestr(name, b'unreviewed native implementation')
                with self.subTest(class_name=name), self.assertRaises(ValueError):
                    world_import.verify_player_api(game)
            jar.write_bytes(b'not a zip archive')
            with self.assertRaisesRegex(ValueError, 'Cannot verify'):
                world_import.verify_player_api(game)
            jar.unlink()
            with self.assertRaisesRegex(ValueError, 'Cannot verify'):
                world_import.verify_player_api(game)

"""Require real rendered scene receipts and screenshot files for this fixture."""
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
PNG = b'\x89PNG\r\n\x1a\n'


def verify(root, text):
    manifest = json.loads((HERE / 'manifest.json').read_text())
    if manifest['failure_marker'] in text or 'KahluaException' in text:
        raise ValueError('Inventory presentation fixture reported a failure')
    markers = ['[INVENTORY_SCREEN] SETUP nativeItems=15 externalOwners=false',
               '[INVENTORY_SCREEN] SORT count=7 bound=3 tail=4 selection=true anchor=true',
               manifest['completion_marker']]
    markers += ['[INVENTORY_SCREEN] DRAW ' + name + ' details=once bag=icons magazine=icons button=1 nativeTypes=true'
                for name in ('01-clean', '02-vanilla', '03-clean-again')]
    for marker in markers:
        if text.count(marker) != 1:
            raise ValueError('Missing/duplicate assertion evidence: ' + marker)
    expected = [name.removeprefix('inventory-').removesuffix('.png') for name in manifest['expected_screenshots']]
    if re.findall(r'\[INVENTORY_SCREEN\] SHOT (\S+)', text) != expected:
        raise ValueError('Missing/duplicate/reordered inventory screenshots')
    screenshots = []
    for name in manifest['expected_screenshots']:
        path = Path(root) / 'client1/Screenshots' / name
        if not path.is_file() or path.read_bytes()[:8] != PNG:
            raise ValueError('Missing/invalid screenshot: ' + str(path))
        screenshots.append(str(path))
    return {'screenshots': screenshots,
            'limits': ['EN single-player with programmatic native UI callbacks; no physical input, Host or pixel-level screenshot verdict.']}
